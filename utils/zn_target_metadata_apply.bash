#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to list, apply, or delete the customerMetaData section of the
# Target specified by the Target name. Target name match is case 
# insensitive. If more than one match is found, dies.
#
# Requires: curl, sed, tr, jq
#
# NOT SUPPORTED ON MACOS DUE TO POSIX NON-COMPLIANCE.
# NOT SUPPORTED ON MACOS DUE TO POSIX NON-COMPLIANCE.
# NOT SUPPORTED ON MACOS DUE TO POSIX NON-COMPLIANCE.
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
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Sorry, MacOS not supported due to their Posix non-compliance.
########################################################################
if [ `uname` == "Darwin" ]; then
    print_msg "ERROR: MacOS not supported due to non-Posix compliance."
    exit 1
fi


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$3" ]
then
    echo "
Script for general inquiry and maintenance of key-value metadata ("tags")
for Targets. Use this script to find out what key-value pairs are on a
Target, to remove key-value pairs, to update existing key-value pairs, or
to add new key-value pairs. This script operates on the \"customerMetadata\"
attribute of a Target, not the \"tags[]\" attribute.

        NOT SUPPORTED ON MACOS DUE TO POSIX NON-COMPLIANCE.
        NOT SUPPORTED ON MACOS DUE TO POSIX NON-COMPLIANCE.
        NOT SUPPORTED ON MACOS DUE TO POSIX NON-COMPLIANCE.


Usage: $MY_NAME <tgt_name> <mode> <key[=value][:key=value,...]> [<key_file>]

where,

  <tgt_name>  - The name of the Target you want to apply the tags to. Use 'ALL'
                when using the 'FIND' mode.

  <mode>      - Must be one of:

                LIST   - Output the values of the specified keys. Specify
                         the \"ALL\" to list all existing key-value pairs.
                         For \"ALL\", the output will be in JSON format.
                APPLY  - Apply the specified key-value pairs, overwriting all
                         existing key-value pairs. See below for the syntax.
                ADD    - Add/update the specified key-value pairs, leaving the
                         other existing key-value pairs intact. See below for
                         the syntax.
                DELETE - Delete the specified key(s). Specify 'ALL' to delete
                         all key-value pairs.
                FIND   - Finds Targets that have the metadata by the specified
                         key (no values are supported yet). Must specify 'ALL'
                         for the Target name. Optionally specify 'ALL' as the
                         key to find all Targets with metadata, essentially
                         doing a full inventory.

  <key(s)>    - A list of key-value pairs delimited with ':'. Examples:

                  key=value
                  key1=value1:key2=value2
                  'key1=hello there : key2 =I am fine'
                  key1=value1:key2=value2:key3=val3a,val3b,val3c:key4=value4

                Presence of white space in/around keys or values will require
                correctly quoting this argument. White space around either the
                ':' separator, the '=' assignment operator, or the ',' between
                a multi-element value will be ignored.

                LIST: specify a list of keys (only) separated by ':'. Or specify
                      \"ALL\" to list all existing key-value pairs.

                APPLY: Apply the specified key-value pairs, replacing all
                       added. Existing keys be updated with the new values.

                ADD: Add/update the specified key-value pairs.

                DELETE: Delete the specified key(s). Specify 'ALL' to delete all
                        key-value pairs.

                FIND: Currently, only a single key is allowed. Specify 'ALL' as
                      the key to find all Targets with some metadata.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.


  Examples: $MY_NAME MyTarget LIST ALL
            $MY_NAME MyTarget LIST mykey
            $MY_NAME MyTarget APPLY key1=val1:key2=val2
            $MY_NAME MyTarget APPLY key1=val1:key2=val2:key3=val3a,val3b,val3c
            $MY_NAME MyTarget ADD key1=val1:key2=val2
            $MY_NAME MyTarget ADD key1=val1:key2=val2:key3=val3a,val3b,val3c
            $MY_NAME MyTarget DELETE ALL
            $MY_NAME MyTarget DELETE key1
            $MY_NAME MyTarget DELETE key1:key2
            $MY_NAME ALL FIND mykey
            $MY_NAME ALL FIND ALL
