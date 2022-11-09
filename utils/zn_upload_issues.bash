#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2022, Harness, Inc., support@harness.io
#
# Script for uploading a scanner output file to a ZeroNorth Policy.
# Assumes that the file being uploaded is produced by a product that
# ZeroNorth has existing integration with.
#
# Requires: curl, sed
#           jq - if the input file is a NexusIQ JSON file
#           unzip - if the input file is a Fortify FPR file
#
# Before using this script sign-in to https://fabric.zeronorth.io to
# prepare a shell Policy that will accept the issues:
#
# 1) Go to znADM -> Scenarios. Locate and activate a Scenario for the
#    appropriate Product to match the JSON/XML document.
#
# 2) Go to znADM -> Integrations -> Add Integration. Create a shell
#    Integration of type "Custom" and set Initiate Scan From to "MANUAL".
#
# 3) Go to znOPS -> Targets -> Add Target. Using the Integration from
#    step 2, create a shell Target.
#
# 4) Go to znOPS -> Policies -> Add Policy. Create a shell policy using
#    the items from the above steps.
#
# Related information in ZeroNorth KB at:
#
#    https://support.zeronorth.io/hc/en-us/articles/115001945114
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


umask 077
trap "func_clean" exit

MY_NAME=`basename $0`
ZN_CURL_CONFIG=~/zn_curl_$$.config

# Find a suitable working directory
[ "${TEMP}" ] && TEMP_DIR="${TEMP}" || TEMP_DIR="/tmp"

# Set temporary work file path/name. Not always created or used.
TEMP_FILE="${TEMP_DIR}/zn_upload.`date '+%s'`.tmp"


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


#----------------------------------------------------------------------
# Functions to print time-stamped messages
#----------------------------------------------------------------------
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME:${BASH_LINENO[0]}  $1" >&2
}


#----------------------------------------------------------------------
# Function called by trap to cleaup on exit.
#----------------------------------------------------------------------
function func_clean {
    [ -f ${ZN_CURL_CONFIG} ] && rm -f ${ZN_CURL_CONFIG} && print_msg "Removed ${ZN_CURL_CONFIG}."
#    [ -f ${TEMP_FILE} ] && rm -f ${TEMP_FILE} && print_msg "Removed ${TEMP_FILE}."
}


