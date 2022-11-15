#!/bin/bash
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2019-Dec, support@zeronorth.io
#
# Script to clean out the onprem jobs queue. This is useful when, before
# launching the Integration Orchestrator for an account, to ensure that
# there aren't leftover jobs in the onprem jobs queue.
#
# Requires curl, cut, sed, and jq.
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
# Function to print time-stamped messages to STDERR
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$2" ]
then
    echo "
Use this script to clean up jobs in the onprem jobs queue. Clean up means
marking the jobs as FAILED.

Usage: `basename $0` CLEAN <count> [<key_file>]

  Examples: `basename $0` CLEAN 3
            `basename $0` CLEAN 0 MyKeyFile

where,
  CLEAN       - The first parameter must be the word \"CLEAN\" as a
                safety parameter.

  <count>     - The maximum number of jobs to clean from the onprem queue.
                Must be an integrater 0 or greater.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
" >&2
    exit 1
fi

MODE="$1"; shift
if [ "$MODE" != "CLEAN" ]; then
    print_msg "Invalid value '$MODE' for mode. Specify \"CLEAN\". Exiting!"
    exit 1
fi

COUNT="$1"; shift
if ! [ "$COUNT" -ge 0 ] 2>/dev/null
then
    print_msg "'$COUNT' is not a valid value for the maximum number of jobs to clean. Existing!"
    exit 1
fi
print_msg "Max jobs count: '${COUNT}'"

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


########################################################################
# FUNC:  Extract the job ID from the given JSON response, which
#        presumably is from the onprem jobs queue API endpoint (will err
#        otherwise). Under most conditions, the job ID is simple to get.
#        However, if the Policy for the onprem job has been archived,
#        the response from the onprem jobs queue will display an errror
#        about a "Resource" that can't be found. In such cases, we need
#        to find the job ID by searching using the Policy ID in that
#        error response.
#
# Input: The JSON response from the API call. Typically, it is message
#        that indicates some sort of Resource cannot be found, with the
#        ID of the resource (the Policy) in the body of the message.
#
# Returns the job ID if successful. Otherwise, "".
########################################################################
function get_job_id
{
    json="$*"
    job_id=''

    # Check to see if missing Policy situation.
    check=$(echo "$json" | egrep 'Resource with id: .* does not exist' | wc -l)

    if [ $check -eq 0 ]; then
        # Looks like we have the standard situation.
        job_id=$(echo "$json" | jq -r '.[0].payload.jobId')
    else
        # So, the onprem job belongs to an archived Policy...
        print_msg "Found an onprem job with missing Policy..."
        pid=$(echo "$json" | jq -r '.message' | cut -d "'" -f2)
        print_msg "The missing Policy ID was '$pid'."

        # Get the jobs for the Policy ID we found
        result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/?policyId=$pid")

        # Extract the first job in PENDING status
        pjid=$(echo "$result" | jq -r '.[0][] | select(.data.status=="PENDING") | .id')
        if [ ! "$pjid" ]; then
            print_msg "Can't find the expected Job ID. Moving on..."
        else
            job_id=$pjid
        fi
    fi

    echo $job_id
}


########################################################################
# 0) Look up the Policy by ID to verify it exists.
#
# The /onprem/jobs endpoint returns one job only. Therefore, the only
# way to see the next job is to mark the job into a state other than
# PENDING. So, for our purposes, we will mark each job as FAILED so that
# can iterate through them all.
########################################################################
j_count=0
while [ $j_count -lt $COUNT ]
do
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/onprem/jobs")

    # Extract the job ID.
#    job_id=$(echo "$result" | jq -r '.[0].payload.jobId')
    job_id=$(get_job_id "$result")

    # Got a Job ID.
    if ( [ "$job_id" ] && [ "$job_id" != "null" ] ); then
        print_msg "Found onprem job with ID '${job_id}'..."
        # Mark the job as FAILED
        result=$(curl -s -X POST --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${job_id}/fail")
        (( j_count = j_count + 1 ))
    else
        # If we get here, we didn't find any more jobs, or got an error.
        break
    fi

done


########################################################################
# The End
########################################################################
jobs="jobs"; [ $j_count -eq 1 ] && jobs="job"
print_msg "$j_count ${jobs} removed from the onprem jobs queue."
