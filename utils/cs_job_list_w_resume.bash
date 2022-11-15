#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to list jobs history for a customer account. Has options for
# forcing jobs into the "RESUME" status (not a common use case).
#
# Output: Customer name
#         Jobs start datetime (UTC)
#         Jobs end datetime (UTC)
#         Job ID
#         Job Status
#         Policy ID
#         Policy Name
#
########################################################################
#
# Before using this script, obtain your API_KEY via the UI.
# See KB article https://support.zeronorth.io/hc/en-us/articles/115003679033
#
# The API key can then be used in one of the following ways:
# 1) Stored in secure file and then setting API_KEY to the its path.
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
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$3" ]; then
    echo "
Script to list jobs history for a customer account. Has option for
forcing jobs into the \"RESUME\" status (not a common use case). Outputs
in CSV format with the following fields:

  Jobs start datetime (UTC)
  Jobs end datetime (UTC)
  Job ID
  Job Status
  Policy ID
  Policy Name


Usage: $MY_NAME <since> <until> <limit> [<job status>] [resume]

where,

  <since>       Starting date/time to extract jobs from. The since value
                is applied against the job start date/time. The format
                is YYYY-MM-DDThh:mi:ss in UTC (ISO-8601). Examples,

                  2021-01-01
                  2021-01-01T01:00:00

  <until>       Ending date/time to extract jobs up to. The until value
                is applied against the job end date/time. Use the same
                format as for the <since> parameter. Specify 'NOW' if you
                want all jobs to the current date/time.

  <limit>       Max # of jobs to retrieve

  <job status>  Optionally, the job status filter. This is one of:
                RUNNING, PENDING, FAILED, FINISHED

  resume        If <job status> of RUNNING or PENDING is specified, use
                this option to mark those jobs for Resume. This is useful
                when a whole batch of jobs need to be resumed to finish
                up their work. This is not a common use case.


  EXAMPLES:

   $MY_NAME 2021-01-01T01:00:00 100 PENDING
   $MY_NAME 2021-01-01T01:00:00 100 RUNNING
   $MY_NAME 2021-01-01T01:00:00 100 PENDING resume
   $MY_NAME 2021-01-01T01:00:00 100 RUNNING resume


  NOTE: This script first retrieves the jobs list and then filters. So, in the
  above example, if only 3 jobs are in PENDING status in the list of 100, the
  output is only 3 jobs, not 100 PENDING jobs.

  The environment variable API_KEY should either have the value of the API key
  or its value must be the path to the file that contains the API key.
" >&2
    exit 1
fi

# API Key
if [ ! "$API_KEY" ]
then
    echo "No API key provided! Exiting."
    exit 1
else
    # is it in a file?
    [ -f "${API_KEY}" ] && [ -r "${API_KEY}" ] && API_KEY=$(cat "${API_KEY}")
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

# Read the filter value
if [ "$1" ]; then
    STATUS="$1"; shift
    print_msg "Accepted job status filter '${STATUS}'."

fi

# Read the "Resume" option
if [ "$1" ]; then
    if ( [ $STATUS == "RUNNING" ] || [ $STATUS == "PENDING" ] )  && [ "$1" == "resume" ]; then
        RESUME=1
        print_msg "Will resumme found $STATUS jobs."
    fi
    shift
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
# 1) List all jobs for this account.
########################################################################
print_msg "Retrieving Jobs list..."
uri="${URL_ROOT}/jobs?limit=${LIMIT}&since=${SINCE}"
[ "$UNTIL" != "NOW" ] && uri="${uri}&until=${UNTIL}"
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "$uri")

# Check response code.
if [[ "$result" =~ '"statusCode":' ]]; then
    response=$(jq '.statusCode' <<< "$result")
    if [ $response -gt 299 ]; then
        print_msg "ERROR: API call for jobs look up failed:
${result}"
        exit 1
    fi
fi

# How many jobs?
count=$(jq -r '.[1].count' <<< "$result")

if   [ $count -eq 1 ]; then
    print_msg "Read ${count} job."
elif [ $count -gt 0 ]; then
    print_msg "Read ${count} jobs."
else
    print_msg "No jobs found. Exiting."
    exit
fi

# Print the column heading.
echo "custName,startDateTime(UTC),endDateTime(UTC),jobId,jobStatus,polId,polName"

# Extract the Jobs list.
jobs=$(jq -r '
  .[0]|sort_by(.meta.created)|.[] | "\"'"$cust_name"'\""
  +","+(if (.meta.created != null) then (.meta.created|split(".")|.[0]|sub("T";" ")|sub("Z";"")) else "" end)
  +","+(if (.meta.lastModified != null) then (.meta.lastModified|split(".")|.[0]|sub("T";" ")|sub("Z";"")) else "" end)
  +","+.id
  +","+.data.status
  +","+.data.policyId
  +",\""+.data.policyName+"\""
' <<< "$result")

# Filter by STATUS if needed
if [ "$STATUS" ]; then
    echo "$jobs" | grep $STATUS
    count=$(echo "$jobs" | grep $STATUS | wc -l)
    print_msg "$count jobs listed."
else
    echo "$jobs"
fi


########################################################################
# 2) Resume RUNNING or PENDING jobs
########################################################################
if [ "$RESUME" == '1' ]; then
    print_msg "Resuming above $STATUS jobs..."

    jlist=$(echo "$jobs" | grep $STATUS | cut -d ',' -f 4)
    while read jid
    do
        print_msg "Resuming Job ID $jid..."
        result=$(curl -s -X POST --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/$jid/resume")
        echo "$result"
        sleep 1
    done <<< "$jlist"
fi


########################################################################
# 3) Done.
########################################################################
print_msg "Done."