#----------------------------------------------------------------------
# Function to exit the script with exit status 1 (error).
#----------------------------------------------------------------------
function func_die {
    print_msg "Exiting due to an error."
    exit 1
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$2" ]
then
    echo "
Script for uploading a scanner output file to a ZeroNorth Policy. Assumes
that the file being uploaded is produced by a product that ZeroNorth has
existing integration with, or that the file complies with ZeroNorth's
\"JSON v2\" standard file format.

Requires: curl, sed
          jq    - only if the input file is a NexusIQ JSON file
          unzip - only if the input file is a Fortify FPR file


Usage: $MY_NAME <policy ID> <data file> [<key_file>]

where,

  <policy ID> - The ID of the Policy you want to load the data to.

  <data file> - The path to the scanner output data file. The data file
                must be of output format from a scanner that ZeroNorth has
                existing integration with. Typically, data file is XML
                or JSON in format.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.


  Examples: $MY_NAME QIbGECkWRbKvhL40ZvsVWh MyDataFile
            $MY_NAME QIbGECkWRbKvhL40ZvsVWh MyDataFile my-key-file
" >&2
    exit 1
fi

POLICY_ID="$1"; shift
print_msg "Policy ID: '${POLICY_ID}'"

ISSUES_DATA_FILE="$1"; shift
print_msg "Data file: '${ISSUES_DATA_FILE}'"

# Read in the ZeroNorth API key.
[ "$1" ] && API_KEY=$(cat "$1")

if [ ! "$API_KEY" ]
then
    echo "No API key provided!"
    func_die
fi


########################################################################
# Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"


########################################################################
# Configure a secure curl config file.
#
# This file will be removed automatically by the trap set at the top of
# this script.
########################################################################
touch ${ZN_CURL_CONFIG} || func_die

echo "
header = \"${HEADER_ACCEPT}\"
header = \"${HEADER_CONTENT_TYPE}\"
header = \"${HEADER_AUTH}\"
" > ${ZN_CURL_CONFIG} || func_die


########################################################################
# The below code does the following:
#
# F) Preprocess a Fortify FPR file, by extracting the audit.fvdl file.
# P) Preprocess a Sonatype NexusIQ file.
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
# Prep.
########################################################################

# By default, the data file will be the one specified in the input.
data_file="${ISSUES_DATA_FILE}"


########################################################################
# F) If the data file is a Foritfy FPR, extract the audit.fvdl file.
########################################################################
result=$(echo "${ISSUES_DATA_FILE}" | egrep '\.fpr')
if [ "$result" ]; then
    print_msg "Looks like a Fortify FPR file."
    fname='audit.fvdl'

    print_msg "Extracting $fname..."
    unzip -p "${ISSUES_DATA_FILE}" "$fname" > "${TEMP_FILE}"
    if ( [ $? -ne 0 ] || [ ! -s "${TEMP_FILE}" ] ); then
        print_msg "Error while extracting '$fname' from '${ISSUES_DATA_FILE}'!"
        func_die
    fi
    print_msg "Extracted '$fname' to '${TEMP_FILE}'."
    data_file="${TEMP_FILE}"
fi


########################################################################
# P) If the data file is from NexusIQ, we need to pre-process it a bit.
########################################################################
result=$(grep '"coordinates":' "${ISSUES_DATA_FILE}" | wc -l)
if [ $result -gt 0 ]; then
    # So, we need to preprocess the NexusIQ file.
    print_msg "Looks like a Sonatype NexusIQ file."
    # Create the working file in the working directory
    touch "${TEMP_FILE}"
    # Check to see that we got a file created.
    if [ ! -e "${TEMP_FILE}" ]
    then
        print_msg "Error creating '${TEMP_FILE}' for temporary working file."
        func_die
    fi
    # Now, prepare the processed file.
    jq '[(.components[] | select(.securityData != null))]' "${ISSUES_DATA_FILE}" > ${TEMP_FILE}
    data_file="${TEMP_FILE}"
    print_msg "Data file preprocessd into '$TEMP_FILE'."
fi


########################################################################
# 0) Look up the Policy by ID to verify it exists.
########################################################################
#
# First, check to see if a Policy by the specified ID exists.
#
result=$(curl -s -X GET -K ${ZN_CURL_CONFIG} "${URL_ROOT}/policies/${POLICY_ID}")

# Extract the resulting policy ID
pol_id=$(echo "${result}" | sed 's/^{\"id\":\"//' | sed 's/\".*$//')

if [ "$POLICY_ID" == "$pol_id" ]; then
    print_msg "Policy with ID '${POLICY_ID}' found."
else
    print_msg "No matching policy found!!!"
    func_die
fi

# Check the Policy type.
pol_type=$(echo ${result} | sed 's/.*\"policyType\":\"//' | sed 's/\".*//')
if [ ${pol_type} != "manualUpload" ]; then
    print_msg "WARNING: Policy is not a 'manualUpload' type. This could lead to problems."
fi


########################################################################
# 1) Run the specified Policy. This creates a Job that will be in the
#    "PENDING" status, which means the job is waiting for issues to be
#    uploaded.
########################################################################
print_msg "Invoking Policy..."
result=$(curl -s -X POST -K ${ZN_CURL_CONFIG} "${URL_ROOT}/policies/${POLICY_ID}/run")

#
# Extract the Job ID from the response. It's needed it in the next step.
#
job_id=$(echo ${result} | sed 's/^.*jobId\":\"//' | sed 's/\".*$//')
print_msg "Got Job ID: '${job_id}'."


########################################################################
# 2) Post the issues
########################################################################
print_msg "Uploading the file..."
result=$(curl -X POST -K ${ZN_CURL_CONFIG} --form "file=@${data_file}" "${URL_ROOT}/onprem/issues/${job_id}")
echo "$result"


########################################################################
# 3) Resume the job to let it finish.
########################################################################
print_msg "Hang on..."
sleep 3

print_msg "Resuming Job to finish the process..."
curl -X POST -K ${ZN_CURL_CONFIG} "${URL_ROOT}/jobs/${job_id}/resume"
echo


########################################################################
# 4) Loop, checking for the job status every 3 seconds.
########################################################################
error=0
while :
do
   result=$(curl -s -X GET -K ${ZN_CURL_CONFIG} "${URL_ROOT}/jobs/${job_id}")
   JOB_STATUS=$(echo ${result} | sed 's/^.*\"status\":\"//' | sed 's/\".*$//')

   if   [ "${JOB_STATUS}" == "RUNNING" ]; then
      print_msg "Job '${job_id}' still running..."
   elif [ "${JOB_STATUS}" == "PENDING" ]; then
      print_msg "Job '${job_id}' still in PENDING state..."
   elif [ "${JOB_STATUS}" == "FINISHED" ]; then
       break
   elif [ "${JOB_STATUS}" == "FAILED" ]; then
       error=1
       break
   else
       print_msg "Unknown job status '${JOB_STATUS}'."
       error=1
       break
   fi

   sleep 3
done


########################################################################
# The End
########################################################################
print_msg "Job '${job_id}' done with status '${JOB_STATUS}'."
[ $error -gt 0 ] && exit 1 || exit 0
