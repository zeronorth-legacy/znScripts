#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2019-Jan, support@zeronorth.io
#
# Script using to export .nessus scan result files from a Nessus server.
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
# of 1 calendar year.
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
if [ ! "$3" ]
then
    echo "
Usage: `basename $0` <Nessus server URL> <scan ID> <keys file> 

  Example: `basename $0` https://nessus.my.com:8834 MyAPIKeysFile My_Scan_ID

where,

  <Nessus URL> - The URL to the Nessus server. For example:

                 http://nessus.my.com:8834 (leave out the trailing /)

  <scan ID>    - The Nessus scan ID. This script will extract the latest
                 scan results for the specified scan ID. You can obtain
                 the scan ID from the URL of the Nessus web UI.

  <keys file>  - The file with the Nessus API Key and the Secret. The
                 file should have the content in the following format:

                 API_ACCESS_KEY=.....
                 API_SECRET_KEY=.....

                 IMPORTANT: Ensure that the keys file is in Unix format.
" >&2
    exit 1
fi


NESSUS_URL="$1"; shift
print_msg "Nessus server URL: '$NESSUS_URL'"

SCAN_ID="$1"; shift
print_msg "Nessus scan ID: '$SCAN_ID'"

. $1; shift
[ $API_ACCESS_KEY ] && print_msg "API_ACCESS_KEY read in."
[ $API_SECRET_KEY ] && print_msg "API_SECRET_KEY read in."


########################################################################
# Constants
########################################################################
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"
HEADER_AUTH="X-ApiKeys: accessKey=$API_ACCESS_KEY; secretKey=$API_SECRET_KEY"
DOWNLOAD_FORMAT="nessus"


########################################################################
# The below code does the following:
#
# 0) Confirm that the scan ID provided can be found.
# 1) Determine the latest History ID.
# 2) Request a .nessus export.
# 3) Loop, checking for the readiness of the export file.
# 4) Download the file. The file is written to STDOUT.
########################################################################

########################################################################
# 0) Confirm that the scan ID provided can be found.
########################################################################
# Look for the scan ID info
result=$(curl -k -s -X GET --header "${HEADER_AUTH}" --header "${CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${NESSUS_URL}/scans/${SCAN_ID}")

# Check to see if the scan ID was found
err_msg=$(echo "$result" | jq '.error')
if [ "$err_msg" != "null" ]; then
    print_msg "ERROR: could not locate scan ID '$SCAN_ID'. Exiting"
    exit 1
fi
scan_name=$(echo $result | jq -r '.info.name')
print_msg "Scan ID '$SCAN_ID' found with name '$scan_name'."


########################################################################
# 1) Determine the latest History ID.
########################################################################
# Is there any scan history?
history=$(echo "$result" | jq -r '.history')
if [ "$history" == "null" ]; then
    print_msg "INFO: No history of completed scans to export. Exiting."
    exit 0
fi

# Extract the latest history ID.
last_hid=$(echo "$history" | jq -r 'last(.[] | select(.status=="completed")).history_id')
if [ "$last_hid" == "null" ]; then
    print_msg "INFO: No scans to export. Exiting."
    exit 0
fi
print_msg "Most recent history ID is '$last_hid'."


########################################################################
# 2) Request a .nessus export.
########################################################################
# Requst the export. This start the background process in the Nessus
# server to prepare the file and provides a file ID.
result=$(curl -k -s -X POST --header "${HEADER_AUTH}" --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${NESSUS_URL}/scans/${SCAN_ID}/export?history_id=${last_hid}" -d '{"format": "nessus"}')

# Get the export file ID
fid=$(echo "$result" | jq -r '.file')
if ( [ ! "$fid" ] || [ "$fid" == "null" ] ); then
    print_msg "ERROR: request for export failed. Exiting."
    exit 1
fi
print_msg "Export file ID is '$fid'."


########################################################################
# 3) Loop, checking for the readiness of the export file.
########################################################################
while :
do
    # Get status.
    result=$(curl -k -s -X GET --header "${HEADER_AUTH}" --header "${CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${NESSUS_URL}/scans/${SCAN_ID}/export/${fid}/status")

    # Is it ready?
    status=$(echo "$result" | jq -r '.status')
    if [ "$status" == "ready" ]; then
        print_msg "Export file is ready!"
        break
    fi

    print_msg "Export file '$fid' status is still '$status'..."
    sleep 5
done


########################################################################
# 4) Download the file. The file is written to STDOUT.
#
# NOTE: Once the file is downloaded, the file ID cannot be reused.
########################################################################
curl -k -s -X GET --header "${HEADER_AUTH}" --header "${CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${NESSUS_URL}/scans/${SCAN_ID}/export/${fid}/download"

if [ ! $? ]; then
    print_msg "ERROR: Export file download failed!"
    exit 1
fi
print_msg "Export file download completed."


########################################################################
# The End
########################################################################
# We don't print anything else here, since the above step will write its
# output to STDOUT.
