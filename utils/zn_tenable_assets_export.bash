#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., 2020-Apr, support@zeronorth.io
#
# Script for exporting Tenable.io Assets inventory.
########################################################################
# Before using this script, prepare a KEY/SECRET file as described by
# the help message of this script (run this script with no parameters to
# see the help message).
########################################################################

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$1" ]
then
    echo "
Usage: `basename $0` <key/secret file> [<since>]

  Example: `basename $0` MyKeySecretFile

where,

  <keys file>  - The file with the Tenable API Key and the Secret. The
                 file should have the content in the following format:

                 API_ACCESS_KEY=.....
                 API_SECRET_KEY=.....

                 IMPORTANT: Ensure that the keys file is in Unix format.

  [<since>]    - OPTIONAL. Specify the number of days to look back. If
                 not specified, the default is 180 days.

Examples:

  `basename $0` key.txt
  `basename $0` key.txt 60
  `basename $0` key.txt 60 > out.json
" >&2
    exit 1
fi

. $1; shift
[ $API_ACCESS_KEY ] && print_msg "API_ACCESS_KEY read in."
[ $API_SECRET_KEY ] && print_msg "API_SECRET_KEY read in."

since=180; [ "$1" ] && since=$1
print_msg "Will look back $since days."

# Prepare the time string to use later.
now=$(date '+%s')
(( ss = now - ( 86400 * $since) ))
#echo "DEBUG: ss = '$ss'"


########################################################################
# Constants
########################################################################
TENABLE_URL="https://cloud.tenable.com/assets/export"
CHUNK_SIZE=10000

DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"
HEADER_AUTH="X-ApiKeys: accessKey=$API_ACCESS_KEY; secretKey=$API_SECRET_KEY"
DOWNLOAD_FORMAT="nessus"


########################################################################
# The below code does the following:
#
# 1) Request an Asset export.
# 2) Loop, checking for the readiness of the export file.
# 3) Download the file. The file is written to STDOUT.
########################################################################


########################################################################
# 1) Request an Asset export.
########################################################################
# Requst the export. This start the background process in the Nessus
# server to prepare the file and provides a file ID.
result=$(curl -k -s -X POST --header "${HEADER_AUTH}" --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${TENABLE_URL}" -d "
{
  \"chunk_size\" : $CHUNK_SIZE,
  \"filters\" : {
    \"updated_at\" : $ss
  }
}
")

# Get the export file ID
uuid=$(echo "$result" | jq -r '.export_uuid')
if ( [ ! "$uuid" ] || [ "$uuid" == "null" ] ); then
    print_msg "ERROR: request for export failed. Exiting."
    exit 1
fi
print_msg "Export UUID is '$uuid'."


########################################################################
# 2) Loop, checking for the readiness of the export.
########################################################################
while :
do
    # Get status.
    result=$(curl -k -s -X GET --header "${HEADER_AUTH}" --header "${CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${TENABLE_URL}/${uuid}/status")

    # Is it ready?
    status=$(echo "$result" | jq -r '.status')
    if [ "$status" == "FINISHED" ]; then
        chunks=$(echo "$result" | jq -r '.chunks_available[]')
        no_chunks=$(echo "$result" | jq -r '.chunks_available[-1]')
        print_msg "Export is ready, with $no_chunks chunk(s)!"
        break
    fi

    print_msg "Export '$uuid' status is still '$status'..."
    sleep 5
done


########################################################################
# 3) Download the result by iterating through the chunks. The output is
# written to STDOUT. Note that each chunk is an Array. So, if multiple
# chunks are being extracted, you will get a concatenation of arrays in
# your output.
########################################################################
echo "$chunks" | while read cid
do
    print_msg "Extracting chunk '$cid'..."
    curl -k -s -X GET --header "${HEADER_AUTH}" --header "${CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${TENABLE_URL}/${uuid}/chunks/$cid"

    if [ ! $? ]; then
        print_msg "ERROR: Extration failed!"
        exit 1
    fi
    print_msg "Extraction successful."
done


########################################################################
# The End
########################################################################
print_msg "DONE."
