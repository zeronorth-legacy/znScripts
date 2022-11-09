#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to rename an existing Target. The Target to rename can be
# specified by either the Target ID or the Target Name. If using the
# Target name, it must be unique or an error will result. Target name
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
Script to rename an existing Target. The Target to rename can be specified
by either the Target ID or the Target Name. If using the Target name, it
must be unique or an error will result. Target name matching will be case
insensitive.


Usage: $MY_NAME <tgt_name/ID> <tgt_new_name> [<key_file>]

where,

  <tgt_name/ID>  - The name or the ID of Target you want to rename.

  <tgt_new_name> - The new name to apply to the specified Target.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.


  Examples: $MY_NAME MyTarget MyNewTarget
            $MY_NAME WZ7GzckvTNWRI9C9f7mEgg MyNewTarget
            $MY_NAME WZ7GzckvTNWRI9C9f7mEgg MyNewTarget key_file
" >&2
    exit 1
fi

# Get the input Target name/ID.
TARGET="$1"; shift
print_msg "The Target to rename is: '${TARGET}'."

# Get the new Target name.
TGT_NEW_NAME="$1"; shift
print_msg "The new Target name to use is: '${TGT_NEW_NAME}'."

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
# Function to look up the Target ID based on the specified Target Name.
# Causes this script to exit if multiple name matches are found.
#
# INPUT:  Target name
# OUTPUT: Target ID, if unique match found. Otherwise, exits the script.
# NOTE:   Target look up by name is case insensitive.
#-----------------------------------------------------------------------
function func_find_tgt_by_name {
    tgt_name="$1"
    tgt_id=''

    # URL-encode for web safety.
    encode_tgt_name=$(echo ${tgt_name} | sed 's|:|%3A|g' | sed 's|/|%2f|g' | sed 's| |%20|g')

    # Look it up--case insensitive search!!!
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets/?name=${encode_tgt_name}")

    # How many possible matches?
    tgt_count=$(jq -r '.[1].count' <<< "$result")

    # Found 1 or more...need to look closer.
    if [ $tgt_count -gt 0 ]; then
        # Let's look for a full, but case-insensitive match.
        tgt_id=$(jq -r '.[0][]|select((.data.name|ascii_downcase)==("'"${tgt_name}"'"|ascii_downcase))|.id' <<< "$result")
        if   [ ! "$tgt_id" ]; then
            tgt_count=0
        else
            tgt_count=$(wc -l <<< "$tgt_id")
        fi
    fi

    # More than 1, die.
    if [ $tgt_count -gt 1 ]; then
        print_msg "Found multiple matches for the Target Name '${tgt_name}'!!! Exiting."
        exit 1
    # Exactly 1, we can use it!
    elif [ $tgt_count -eq 1 ]; then
        print_msg "Target '${tgt_name}' found with ID '${tgt_id}'."
    fi

    echo "$tgt_id"
}


#-----------------------------------------------------------------------
# Function to obtain the Target details by ID.
#
# INPUT:  Target ID.
# OUTPUT: The data section of the Target details
#-----------------------------------------------------------------------
function func_get_target_details {
    tgt_id="$1"

    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets/$tgt_id")

    # Check response code.
    response=$(echo "$result" | jq '.statusCode')
    if ([ "$response" != "null" ] && [ "$response" -gt 299 ] ); then
#        print_msg "ERROR: Target detail lookup failed."
        return
    fi

    # Acknowlege the find.
    tgt_name=$(echo "$result" | jq -r '.data.name')
    print_msg "Target details retrieved for '$tgt_name'."

    # Output just the data section, which is the core of what we need.
    echo "$result" | jq '.data'
}


#-----------------------------------------------------------------------
# Function to construct the Target data JSON for the rename.
#
# INPUT:  Target data, target_new_name
# OUTPUT: The modified Target data JSON
#-----------------------------------------------------------------------
function func_construct_rename {
    tgt_data="$1"
    tgt_new_name="$2"

    echo "$tgt_data" | jq '.name = "'"$tgt_new_name"'"'
}


########################################################################
# "MAIN" - process the user request by calling various function.
########################################################################

# Let's find the Target. First assume the user supplied the Target ID.
tgt_data=$(func_get_target_details "$TARGET")

# See if the ID lookup worked.
if [ "$tgt_data" ]; then
    tgt_id="$TARGET"
# No, so try by name.
else
    tgt_id=$(func_find_tgt_by_name "$TARGET")

    # Still didn't find it.
    if [ ! "$tgt_id" ]; then
        print_msg "ERROR: Target '$TARGET' not found. Exiting."
        exit 1
    fi

    # Finally, try my 2nd attempt to look up the Target details.
    tgt_data=$(func_get_target_details "$tgt_id")
fi

# Construct the JSON for the Target rename.
tgt_data=$(func_construct_rename "$tgt_data" "$TGT_NEW_NAME")

# Final touches to deal with old, bad data.
tgt_data=$(echo "$tgt_data" | jq '(if (.includeRegex == null) then (.includeRegex = []) else . end) | (if (.excludeRegex == null) then (.excludeRegex = []) else . end) | (if (.notifications == {} or .notifications == null) then (.notifications = []) else . end)')

#echo "DEBUG: resulting Target data json:
#$tgt_data" >&2

# The final step is to update the Target with the new details.
print_msg "Updating '$TARGET'..."
result=$(curl -s -X PUT --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "$tgt_data" "${URL_ROOT}/targets/$tgt_id")

# Check response code.
response=$(echo "$result" | jq '.statusCode')
if ([ "$response" != "null" ] && [ "$response" -gt 299 ] ); then
    print_msg "ERROR: Target update failed."
    exit 1
else
    print_msg "Updated the Target '$TARGET' with the new name '$TGT_NEW_NAME'."
fi


########################################################################
# The End
########################################################################
print_msg "Done."
