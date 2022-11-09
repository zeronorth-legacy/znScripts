#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2019-Mar, support@zeronorth.io
#
# Sample script using CURL to list all policies for the account the user
# has access to (identified by the API_KEY in use). Required curl and jq
# in the PATH.
#
# Prints: Policy ID
#         Policy Name
#         Schedule Count (1 mean it has a schedule)
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


[ "$1" ] && API_KEY=$(cat "$1")

if [ ! "$API_KEY" ]
then
    echo "
Usage: `basename $0` [<key_file>]

  Example: `basename $0` MyKeyFile

where,
  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
" >&2
    exit 1
fi


########################################################################
# Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# 1) List all policies for this account.
########################################################################
print_msg "Retrieving Policies list..."
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies?limit=3000")

# Were there any Policies?
count=$(echo "$result" | jq -r '. | .[1].count')
if [ ! $count -gt 0 ]; then
    print_msg "No policies found. Exiting."
    exit
fi

# Exract the list of Policy ID and the Policy Name.
policies=$(echo ${result} | jq -r '. | .[0][] | .id+","+.data.name' )

# Print the field headers
echo 'polId,polName,polCount,activePolCount'

# For each Polity ID, look up the schedule.
echo "$policies" | while read policy
do
    pol_id=$(echo ${policy} | cut -d ',' -f 1)
    pol_nm=$(echo ${policy} | cut -d ',' -f 2)

    # Look up any Policy Schedule(s).
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/${pol_id}/schedules")

    # How many schedules?
    sch_no=$(echo ${result} | jq -r '. | .[1].count')

    # How many are in enabled state?
    act_no=$(echo ${result} | jq -r '.[0][].data.isEnabled' | grep 'true' | wc -l | xargs)

    # Print the result
    echo "${pol_id},${pol_nm},${sch_no},${act_no}"

    # Iterate through the Schedules and print the details
    echo "$result" | jq -r '.[0][].data | "  Schedule: ["+.pattern+"], isEnabled: "+(.isEnabled|tostring)'
done


########################################################################
# 2) Done.
########################################################################
print_msg "Done."
