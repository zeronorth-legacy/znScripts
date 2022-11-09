#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# A script to mark ALL running jobs as FAILED. This is useful in cases
# where many jobs are hung due to whatever reasons.
#
# Requires curl, jq.
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
# of 1 calendar year.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."


########################################################################
# Constants
########################################################################
MAGIC_STRING="FAIL_ALL_MY_JOBS"
QUERY_LIMIT=4000

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
# Read the inputs from the positional parameters
########################################################################
if [ ! "$4" ]
then
    echo "
************************************************************************
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
************************************************************************

A script to mark ALL running jobs as FAILED. This is useful in cases where
many jobs are hung due to whatever reasons.


Usage: `basename $0` $MAGIC_STRING <since> <until> <limit> [<key_file>]

where,
  FAIL_ALL_MY_JOBS - Specify this string as the first parameter to confirm
                     that you mean it.

  <since>            Starting date/time to extract jobs from. The since value
                     is applied against the job start date/time. The format
                     is YYYY-MM-DDThh:mi:ss in UTC (ISO-8601). Examples,

                       2021-01-01
                       2021-01-01T01:00:00

  <until>            Ending date/time to extract jobs up to. The until value
                     is applied against the job end date/time. Use the same
                     format as for the <since> parameter. Specify 'NOW' if you
                     want all jobs to the current date/time.

  <limit>            Max # of jobs to retrieve and operate on.

  <key_file>       - Optionally, the file with the ZeroNorth API key.
                     If not provided, will use the value in the API_KEY
                     variable, which can be supplied as an environment
                     variable or be set inside the script.
" >&2
    exit 1
else
    JOB_ID="$1"; shift
    if [ "${JOB_ID}" != "$MAGIC_STRING" ]
    then
        print_msg "Confirmation string '$MAGIC_STRING' not provided. Exiting with no action."
        exit 1
    fi
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

# Read the limit value
if [ "$1" ]; then
    LIMIT="$1"; shift
    print_msg "Accepted list limit of ${LIMIT}."
else
    LIMIT="100"
    print_msg "Using default list limit of ${LIMIT}."
fi

# API Key
[ "$1" ] && API_KEY=$(cat "$1")

if [ ! "$API_KEY" ]
then
    echo "No API key provided! Exiting."
    exit 1
fi


########################################################################
# 0) Look up the customer name. It's a good test of the API_KEY.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")

# Check response code.
if [[ "$result" =~ '"statusCode":' ]]; then
    response=$(jq '.statusCode' <<< "$result")
    if [ $response -gt 299 ]; then
        print_msg "ERROR: API call for customer name look up failed:
${result}"
        exit 1
    fi
fi

cust_name=$(jq -r '.customer.data.name' <<< "$result")
if [ ! "$cust_name" ]; then
    print_msg "ERROR: unable to retrieve customer name. Exiting."
    exit 1
fi
print_msg "Customer = '$cust_name'"


########################################################################
# Prompt the user for final confirmation.
########################################################################
read -p "Are you sure you want to proceed? (y/n) " answer
if [ "$answer" != "y" ]; then
    print_msg "Aborting on user request. Exiting."
    exit
fi


########################################################################
# Iterate through the list of Policies (limited to 1,000 for now). For
# each Policy, identify the jobs in RUNNING/PENDING state, FAIL them.
#
# No real error checking here.
########################################################################
# Look up the Policies list.
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies?limit=${QUERY_LIMIT}")

# Extract the Policy IDs.
policies=$(echo "$result" | jq -r '.[0][] | .id+" "+.data.name')
p_count=$(echo "$policies" | wc -l)
print_msg "Found $p_count Policies."

echo "$policies" | while read p
do
    set $p; pid=$1; shift; pname="$*"
    (( p_num++ ))
    print_msg "================================================================"
    print_msg "${p_num}) Looking for jobs for policy '$pname' ($pid)..."

    # For each Policy ID, list the Jobs.
    uri="${URL_ROOT}/jobs?policyId=$pid&limit=${LIMIT}&since=${SINCE}"
    [ "$UNTIL" != "NOW" ] && uri="${uri}&until=${UNTIL}"
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "$uri")
    job_ids=$(echo "$result" | jq -r '.[0][] | select(.data.status=="PENDING" or .data.status=="RUNNING") | .id' | egrep -v '^$')

    # The following check is needed due to BASH behavior.
    if [ ! "$job_ids" ]
    then
        print_msg "Found no Jobs in PENDING or RUNNING state."
        continue
    fi

    j_count=$(echo "$job_ids" | wc -l)
    print_msg "Found $j_count Jobs in PENDING or RUNNING state."

    # For each job, mark it FAILED.
    echo "$job_ids" | while read jid
    do
        print_msg "----------------------------------------------------------"
        print_msg "Marking job '$jid' as 'FAILED'..."
        result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${jid}/fail")
        sleep 1
        result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${jid}")
        job_status=$(echo "$result" | jq -r '.data.status')
        print_msg "Job '$jid' now has status '${job_status}'."
    done
done


########################################################################
# Done.
########################################################################
print_msg "================================================================"
print_msg "DONE."
