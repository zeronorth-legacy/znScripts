#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2019-Jan, support@zeronorth.io
#
# Sample script run an existing scan Policy.
# Requires curl and sed in your PATH.
#
# Before using this script sign-in to https://fabric.zeronorth.io to
# prepare a shell Policy that will to what you need to do.
#
# Related information in ZeroNorth KB at:
#
#    https://support.zeronorth.io/hc/en-us/articles/115001945114
#
# BUGS: This script uses sed to parse JSON response from the API calls.
#       As a result, it may be susceptible to changes in the structure
#       of the JSON respones. A possible improvement is to replace the
#       use of sed with jq.
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
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$2" ]; then
    echo "
Usage: `basename $0` <key_file> <PolicyID> [{run options}]

  Example: `basename $0` MyAPIKeyFile OtzOhx2SRxWhKjz10kqrnW

where

  <key_file> - The file with the ZeroNorth API key. The file should
               contain only the API key as a single string.

  <PolicyID> - The ID of the Policy you want to run.


  Optionally, provide run options as a JSON object (enclosed in curly
  brackets) with the set of attributes applicable to the Policy you
  want to run. For example, to run a policy that imports Veracode scan
  results for a specify app_id and build_id:

    {\"veracodeApplicationLookupType\":\"byId\",\"appId\":\"123456\",\"buildId\":\"654321\"}


  It may be necessary to enlose the JSON object string in single quotes:

    `basename $0 ` .... '{\"veracodeApplicationLookupType\":\"byId\",\"appId\":\"123456\",\"buildId\":\"654321\"}'

" >&2
    exit 1
fi

API_KEY=$(cat "$1")
if [ $? != 0 ]; then
    print_msg "Can't read key file!!! Exiting."
    exit 1
fi
shift
print_msg "API_KEY read in."

POLICY_ID="$1"; shift
print_msg "Policy ID: '${POLICY_ID}'"

if [ "$1" ]; then
    CUSTOM_PARM="$1"; shift
    print_msg "Custom Params: '${CUSTOM_PARM}'"
fi

#
# Job ID is determined at run time
#
JOB_ID=""


########################################################################
# Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"
HEADER_AUTH="Authorization:${API_KEY}"


########################################################################
# The below code does the following:
#
# 0) Look up the Policy ID to verify it exists.
# 1) "Run" the Policy specified via the POLICY_ID variable. This returns
#    the resulting JOB_ID.
# 2) Loop, checking for the job status every 30 seconds.
# 3) Print the final status of the job.
#
# After the above steps, you can see the results in the ZeroNorth UI.
########################################################################

########################################################################
# 0) Look up the Policy ID to verify it exists.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/${POLICY_ID}")

# Extract the Policy Name just to acknowledge it.
pol_id=$(echo ${result} | sed 's/^{\"id\":\"//' | sed 's/\".*$//' )

if [ "${POLICY_ID}" != "${pol_id}" ]; then
    print_msg "ERROR: Specified Policy ID not found!!! Exiting."
    exit 1
fi

print_msg "Found matching Policy."


########################################################################
# 1) Run the specified Policy. This creates a Job that will be in the
#    "Pending" status, which means the job is waiting for issues to be
#    uploaded.
########################################################################
print_msg "Invoking Policy..."

# construct the runOptions if supplied as CUSTOM_PARM
custom_parm="{}"
if [ "$CUSTOM_PARM" ]; then
    print_msg "Using optional custom runOptions..."
    custom_parm="$CUSTOM_PARM"
fi

result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{
  \"options\": {
    \"runOptions\":${custom_parm}
  }
}" "${URL_ROOT}/policies/${POLICY_ID}/run")

#
# Extract the Job ID from the response. It's needed in the next step.
#
JOB_ID=$(echo ${result} | sed 's/^.*jobId\":\"//' | sed 's/\".*$//')

if [ "${JOB_ID}" == "{" ]; then
    print_msg "ERROR: failed to start the job. Existing."
    exit 1
fi
print_msg "Job '${JOB_ID}' started."


########################################################################
# 2) Loop, checking for the job status every 30 seconds.
########################################################################

while :
do
   result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${JOB_ID}")
   JOB_STATUS=$(echo ${result} | sed 's/^.*\"status\":\"//' | sed 's/\".*$//')

   if [ "${JOB_STATUS}" == "RUNNING" ]; then
      print_msg "Job '${JOB_ID}' still running..."
   elif [ "${JOB_STATUS}" == "PENDING" ]; then
      print_msg "Job '${JOB_ID}' still in PENDING state..."
   else
      break
   fi

   sleep 10
done


########################################################################
# 3) Print the final status of the job.
########################################################################
print_msg "Job '${JOB_ID}' done with status '${JOB_STATUS}'."
