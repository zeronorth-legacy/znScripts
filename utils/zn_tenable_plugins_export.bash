#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2022, ZeroNorth, Inc., support@harness.io
#
# Script for exporting Tenable.io Plugins inventory.
########################################################################
# Before using this script, prepare a KEY/SECRET file as described by
# the help message of this script (run this script with no parameters to
# see the help message).
########################################################################
CHUNK_SIZE=1000


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
Script for exporting Tenable.io Plugins inventory. All of them. The output
can be in either CSV format or in JSON format. For the CSV format, only the
following fields are printed:

  pluginId
  pluginName
  CPEs, concatenated with '|'


Usage: `basename $0` <key/secret file> ALL <CSV|JSON>

where,

  <keys file>  - The file with the Tenable API Key and the Secret. The
                 file should have the content in the following format:

                 API_ACCESS_KEY=.....
                 API_SECRET_KEY=.....

                 IMPORTANT: Ensure that the keys file is in Unix format.

  ALL          - Required string for safety.

  <CSV|JSON>   - Specify one of 'CSV' or 'JSON' as the desired output
                 format. If the CSV is selected, only the few essential
                 fields are printed. If the JSON is selected, the output
                 will be in chunks of ${CHUNK_SIZE} records.

Examples:

  `basename $0` key.txt ALL
  `basename $0` key.txt ALL > out.json
" >&2
    exit 1
fi

. $1; shift
[ $API_ACCESS_KEY ] && print_msg "API_ACCESS_KEY read in."
[ $API_SECRET_KEY ] && print_msg "API_SECRET_KEY read in."

ALL="$1"; shift
if [ "$ALL" != "ALL" ]; then
    print_msg "ERROR: Please, specify the required string 'ALL'. Exiting."
    exit 1
fi

FORMAT="$1"; shift
if [ "$FORMAT" != "CSV" ] && [ "$FORMAT" != "JSON" ]; then
    print_msg "ERROR: Format '$FORMAT' is not supported. Specify 'CSV' or 'JSON'."
    exit 1
fi
print_msg "Output format will be '$FORMAT'."


########################################################################
# Constants
########################################################################
TENABLE_URL="https://cloud.tenable.com/plugins/plugin"

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

# Here, we are dealing with poor API design by Tenable.io where it
# does not indicate the actual count returned for each page. So, we
# start by getting the total count of the agents to figure out how many
# iterations we need.

# Pagination prep.
p_limit=${CHUNK_SIZE}
p_pagenum=1

result=$(curl -s -X GET --header "${HEADER_AUTH}" --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${TENABLE_URL}?limit=1")

p_count=$(echo $result | jq -r '.total_count')
if [ -n "$p_count" ]; then
    print_msg "$p_count Plugins found."
else
    print_msg "ERROR: Unexpected response from Tenable API:
$result"
    exit 1
fi

# Compute the number of pages.
(( p_numpages = p_count / p_limit ))
(( p_remainder = p_count - ( p_limit * p_numpages ) ))
[ $p_remainder -gt 0 ] && (( p_numpages++ )) 

print_msg "Will retrieve $p_numpages pages of Plugins in chunks of ${p_limit} per page."

# Print the column headings.
[ "$FORMAT" == "CSV" ] && echo "pluginId,pluginName,CPEs"

# Retrieve the Plugins list, using pagination.
while :
do
    print_msg "Current page number = $p_pagenum"
    result=$(curl -s -X GET --header "${HEADER_AUTH}" --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" "${TENABLE_URL}?size=$p_limit&page=$p_pagenum")

    if [ "$FORMAT" == "CSV" ]; then
    jq -r '
    .data.plugin_details[] |
    (.id | tostring)
    +",\""+
    (.name | gsub("\"";"\"\""))
    +"\",\""+
    (
      if ( .attributes.cpe != null ) then
        (.attributes.cpe | join("|") | gsub("\"";"\"\""))
      else
        ""
      end
    )
    +"\""
' <<< "$result"
    elif [ "$FORMAT" == "JSON" ]; then
        echo "$result"
    else
        print_msg "ERROR: '$FORMAT' is an unsupported output format."
        exit
    fi

    # Compute for next page of results.
    (( p_pagenum++ ))
    [ $p_pagenum -gt $p_numpages ] && break
done    


########################################################################
# The End
########################################################################
print_msg "DONE."
