#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# A utility script to mark a job as FAILED. Useful when a job has died
# or has completed, but still shows up as running.
#
# Requires curl, jq
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
#
# IMPORTANT: An API key generated using the above method has life span
# of 10 calendar years.
#
########################################################################
MY_NAME=`basename $0`
MY_DIR=`dirname $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME:${BASH_LINENO[0]}  $1" >&2
}


########################################################################
# Function to check ZeroNorth REST API response code.
#
# NOTE: This function is not recommended when dealing with large amount
# of response data as the value of the data to evaluate is being passed
# as a copy of the original.
########################################################################
function func_check_response {
    result="$1"

    if [[ "$result" =~ '"statusCode":' ]]; then
        response=$(jq '.statusCode' <<< "$result")
        if [ "$response" -gt 299 ]; then
            print_msg "ERROR: API call returned error response code ${response}, with message:
${result}"
            return 1
        fi
    fi
}


########################################################################
# HELP information and input params
########################################################################
if [ ! "$1" ]
then
    echo "
A utility script to mark a job as FAILED. Useful when a job has died
or has completed, but still shows up as running.


Usage: $MY_NAME <Job ID> [<key_file>]

where,

  <job ID>   - The ID of the Job you want to mark FAILED.

  <key_file> - Optionally, the file with the ZeroNorth API key. If not
               provided, will use the value in the API_KEY variable,
               which can be supplied as an environment variable or be
               set inside the script.
" >&2
    exit 1
fi

# Read in the job ID.
JOB_ID="$1"; shift

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
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"


########################################################################
# Look up the customer name. It's a good test of the API_KEY.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")
func_check_response "$result" || exit 1

cust_name=$(jq -r '.customer.data.name' <<< "$result")
if [ ! "$cust_name" ]; then
    print_msg "ERROR: unable to retrieve customer name. Exiting."
    exit 1
fi
print_msg "Customer: '$cust_name'"


########################################################################
# The below code does the following:
#
# 0) Look up the Job ID to verify it exists.
# 1) Attempts to mark the job as FAILED.
# 2) Print the resulting status of the job.
#
# After the above steps, you can see the results in the ZeroNorth UI.
########################################################################

########################################################################
# 0) Look up the Job ID to verify it exists.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${JOB_ID}")
func_check_response "$result" || exit 1

# Try to extract the Job ID to match to the specified ID.
job_id=$(jq -r '.id' <<< "$result")
pol_nm=$(jq -r '.data.policyName' <<< "$result")

if [ "${JOB_ID}" == "${job_id}" ]; then
    print_msg "Found Job ID '${job_id}' for Policy '$pol_nm'."
else
    print_msg "Job ID '${JOB_ID}' not found. Exiting."
    exit 1
fi


########################################################################
# 1) Mark the job as FAILED.
########################################################################
print_msg "Marking Job as 'FAILED'..."
result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${job_id}/fail")
func_check_response "$result" || exit 1


########################################################################
# 2) Get the resulting job status.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${JOB_ID}")
func_check_response "$result" || exit 1

job_status=$(jq -r '.data.status' <<< "$result")

print_msg "Job '${JOB_ID}' now has status '${job_status}'."


########################################################################
# Done.
########################################################################
print_msg "Done."
