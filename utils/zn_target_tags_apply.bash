#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., support@zeronorth.io
#
# Script to replace or amend the tags for a Target.
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
if [ ! "$3" ]
then
    echo "
Script for general inquiry and maintenance of tags for Targets. Use this
script to find out what tags are on a Target, to remove tags, to update
existing tags, or to add new tags. Note that this script only operates on
the \"tags[]\" attribute of a Target, not the \"customerMetadata\" attribute.


Usage: $MY_NAME <tgt_name> <mode> <tag(s)> [<key_file>]

where,

  <tgt_name>  - The name of the Target you want to apply the tags to.

  <mode>      - Must be one of:

                LIST - Outputs \"1\" if the specified tag is found, \"0\" otherwise.
                       Can only check 1 specific tag at per script run.
                       Specify tag value of \"ALL\" to list existing tags.
                ADD - add the specified tag(s).
                UPDATE - replace the tags with the specified tag(s).
                DELETE - delete the specified or all existing tags.

  <tag(s)>    - A comma-delimited list of tags. If any of the tags contain
                white space, be sure to quote this argument correctly. Any
                white space around the comma separator will be ignored.

                For the LIST mode, specify the tag name \"ALL\" to list all
                existing tags.

                For the ADD mode, only the tags that are not already on the
                specified Target will be added.

                For the DELETE mode, specify the tag name \"ALL\" to delete
                all existing tags.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.


  Examples: $MY_NAME MyTarget ADD foo
            $MY_NAME MyTarget ADD \"foo,bar\"
            $MY_NAME MyTarget DELETE \"bar\"
            $MY_NAME MyTarget UPDATE \"foo, bar\" zn_key_file
" >&2
    exit 1
fi

# Get the input Target name.
TGT_NAME="$1"; shift
print_msg "Target Name: '${TGT_NAME}'"

# Get the input mode.
MODE="$1"; shift
if ( [ "$MODE" != "LIST" ] && [ "$MODE" != "ADD" ] && [ "$MODE" != "UPDATE" ]  && [ "$MODE" != "DELETE" ] ); then
    print_msg "ERROR: '$MODE' is not a valid mode. Exiting."
    exit 1
fi
print_msg "Mode: '${MODE}'"

# Get the tags(s). Will do further validation later.
TAGS="$1"; shift
print_msg "Tags: '$TAGS'"

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
# First, parse the input tags, breaking them out to separate lines.
########################################################################
INPUT_TAGS=$(while read tag
do
    echo "$tag"
done <<< $(echo "$TAGS" | sed 's/,/\n/g' | sed 's/^[ \t]*//' | sed 's/[ \t]*$//'))

#echo "DEBUG: tags are:
#$INPUT_TAGS" >&2


########################################################################
#
#                        FUNCTION DEFINITIONS
#
########################################################################

#-----------------------------------------------------------------------
# Function to look up the Target ID based on the specified Target Name.
#
# INPUT:  Target name
# OUTPUT: Target ID, if unique match found. Otherwise, exits the script.
# NOTE:   Target look up by name is case insensitive.
#-----------------------------------------------------------------------
function func_lookup_target {
    tgt_name="$1"

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
    # Target not found, die.
    else
        print_msg "Target '${tgt_name}' does not exist!!! Exiting."
        exit 1
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
        print_msg "ERROR: Target detail lookup failed."
        return
    fi

    # Output just the data section, which is the core of what we need.
    echo "$result" | jq '.data'
}


#-----------------------------------------------------------------------
# Function to process the LIST command.
#
# INPUT:  Target data, tags.
# OUTPUT: 1 if found 0 other wise. For ALL, the list of tags found.
#-----------------------------------------------------------------------
function func_list_tags {
    tgt_data="$1"
    i_tags="$2"

    # The user asked to list all tags.
    if [ "$i_tags" == "ALL" ]; then
        echo "$tgt_data" | jq -r '(if (.tags != null) then .tags[] else empty end)'
        return
    fi

    # The user asked to check for one or more tag(s). We iterate through
    # the i_tags but we only check the first one to ensure that the
    # output is not ambiguous.
    while read input_tag
    do
        echo "$tgt_data" | jq -r '.tags | (if ( index("'"$input_tag"'") != null) then 1 else 0 end)'
        return # We only check one input tag, the first one.
    done <<< "$i_tags"
}


