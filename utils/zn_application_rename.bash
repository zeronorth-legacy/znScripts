#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to rename an existing Application. The Application to rename
# can be specified by either the Application ID or the Application Name.
# If using the Application name, it must be unique or an error will
# result. Application name matching will be case insensitive.
#
# Requires: curl, sed, jq
#
########################################################################
# Before using this script, obtain your API key using the instructions
# outlined in the following KB article:
#
#   https://support.zeronorth.io/hc/en-us/articles/115003679033
#
# Save the API key as the sole content into a secured file, which will
# be refereed to as the "key file" when using this script.
#
# IMPORTANT: An API key generated using the above method has life span
# of 10 calendar years.
########################################################################
MY_NAME=`basename $0`

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Function to print time-stamped messages
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$2" ]
then
    echo "

Script to rename an existing Application. The Application to rename can
be specified by either the Application ID or the Application Name. If
using the Application name, it must be unique or an error will result.
Application name matching will be case insensitive.


Usage: $MY_NAME <app_name/ID> <app_new_name> [<key_file>]

where,

  <app_name/ID>  - The name or the ID of Application you want to rename.

  <app_new_name> - The new name to apply to the specified Application.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.


Examples: $MY_NAME MyApplication MyNewApplication
          $MY_NAME WZ7GzckvTNWRI9C9f7mEgg MyNewApplication
          $MY_NAME WZ7GzckvTNWRI9C9f7mEgg MyNewApplication key_file


See also: zn_target_rename.bash  
" >&2
    exit 1
fi

# Get the input Application name/ID.
APPLICATION="$1"; shift
print_msg "The Application to rename is: '${APPLICATION}'."

# Get the new Application name.
APP_NEW_NAME="$1"; shift
print_msg "The new Application name to use is: '${APP_NEW_NAME}'."

# Read in the API key.
[ "$1" ] && API_KEY=$(cat "$1")
if [ ! "$API_KEY" ]
then
    echo "No API key provided! Exiting."
    exit 1
fi


########################################################################
# Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"
HEADER_AUTH="Authorization:${API_KEY}"


########################################################################
#
#                        FUNCTION DEFINITIONS
#
########################################################################

#-----------------------------------------------------------------------
# Function to look up the Application ID based on the specified
# Application Name. Causes this script to exit if multiple name matches
# are found.
#
# INPUT:  Application name
# OUTPUT: Application ID, if unique match found. Else, exits the script.
# NOTE:   Application look up by name is case insensitive.
#-----------------------------------------------------------------------
function func_find_app_by_name {
    app_name="$1"
    app_id=''

    # URL-encode for web safety.
    encode_app_name=$(echo ${app_name} | sed 's|:|%3A|g' | sed 's|/|%2f|g' | sed 's| |%20|g')

    # Look it up--case insensitive search!!!
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications/?name=${encode_app_name}")

    # How many possible matches?
    app_count=$(jq -r '.[1].count' <<< "$result")

    # Found 1 or more...need to look closer.
    if [ $app_count -gt 0 ]; then
        # Let's look for a full, but case-insensitive match.
        app_id=$(jq -r '.[0][]|select((.data.name|ascii_downcase)==("'"${app_name}"'"|ascii_downcase))|.id' <<< "$result")
        if   [ ! "$app_id" ]; then
            app_count=0
        else
            app_count=$(wc -l <<< "$app_id")
        fi
    fi

    # More than 1, die.
    if [ $app_count -gt 1 ]; then
        print_msg "Found multiple matches for the Application Name '${app_name}'!!! Exiting."
        exit 1
    # Exactly 1, we can use it!
    elif [ $app_count -eq 1 ]; then
        print_msg "Application '${app_name}' found with ID '${app_id}'."
    fi

    echo "$app_id"
}


#-----------------------------------------------------------------------
# Function to obtain the Application details by ID.
#
# INPUT:  Application ID.
# OUTPUT: The data section of the Application details
#-----------------------------------------------------------------------
function func_get_application_details {
    app_id="$1"

    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications/$app_id")

    # Check response code.
    response=$(echo "$result" | jq '.statusCode')
    if ([ "$response" != "null" ] && [ "$response" -gt 299 ] ); then
#        print_msg "ERROR: Application detail lookup failed."
        return
    fi

    # Acknowlege the find.
    app_name=$(echo "$result" | jq -r '.data.name')
    print_msg "Application details retrieved for '$app_name'."

    # Output just the data section, which is the core of what we need.
    echo "$result" | jq '.data'
}


#-----------------------------------------------------------------------
# Function to construct the Application data JSON for the rename.
#
# INPUT:  Application data, application_new_name
# OUTPUT: The modified Application data JSON
#-----------------------------------------------------------------------
function func_construct_rename {
    app_data="$1"
    app_new_name="$2"

    echo "$app_data" | jq '
{
  "name": "'"$app_new_name"'",
  "description": .description,
  "targetIds": .targetIds,
  "typeOfRiskEstimate": .typeOfRiskEstimate,
  "technicalImpact": .technicalImpact,
  "businessImpact": .businessImpact,
}'

}


########################################################################
# "MAIN" - process the user request by calling various function.
########################################################################

# Let's find the Application. First assume the user supplied the Application ID.
app_data=$(func_get_application_details "$APPLICATION")

# See if the ID lookup worked.
if [ "$app_data" ]; then
    app_id="$APPLICATION"
# No, so try by name.
else
    app_id=$(func_find_app_by_name "$APPLICATION")

    # Still didn't find it.
    if [ ! "$app_id" ]; then
        print_msg "ERROR: Application '$APPLICATION' not found. Exiting."
        exit 1
    fi

    # Finally, try my 2nd attempt to look up the Application details.
    app_data=$(func_get_application_details "$app_id")
fi

# Construct the JSON for the Application rename.
app_data=$(func_construct_rename "$app_data" "$APP_NEW_NAME")

#echo "DEBUG: resulting Application data json:
#$app_data" >&2

# The final step is to update the Application with the new details.
print_msg "Updating '$APPLICATION'..."
result=$(curl -s -X PUT --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "$app_data" "${URL_ROOT}/applications/$app_id")

# Check response code.
response=$(echo "$result" | jq '.statusCode')
if ([ "$response" != "null" ] && [ "$response" -gt 299 ] ); then
    print_msg "ERROR: Application update failed."
    exit 1
else
    print_msg "Updated the Application '$APPLICATION' with the new name '$APP_NEW_NAME'."
fi


########################################################################
# The End
########################################################################
print_msg "Done."