" >&2
    exit 1
fi

# Get the input Target name.
TGT_NAME="$1"; shift
print_msg "Target Name: '${TGT_NAME}'"

# Get the input mode.
MODE="$1"; shift
if ( [ "$MODE" != "LIST" ] && [ "$MODE" != "APPLY" ] && [ "$MODE" != "ADD" ] && [ "$MODE" != "DELETE" ] && [ "$MODE" != "FIND" ] ); then
    print_msg "ERROR: '$MODE' is not a valid mode. Exiting."
    exit 1
fi
print_msg "Mode: '${MODE}'"

# Get the tags(s). Will do further validation later.
KEYVALS="$1"; shift
print_msg "Data: '$KEYVALS'"

# For FIND, only "ALL" is accepted for the Target name.
if [ "$MODE" == "FIND" ] && [ "$TGT_NAME" != "ALL" ]; then
    print_msg "Only Target name 'ALL' is accepted for FIND. No action taken."
    exit
fi

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

TGTS_LIMIT=3000


########################################################################
# Preparse the input tags to separate lines for each key.
########################################################################
parsed=$(echo "$KEYVALS" | tr : '\n' | sed -e $'s/^[ \t]*//; s/[ \t]*$//; s/[ \t]*=[ \t]*/=/g; s/[ \t]*,[ \t]*/,/g')
# echo "DEBUG: Tags parsed
# $parsed" >&2


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
# INPUT:  Target data, pre-parsed keys.
# OUTPUT: The tag value if found, empty string otherwise. For ALL, the
#         tags found.
#-----------------------------------------------------------------------
function func_list_tags {
    tgt_data="$1"
    i_keyvals="$2"

    # The user asked to list all tags.
    if [ "$i_keyvals" == "ALL" ]; then
        echo "$tgt_data" | jq -r '(if (.customerMetadata != null) then .customerMetadata else empty end)'
        return
    fi

    # The user asked to check for one or more tag(s). We iterate through
    # the i_keyvals but we only check the first one to ensure that the
    # output is not ambiguous.
    while read input_key
    do
        value=$(echo "$tgt_data" | jq -r '.customerMetadata.'"$input_key")
        echo "$input_key = '$value'"
    done <<< "$i_keyvals"
}


#-----------------------------------------------------------------------
# Function to construct the Target data JSON for APPLY.
#
# INPUT:  Target data, pre-parsed key-value pairs.
#         Replaces all key-value pairs with the specified ones.
# OUTPUT: The modified Target data JSON.
#-----------------------------------------------------------------------
function func_construct_for_apply {
    tgt_data="$1"
    i_keyvals="$2"

    counter=0
    cmd=$(while read keyval
    do
        if [ $counter -le 0 ]; then
            echo -n '{'
        else
            echo -n ','
        fi
        (( counter = counter + 1 ))

        # Split key and value(s).
        IFS="=" read key val <<< "$keyval"

        # Quote the key name.
        key="\"$key\""

        # Process multi-value condition.
        if [[ "$val" =~ , ]]; then
            vals_array=$(echo -n '["'; echo -n "$val" | sed 's/,/","/g' ; echo '"]')
            val=$vals_array
        else
            val="\"$val\""
        fi

        # Resulting key/val pair.

        echo -n "$key:$val"
    done <<< $i_keyvals
    echo '}')

#    echo "DEBUG: cmd is:
#    $cmd" >&2

    # Construct the new JSON.
    echo "$tgt_data" | jq '.customerMetadata = '"$cmd"''
}


