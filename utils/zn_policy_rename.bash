#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to rename an existing Policy. The Policy to rename can be
# specified by either the Policy ID or the Policy Name. If using the
# Policy name, it must be unique or an error will result. Policy name
# matching will be case insensitive.
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
Script to rename an existing Policy. The Policy to rename can be specified
by either the Policy ID or the Policy Name. If using the Policy name, it
must be unique or an error will result. Policy name matching will be case
insensitive.


Usage: $MY_NAME <pol_name/ID> <pol_new_name> [<key_file>]

where,

  <pol_name/ID>  - The name or the ID of Policy you want to rename.

  <pol_new_name> - The new name to apply to the specified Policy.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.


Examples: $MY_NAME MyPolicy MyNewPolicy
          $MY_NAME WZ7GzckvTNWRI9C9f7mEgg MyNewPolicy
          $MY_NAME WZ7GzckvTNWRI9C9f7mEgg MyNewPolicy key_file


See also: zn_target_rename.bash  
" >&2
    exit 1
fi

# Get the input Policy name/ID.
POLICY="$1"; shift
print_msg "The Policy to rename is: '${POLICY}'."

# Get the new Policy name.
POL_NEW_NAME="$1"; shift
print_msg "The new Policy name to use is: '${POL_NEW_NAME}'."

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
# Function to look up the Policy ID based on the specified Policy Name.
# Causes this script to exit if multiple name matches are found.
#
# INPUT:  Policy name
# OUTPUT: Policy ID, if unique match found. Otherwise, exits the script.
# NOTE:   Policy look up by name is case insensitive.
#-----------------------------------------------------------------------
function func_find_pol_by_name {
    pol_name="$1"
    pol_id=''

    # URL-encode for web safety.
    encode_pol_name=$(echo ${pol_name} | sed 's|:|%3A|g' | sed 's|/|%2f|g' | sed 's| |%20|g')

    # Look it up--case insensitive search!!!
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/?name=${encode_pol_name}")

    # How many possible matches?
    pol_count=$(jq -r '.[1].count' <<< "$result")

    # Found 1 or more...need to look closer.
    if [ $pol_count -gt 0 ]; then
        # Let's look for a full, but case-insensitive match.
        pol_id=$(jq -r '.[0][]|select((.data.name|ascii_downcase)==("'"${pol_name}"'"|ascii_downcase))|.id' <<< "$result")
        if   [ ! "$pol_id" ]; then
            pol_count=0
        else
            pol_count=$(wc -l <<< "$pol_id")
        fi
    fi

    # More than 1, die.
    if [ $pol_count -gt 1 ]; then
        print_msg "Found multiple matches for the Policy Name '${pol_name}'!!! Exiting."
        exit 1
    # Exactly 1, we can use it!
    elif [ $pol_count -eq 1 ]; then
        print_msg "Policy '${pol_name}' found with ID '${pol_id}'."
    fi

    echo "$pol_id"
}


#-----------------------------------------------------------------------
# Function to obtain the Policy details by ID.
#
# INPUT:  Policy ID.
# OUTPUT: The data section of the Policy details
#-----------------------------------------------------------------------
function func_get_policy_details {
    pol_id="$1"

    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/$pol_id")

    # Check response code.
    response=$(echo "$result" | jq '.statusCode')
    if ([ "$response" != "null" ] && [ "$response" -gt 299 ] ); then
#        print_msg "ERROR: Policy detail lookup failed."
        return
    fi

    # Acknowlege the find.
    pol_name=$(echo "$result" | jq -r '.data.name')
    print_msg "Policy details retrieved for '$pol_name'."

    # Output just the data section, which is the core of what we need.
    echo "$result" | jq '.data'
}


#-----------------------------------------------------------------------
# Function to construct the Policy data JSON for the rename.
#
# INPUT:  Policy data, policy_new_name
# OUTPUT: The modified Policy data JSON
#-----------------------------------------------------------------------
function func_construct_rename {
    pol_data="$1"
    pol_new_name="$2"

    echo "$pol_data" | jq '
{
  "name": "'"$pol_new_name"'",
  "description": .description,
  "environmentId": .environmentId,
  "environmentType": .environmentType,
  "targets": [{"id":.targets[].id}],
  "scenarioIds": .scenarioIds,
  "scenarioParameters": [],
  "policyType": .policyType,
  "policySite": .policySite,
  "permanentRunOptions": .permanentRunOptions
}'

}


########################################################################
# "MAIN" - process the user request by calling various function.
########################################################################

# Let's find the Policy. First assume the user supplied the Policy ID.
pol_data=$(func_get_policy_details "$POLICY")

# See if the ID lookup worked.
if [ "$pol_data" ]; then
    pol_id="$POLICY"
# No, so try by name.
else
    pol_id=$(func_find_pol_by_name "$POLICY")

    # Still didn't find it.
    if [ ! "$pol_id" ]; then
        print_msg "ERROR: Policy '$POLICY' not found. Exiting."
        exit 1
    fi

    # Finally, try my 2nd attempt to look up the Policy details.
    pol_data=$(func_get_policy_details "$pol_id")
fi

# Construct the JSON for the Policy rename.
pol_data=$(func_construct_rename "$pol_data" "$POL_NEW_NAME")

#echo "DEBUG: resulting Policy data json:
#$pol_data" >&2

# The final step is to update the Policy with the new details.
print_msg "Updating '$POLICY'..."
result=$(curl -s -X PUT --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "$pol_data" "${URL_ROOT}/policies/$pol_id")

# Check response code.
response=$(echo "$result" | jq '.statusCode')
if ([ "$response" != "null" ] && [ "$response" -gt 299 ] ); then
    print_msg "ERROR: Policy update failed."
    exit 1
else
    print_msg "Updated the Policy '$POLICY' with the new name '$POL_NEW_NAME'."
fi


########################################################################
# The End
########################################################################
print_msg "Done."
