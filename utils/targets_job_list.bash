#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., support@zeronorth.io
#
# Script to list the Targets and the most recent FINSIHED jobs count for
# each Target. Hard-coded to up to 1000 Targets.
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
if [ ! "$1" ]
then
    echo "
Usage: `basename $0` ALL [<key_file>]

  Example: `basename $0` ALL

where,
  ALL - Required parameter for safety.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.

Prints the timestamped diagnostic messages to STDERR while the actual
output is printed to STDOUT.
" >&2
    exit 1
fi

if [ $1 != "ALL" ]; then
    print_msg "ERROR: missing the required parameter 'ALL'. Exiting."
    exit 1
fi
shift

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
# 0) Look up the customer account.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")

cust_name=$(echo ${result} | jq -r '.customer.data.name')
print_msg "Customer Account: '$cust_name'"


########################################################################
# 1) Retrieve the Targets list.
########################################################################
#
# First, check to see if a Policy by same name exists
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets?limit=1000")

# How many Targets?
tgt_count=$(echo ${result} | jq -r '.[1].count')
print_msg "Found $tgt_count Targets."

# Extract the list of Target Names/IDs.
tgt_list=$(echo ${result} | jq -r '.[0][] | .id+"|"+.data.name')


########################################################################
# 2) For each Target, first locate Policies, and then for each Policy,
#    look up the most recent job. If no job ever, print just the Target
#    ID/Name.
########################################################################
# Print the column headings.
echo "target_name,policy_name,jobs"
echo "$tgt_list" | while IFS='|' read tgt_id tgt_name
do
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/?targetId=${tgt_id}")

    # How many Policies?
    pol_count=$(echo ${result} | jq -r '.[1].count')

    if [ $pol_count -eq 0 ]; then
#        print_msg "Target '$tgt_name' has no Policies."
        echo "${tgt_name},,"
    else
        # Get the Policies list.
        pol_list=$(echo ${result} | jq -r '.[0][] | .id+"|"+.data.name')

        # Iterate through the Policies.
        echo "$pol_list" | while IFS='|' read pol_id pol_name
        do
            # Look up the latest FINISHED job for each Policy.
            result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/?policyId=${pol_id}&limit=10")

            # Count the number of recent FINISHED jobs
            job_finished_count=$(echo ${result} | jq -r '.[0][] | select (.data.status == "FINISHED") | .id' | wc -l)
#            print_msg "Target '$tgt_name' Policy '$pol_name' has $job_finished_count FINISHED jobs."
            echo "${tgt_name},${pol_name},$job_finished_count"
        done
    fi

done


########################################################################
# The End
########################################################################
print_msg "Done."
