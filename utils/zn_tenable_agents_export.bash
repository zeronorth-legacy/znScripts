#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script for exporting Tenable.io Agents inventory. Automatically pages
# through the agents, 1000 agents at a time until done. The output is
# written out to STDOUT in CSV format.
########################################################################
# Before using this script, prepare a KEY/SECRET file as described by
# the help message of this script (run this script with no parameters to
# see the help message).
########################################################################
MY_NAME=`basename $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$2" ]
then
    echo "
Script for exporting Tenable.io Agents inventory. Automatically pages
through the agents, 1000 agents at a time until done. The output is
written out to STDOUT in CSV format.


Usage: $MY_NAME ALL <key/secret file>

where,

  ALL          - Required keyword for safety.

  <keys file>  - The file with the Tenable API Key and the Secret. The
                 file should have the content in the following format:

                 API_ACCESS_KEY=.....
                 API_SECRET_KEY=.....

                 IMPORTANT: Ensure that the keys file is in Unix format.


Examples:

  $MY_NAME ALL key.txt
" >&2
    exit 1
fi

# Required safety param.
SAFETY="$1"; shift
if [ $SAFETY != "ALL" ]
then
    print_msg "ERROR: You must specify 'ALL' as the first parameter. Exiting."
    exit 1
fi

. $1; shift
[ "$API_ACCESS_KEY" ] && print_msg "API_ACCESS_KEY read in."
[ "$API_SECRET_KEY" ] && print_msg "API_SECRET_KEY read in."
if [ ! "$API_ACCESS_KEY" ] || [ ! "$API_SECRET_KEY" ]; then
    print_msg "ERROR: The access key and/or the secret key missing. Exiting."
    exit 1
fi


########################################################################
# Constants
########################################################################
TENABLE_URL="https://cloud.tenable.com"

DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"
HEADER_AUTH="X-ApiKeys: accessKey=$API_ACCESS_KEY; secretKey=$API_SECRET_KEY"


########################################################################
# The below code does the following:
#
# Uses the API endpoint for listing Agents by Scanner ID. HOWEVER, we do
# NOT need to interate through the scanners, because that option is not
# meaningful as confirmed with our Tenable.io technical contacts.
#
# Pagination logic is used.
########################################################################
# Set the scanner ID to '0' since it's not really used.
s_id=0

# Here, we are dealing with poor API design by Tenable.io where it
# does not indicate the actual count returned for each page. So, we
# start by getting the total count of the agents to figure out how many
# iterations we need.
result=$(curl -s -X GET --header "${HEADER_AUTH}" --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${TENABLE_URL}/scanners/$s_id/agents?limit=1")

a_count=$(echo $result | jq -r '.pagination.total')
print_msg "$a_count Agents found."

# Print the column headings.
echo "agentID,agentUUID,agentName,Status,platform,distro,ip,coreVersion,lastScanned,lastConnect,linkedOn,pluginFeedDdate,groups"

# Pagination prep.
a_limit=1000
a_offset=0
print_msg "Will retrieve Agents in chunks of ${a_limit}."

# Retrieve the Agents list, using pagination.
while :
do
    print_msg "Current offset = $a_offset"
    result=$(curl -s -X GET --header "${HEADER_AUTH}" --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${TENABLE_URL}/scanners/$s_id/agents?limit=$a_limit&offset=$a_offset")
    echo $result | \
        jq -r '.agents[] |
(.id|tostring)
+","+.uuid
+","+.name
+","+.status
+","+.platform
+","+.distro
+","+.ip
+","+.core_version
+","+(if .last_scanned == null then "" else ((.last_scanned|todate|split(".")|.[0]|sub("T";" ")|sub("Z";""))) end)
+","+(if .last_connect == null then "" else ((.last_connect|todate|split(".")|.[0]|sub("T";" ")|sub("Z";""))) end)
+","+(if .linked_on == null then "" else ((.linked_on|todate|split(".")|.[0]|sub("T";" ")|sub("Z";""))) end)
+","+(if .plugin_feed_id == null then "" else ((.plugin_feed_id|strptime("%Y%m%d%H%M")|mktime|todate|split(".")|.[0]|sub("T";" ")|sub("Z";""))) end)
+","+([.groups[].name] | join("|"))
'
    # Compute for next page of results.
    (( a_offset = a_offset + a_limit ))
    [ $a_offset -ge $a_count ] && break
#    exit
done    


########################################################################
# The End
########################################################################
print_msg "DONE."
