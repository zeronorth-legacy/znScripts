#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2019-Sep, support@zeronorth.io
#
# Script to extract Synthetic Issues for Targets. Requires curl, jq.
# Run the script without params to see HELP info.
########################################################################
#
# Before using this script, obtain your API key using the instructions
# outlined in the following KB article:
#
#   https://support.zeronorth.io/hc/en-us/articles/115003679033
#
# The API key can then be used in one of the following ways:
# 1) Stored in secure file and then referenced at run time.
# 2) Set as the value to the environment variable API_KEY.
# 3) Set as the value to the variable API_KEY within this script.
#
# IMPORTANT: An API key generated using the above method has life span
# of 1 calendar year.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$1" ]
then
    echo "
Usage: `basename $0` <target ID|ALL> [<key_file>]

  Example: `basename $0` QIbGECkWRbKvhL40ZvsVWh
           `basename $0` ALL key_file

where,
  <target ID> - The ID of the Target whose synthetic issues you want.
                Specify "ALL" to iterate through all Taregts.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
" >&2
    exit 1
else
    TARGET_ID="$1"; shift
#    print_msg "Target ID: '${TARGET_ID}'"
fi

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
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"

########################################################################
# Extract the list of Targets.
########################################################################
if [ "$TARGET_ID" == "ALL" ]
then
    #
    # Get the Isses for all the Targets.
    #
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets?limit=1000")
    list=$(echo "$result" | jq -r '.[0][]|.id+" "+.data.name')

    # Extract the Synthetic Issues for the Targets. Limit 1,000 each.
    echo "$list" | while read line
    do
        set $line; tid="$1"; shift; tname="$*"
        echo
        print_msg "----- Target ID: '$tid', Target Name: '$tname' -----"
        curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/syntheticIssues/?targetId=${tid}&limit=1000" | jq '.[0]'
    done
else
    #
    # Get the Issues for the specified Target only.
    #
    curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/syntheticIssues/?targetId=${TARGET_ID}&limit=1000" | jq '.[0]'
fi


########################################################################
# Done.
########################################################################
