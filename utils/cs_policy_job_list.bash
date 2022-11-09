#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., support@zeronorth.io
#
# Script to list the jobs for the specified policy. Prints out the job
# details, including job date, job ID, status, start/end datetimes, and
# duration in minutes.
#
# Requires: curl, jq
#
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


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}


########################################################################
# Print the help info.
########################################################################
if [ ! "$2" ]
then
    echo "
Script to list the jobs for the specified policy. Prints out the job
details, including job date, job ID, status, start/end datetimes, and
duration in minutes.


Usage: `basename $0` <policy ID> <since> [<key_file>]

where,
  <policy ID> - The ID of the Policy you want to check recent jobs for.

  <since>     - Date/time to start looking from. Must be in the ISO-8601
                format like YYYY-MM-DDThh:mm:ss in UTC.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.

Prints the timestamped diagnostic messages to STDERR while the actual
output is printed to STDOUT. Output is limited to 2000 records.


Examples:

  `basename $0` QIbGECkWRbKvhL40ZvsVWh 2020-06-01
  `basename $0` QIbGECkWRbKvhL40ZvsVWh 2020-06-01T00:00:00
" >&2
    exit 1
else
    POLICY_ID="$1"; shift
    SINCE="$1"; shift
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
API_LIMIT="2000"


########################################################################
# The below code does the following:
#
# 0) Look up the Policy ID and ensure it exists.
# 1) Retrieve the jobs list.
# 2) Print the jobs list, formatted into a CSV.
#
# After the above steps, you can see the results in the ZeroNorth UI.
########################################################################

########################################################################
# 0) Look up the Policy by ID to verify it exists.
########################################################################
#
# First, check to see if a Policy by same name exists
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/${POLICY_ID}")

# Extract the resulting policy ID
pol_id=$(echo ${result} | jq -r '.id')
pol_nm=$(echo ${result} | jq -r '.data.name')

if [ ${POLICY_ID} = ${pol_id} ]; then
    print_msg "Found Policy '${pol_nm}' with ID '${POLICY_ID}'."
else
    print_msg "No Policy with ID '${POLICY_ID}' found!!! Exiting."
    exit 1
fi


########################################################################
# 1) Retrieve the jobs list.
########################################################################
print_msg "Looking for jobs..."

result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/?policyId=${POLICY_ID}&since=${SINCE}&limit=${API_LIMIT}")

# Were there any jobs?
count=$(echo "$result" | jq -r '.[1].count')
if [ $count -lt 1 ]; then
    slack_msg "Policy '$pol_nm' (ID '${POLICY_ID}'), no jobs found."
    exit
fi
print_msg "Found $count job(s)."


########################################################################
# 2) Print the jobs list, formatted into a CSV.
########################################################################
print_msg "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "date,jobId,status,start,end,dur.(mins)"
echo "$result" | jq -r '
  .[0] | sort_by(.meta.created) | .[] |
  ((.meta.created|split("T"))|.[0])
  +","+.id
  +","+.data.status
  +","+((.meta.created|split("."))|.[0]|sub("T";" "))
  +","+((.meta.lastModified|split("."))|.[0]|sub("T";" "))
  +","+(
         (
           (
             (.meta.lastModified|sub(".[0-9][0-9][0-9]Z";"Z")|fromdate)
            -(.meta.created|sub(".[0-9][0-9][0-9]Z";"Z")|fromdate)
           )
           /60
         )|tostring
       )
'
print_msg "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

########################################################################
# The End
########################################################################
print_msg "Done."
