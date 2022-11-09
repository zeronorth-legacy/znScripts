#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to extract Supplemental Issues for all Applications. This version
# of the script has minor customizataions for Bridgestone.
#
# Requires curl, jq.
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
# of 10 calendar years.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."

MY_NAME=`basename $0`
CHUNK_SIZE=10


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Print the help info.
########################################################################
if [ ! "$3" ]
then
    echo "
Usage: $MY_NAME <since> <until|NOW> <tgtID> [<key_file>]

" >&2
    exit 1
fi

# Read the since value
if [ "$1" ]; then
    SINCE="$1"; shift
    print_msg "Will looks for jobs started on or after '${SINCE}' UTC..."
    # we need to massage the SINCE value to make it web safe
    SINCE=$(sed 's/:/%3A/g' <<< "$SINCE")
fi

# Read the until value
if [ "$1" ]; then
    UNTIL="$1"; shift
    print_msg "...and up to '${UNTIL}' UTC."
    # we need to massage the UNTIL value to make it web safe
    UNTIL=$(sed 's/:/%3A/g' <<< "$UNTIL")
fi

TGT_ID="$1"; shift
print_msg "Target ID: '${TGT_ID}'"

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
# Prep.
########################################################################
# Find a suitable working directory
[ "${TEMP}" ] && TEMP_DIR="${TEMP}" || TEMP_DIR="/tmp"

# Prepare the temporary work file.
TEMP_FILE="${TEMP_DIR}/zn_temp.`date '+%s'`.tmp"


########################################################################
# Look up the customer name.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")
cust_name=$(jq -r '.customer.data.name' <<< "$result")
print_msg "Customer = '$cust_name'"


########################################################################
# Function to get Target supplementa issues in managable chunk sizes.
#
# Inputs: Target ID
#         File to write to
# Output: The result, if successful, will be in the specified file.
########################################################################
echo "DEBUG: chunk size = $CHUNK_SIZE" >&2

tgt_id=${TGT_ID}
outfile=${TEMP_FILE}

# Initialize the outfile.
echo > "$outfile"

# Set the base URI.
uri_base="${URL_ROOT}/syntheticIssues/?targetId=${tgt_id}&limit=${CHUNK_SIZE}&since=${SINCE}"
[ "$UNTIL" != "NOW" ] && uri="${uri}&until=${UNTIL}"

# Interate until we have extracted all the data in chunks.
offset=0; total_count=0
while :
do
    echo "DEBUG: offset = $offset" >&2
    uri="${uri_base}&offset=${offset}"
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "$uri")
    echo "$result" >> ${TEMP_FILE}

    count=$(jq -r '.[1].count' <<< "$result")
    (( total_count = total_count + count ))
    ( [[ $count -lt $CHUNK_SIZE ]] || [[ $count -eq 0 ]] ) && break
    (( offset = offset + $CHUNK_SIZE ))
done
echo "DEBUG: count = $total_count" >&2


########################################################################
# Done.
########################################################################
[ "${TEMP_FILE}" ] && [ -w ${TEMP_FILE} ] && rm "${TEMP_FILE}" && print_msg "Temp file '${TEMP_FILE}' removed."
print_msg "Done."