#-----------------------------------------------------------------------
# Function to construct the Target data JSON for ADD.
#
# INPUT:  Target data, pre-parsed key-value pairs.
#         Adds or updates matching key-value pairs with the specified ones.
# OUTPUT: The modified Target data JSON.
#-----------------------------------------------------------------------
function func_construct_for_add {
    tgt_data="$1"
    i_keyvals="$2"

    # Extract the customerMetadata section from tgt_data.
    cmd=$(jq '.customerMetadata' <<< "$tgt_data")
    # echo "DEBUG: cmd is:
    # $cmd" >&2

    while read keyval
    do
        # Split key and value(s).
        IFS="=" read key val <<< "$keyval"

        # Process multi-value condition.
        if [[ "$val" =~ , ]]; then
            vals_array=$(echo -n '["'; echo -n "$val" | sed 's/,/","/g' ; echo '"]')
            val=$vals_array
        else
            val="\"$val\""
        fi

        # echo "DEBUG: '$key:$val'" >&2
        cmd=$(jq '.'"$key"'='"$val"'' <<< "$cmd")
    done <<< $i_keyvals

    # echo "DEBUG: cmd is:
    # $cmd" >&2

    # Construct the new JSON.
    echo "$tgt_data" | jq '.customerMetadata = '"$cmd"''
}


#-----------------------------------------------------------------------
# Function to construct the Target data JSON for DELETE.
#
# INPUT:  Target data, pre-parsed key-value pairs. Specifying 'ALL' will
#         remove all metadata.
# OUTPUT: The modified Target data JSON.
#-----------------------------------------------------------------------
function func_construct_for_del {
    tgt_data="$1"
    i_keyvals="$2"

    # If ALL is specified, simple.
    if [ "$i_keyvals" == "ALL" ]; then
        jq '.customerMetadata = {}' <<< "$tgt_data"
        return
    fi

    # Else, extract the customerMetadata section from tgt_data.
    cmd=$(jq '.customerMetadata' <<< "$tgt_data")
    # echo "DEBUG: cmd is:
    # $cmd" >&2

    while read keyval
    do
        # Split key and value(s). Value is not used for delete.
        IFS="=" read key val <<< "$keyval"

        # echo "DEBUG: '$key'" >&2
        cmd=$(jq 'del(."'"$key"'")' <<< "$cmd")
    done <<< $i_keyvals

    # echo "DEBUG: cmd is:
    # $cmd" >&2

    # Construct the new JSON.
    echo "$tgt_data" | jq '.customerMetadata = '"$cmd"''
}


#-----------------------------------------------------------------------
# Function to find Targets that have the specified metadata tags by key.
#
# INPUT:  The key to search by
# OUTPUT: Prints the matching Targets to STDOUT.
#
# BUG: This function doesn't know how to search by "key=value".
#-----------------------------------------------------------------------
function func_find_targets_by_key {
    key="$1"

    # Retrieve the Targets list (could be long).
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets?limit=${TGTS_LIMIT}")

    # Filter the list for the matching Targets and print the findings.
    if [ "$key" == "ALL" ]; then
        jq -r '.[0][] | select(.data.customerMetadata != {}) | .id+"|"+.data.name+"|"+(.data.customerMetadata | tostring)' <<< "$result"
    else
        jq -r '.[0][] | select(.data.customerMetadata."'"$key"'" != null) | .id+"|"+.data.name+"|"+(.data.customerMetadata | tostring)' <<< "$result"
    fi
}

########################################################################
# "MAIN" - process the user request by calling various function.
########################################################################

if [ "$TGT_NAME" != "ALL" ]; then
    # Look up the Target. The function exits on error.
    tgt_id=$(func_lookup_target "$TGT_NAME")
    [ "$tgt_id" ] || exit 1

    # Look up the Target detail, getting back the Target data.
    tgt_data=$(func_get_target_details "$tgt_id")
    [ "$tgt_data" ] || exit 1
fi

# Process the input command.
if   [ "$MODE" == "LIST" ]; then
    func_list_tags "$tgt_data" "$parsed"; exit
elif [ "$MODE" == "APPLY" ]; then
    tgt_data=$(func_construct_for_apply "$tgt_data" "$parsed")
elif [ "$MODE" == "ADD" ]; then
    tgt_data=$(func_construct_for_add "$tgt_data" "$parsed")
elif [ "$MODE" == "DELETE" ]; then
    tgt_data=$(func_construct_for_del "$tgt_data" "$parsed")
elif [ "$MODE" == "FIND" ]; then
    func_find_targets_by_key "$parsed"; exit
else
    print_msg "ERROR: command '$MODE' is not (yet) supported."
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