#-----------------------------------------------------------------------
# Function to construct the Target data JSON for ADD.
#
# INPUT:  Target data, tags.
#         Only adds tags that are not already on the Target.
# OUTPUT: The modified Target data JSON.
#-----------------------------------------------------------------------
function func_construct_for_add {
    tgt_data="$1"
    i_tags="$2"

    # We first need to create a merged list of tags between what's on
    # the Target and what the user wanted to add.

    # Get the tags on the Target.
    t_tags=$(func_list_tags "$tgt_data" "ALL")

    # Merge the two tags lists.
    u_tags="$i_tags"
    [ "$t_tags" ] && u_tags=$(echo "$u_tags
$t_tags" | sort -u)

    # Construct the new JSON.
    func_construct_for_upd "$tgt_data" "$u_tags"
}


#-----------------------------------------------------------------------
# Function to construct the Target data JSON for UPDATE.
#
# INPUT:  Target data, tags.
#         WARNING!!! Existing tags are completely replaced.
# OUTPUT: The modified Target data JSON.
#-----------------------------------------------------------------------
function func_construct_for_upd {
    tgt_data="$1"
    i_tags="$2"

    tags=''
    while read tag
    do
        tags="${tags}\",\"$tag"
    done <<< "$i_tags"
    tags=$(echo "${tags}\"" | sed 's/^\",//')

    echo "$tgt_data" | jq '.tags = ['"$tags"']'
}


#-----------------------------------------------------------------------
# Function to construct the Target data JSON for DELETE.
#
# INPUT:  Target data, tags. Special tags "ALL" will remove all tags.
# OUTPUT: The modified Target data JSON.
#-----------------------------------------------------------------------
function func_construct_for_del {
    tgt_data="$1"
    i_tags="$2"

    if [ "$i_tags" == "ALL" ]; then
        tgt_data=$(echo "$tgt_data" | jq '.tags = null')
    else
        while read tag
        do
            tgt_data=$(echo "$tgt_data" | jq '(if (.tags != null) then (.tags -= ["'"$tag"'"]) else . end)')
        done <<< "$i_tags"
    fi

    echo "$tgt_data"
}


########################################################################
# "MAIN" - process the user request by calling various function.
########################################################################

# Look up the Target. The function exits on error.
tgt_id=$(func_lookup_target "$TGT_NAME")
[ "$tgt_id" ] || exit 1

# Look up the Target detail, getting back the Target data.
tgt_data=$(func_get_target_details "$tgt_id")
[ "$tgt_data" ] || exit 1

# Process the input command.
if   [ "$MODE" == "LIST" ]; then
    func_list_tags "$tgt_data" "$INPUT_TAGS"; exit
elif [ "$MODE" == "ADD" ]; then
    tgt_data=$(func_construct_for_add "$tgt_data" "$INPUT_TAGS")
elif [ "$MODE" == "UPDATE" ]; then
    tgt_data=$(func_construct_for_upd "$tgt_data" "$INPUT_TAGS")
elif [ "$MODE" == "DELETE" ]; then
    tgt_data=$(func_construct_for_del "$tgt_data" "$INPUT_TAGS")
else
    print_msg "ERROR: command '$MODE' is not supported."
    exit 1
fi

# Final touches to deal with old, bad data.
tgt_data=$(echo "$tgt_data" | jq '(if (.includeRegex == null) then (.includeRegex = []) else . end) | (if (.excludeRegex == null) then (.excludeRegex = []) else . end) | (if (.notifications == {} or .notifications == null) then (.notifications = []) else . end)')
#echo "DEBUG: resulting Target data json:
#$tgt_data" >&2

# The final step is to update the Target with the new details.
print_msg "Updating '$TGT_NAME'..."
result=$(curl -s -X PUT --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "$tgt_data" "${URL_ROOT}/targets/$tgt_id")

# Check response code.
response=$(echo "$result" | jq '.statusCode')
if ([ "$response" != "null" ] && [ "$response" -gt 299 ] ); then
    print_msg "ERROR: Target update failed."
    exit 1
else
    print_msg "Updated '$TGT_NAME'."
fi


########################################################################
# The End
########################################################################
print_msg "Done."
