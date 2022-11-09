#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to upload a ZeroNorth JSONv2 format file to a ZeroNorth Policy.
# See https://support.zeronorth.io/hc/en-us/articles/360046876553 for
# details.
#
# Requires: curl, sed
#
# Before using this script sign-in to https://fabric.zeronorth.io to
# prepare a shell Policy that will accept the issues:
#
# 1) Go to znADM -> Scenarios. Locate and activate a JSONv2 Scenario for
#    the desired Target type.
#
# 2) Go to znADM -> Integrations -> Add Integration. Create a shell
#    Integration of the desired type.
#
# 3) Go to znOPS -> Targets -> Add Target. Using the Integration from
#    step 2, create a shell Target.
#
# 4) Go to znOPS -> Policies -> Add Policy. Create a shell policy using
#    the items from the above steps.
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
#
# IMPORTANT: An API key generated using the above method has life span
# of 1 calendar year.
#
########################################################################
MY_NAME=`basename $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1"
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$2" ]
then
    echo "
Script to upload a ZeroNorth \"JSONv2\" format JSON file to the ZeroNorth
platform.


Usage: $MY_NAME <policy ID> <data file> [<key_file>]

where,

  <policy ID> - The ID of the Policy you want to load the data to.

  <data file> - The path to the scanner output data file. The data file
                must be of output format from a scanner that ZeroNorth has
                existing integration with. Typically, data file is XML
                or JSON in format.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY environment
                variable.


  Examples: $MY_NAME QIbGECkWRbKvhL40ZvsVWh MyDataFile
            $MY_NAME QIbGECkWRbKvhL40ZvsVWh MyDataFile my-key-file
" >&2
    exit 1
else
    POLICY_ID="$1"; shift
    print_msg "Policy ID: '${POLICY_ID}'"
    ISSUES_DATA_FILE="$1"; shift
    print_msg "Data file: '${ISSUES_DATA_FILE}'"
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


########################################################################
# The below code does the following:
#
# 0) Look up the Policy ID and ensure it exists.
# 1) "Run" the Policy specified via the POLICY_ID variable. This returns
#    the resulting job_id.
# 2) Posts the issues to the job_id from above.
# 3) "Resume" the job to allow ZeroNorth to process the posted issues.
# 4) Loop, checking for the job status every 3 seconds.
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
pol_id=$(sed 's/^{\"id\":\"//; s/\".*$//' <<< "$result")

if [ ${POLICY_ID} == ${pol_id} ]; then
    print_msg "Policy with ID '${POLICY_ID}' found."
else
    print_msg "No matching policy found!!! Exiting."
    exit 1
fi

# Check the Policy type.
pol_type=$(sed 's/.*\"policyType\":\"//; s/\".*//' <<< "$result")
if [ ${pol_type} != "manualUpload" ]; then
    print_msg "WARNING: Policy is not a 'manualUpload' type. This could lead to problems."
fi


########################################################################
# 1) Run the specified Policy. This creates a Job that will be in the
#    "PENDING" status, which means the job is waiting for issues to be
#    uploaded.
########################################################################
print_msg "Invoking Policy..."
result=$(curl -s -X POST --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/${POLICY_ID}/run")

#
# Extract the Job ID from the response. It's needed it in the next step.
#
job_id=$(sed 's/^.*jobId\":\"//; s/\".*$//' <<< "$result")
print_msg "Got Job ID: '${job_id}'."


########################################################################
# 2) Post the JSON v2 issues
########################################################################
print_msg "Uploading the file..."
result=$(curl -X POST --header "Content-Type: multipart/form-data" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" --form "file=@${ISSUES_DATA_FILE}" "${URL_ROOT}/common/2/issues/${job_id}")
echo "$result"


########################################################################
# 3) Resume the job to let it finish.
########################################################################
print_msg "Hang on..."
sleep 3

print_msg "Resuming Job to finish the process..."
curl -X POST --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${job_id}/resume"
echo


########################################################################
# 4) Loop, checking for the job status every 3 seconds.
########################################################################
while :
do
   result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${job_id}")
   JOB_STATUS=$(sed 's/^.*\"status\":\"//; s/\".*$//' <<< "$result")

   if [ "${JOB_STATUS}" == "RUNNING" ]; then
      print_msg "Job '${job_id}' still running..."
   elif [ "${JOB_STATUS}" == "PENDING" ]; then
      print_msg "Job '${job_id}' still in PENDING state..."
   else
      break
   fi

   sleep 3
done


########################################################################
# The End
########################################################################
print_msg "Job '${job_id}' done with status '${JOB_STATUS}'."
