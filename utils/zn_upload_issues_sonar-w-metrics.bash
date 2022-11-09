#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script using CURL to upload SonarQube Issues and Metrics together to a
# pre-defined ZeroNorth Policy.
#
# Requires: curl, jq, sed
#
# Before using this script, sign-in to https://fabric.zeronorth.io to
# prepare a Receiver Policy that will accept the issues:
#
# 1) Go to znADM -> Scenarios. Locate the Product "SonarQube" and then
#    activate a Scenario. For upload purposes, the Scenario does not
#    have to point to a real SonarQube server. You can use dummy values
#    for the URL and the key.
#
# 2) Go to znADM -> Integrations -> Add Integration. Create a shell
#    integration. Select the "Artifact" Type and specify Initiate Scan
#    from as "Manual Issues Upload".
#
# 3) Go to znOPS -> Targets -> Add Target. Using the Integration(s) from
#    step 2, create a shell Target(s).
#
# 4) Go to znOPS -> Policies -> Add Policy. Create a Receiver policy
#    using the items from the above steps.
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
# 1) Stored in secure file and then referenced at run time by passing in
#    the name of the file as a parameter to this script.
# 2) Set as the value to the environment variable API_KEY like this:
#      export API_KEY=.....
# 3) Set as the value to the variable API_KEY within this script. See
#    the line below.
#
# IMPORTANT: An API key generated using the above method has life span
# of 1 calendar year.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."

SELF=`basename $0`

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# Read the inputs from the positional parameters.
########################################################################
if [ ! "$3" ]
then
    echo "
Usage: `basename $0` <policy ID> <issues data file> <metrics data file> [<key_file>]

  Examples:

  `basename $0` QIbGECkWRbKvhL40ZvsVWh MyIssuesFile.json MyMetricsFile.json KeyFile.txt
  `basename $0` QIbGECkWRbKvhL40ZvsVWh MyIssuesFile.json MyMetricsFile.json
  `basename $0` QIbGECkWRbKvhL40ZvsVWh MyIssuesFile.json DUMMY

where,
  <policy ID>    - The ID of the Policy you want to load the data to.

  <issues file>  - The path to the Sonar issues output JSON file.

  <metrics file> - The path to the Sonar metrics output JSON file. If
                   the name of the file is \"DUMMY\", the script will
                   skip metrics.

  <key_file>     - Optionally, the file with the ZeroNorth API key. If not
                   provided, will use the value in the API_KEY variable,
                   which can be supplied as an environment variable or
                   be set inside the script.
" >&2
    exit 1
fi

POLICY_ID="$1"; shift
print_msg "Policy ID: '${POLICY_ID}'"

ISSUES_DATA_FILE="$1"; shift
if [ ! -r $ISSUES_DATA_FILE ]; then
    print_msg "Can't read issues file '$ISSUES_DATA_FILE'! Exiting."
    exit 1
else
    print_msg "Issues file: '${ISSUES_DATA_FILE}'"
fi

METRICS_DATA_FILE="$1"; shift
if [ "DUMMY" == "$METRICS_DATA_FILE" ]; then
    print_msg "Will skip metrics processing."
else
    if [ ! -r $METRICS_DATA_FILE ]; then
        print_msg "Can't read issues file '$METRICS_DATA_FILE'! Exiting."
        exit 1
    else
        print_msg "Metrics file: '${METRICS_DATA_FILE}'"
    fi
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
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"


########################################################################
# Prepare the temporary work file
########################################################################
#
# Find a suitable working directory
#
[ "${TEMP}" ] && TEMP_DIR="${TEMP}" || TEMP_DIR="/tmp"

#
# Create the working file in the working directory
#
TEMP_FILE="${TEMP_DIR}/zn_upload.`date '+%s'`.tmp"
touch "${TEMP_FILE}"

if [ ! -e "${TEMP_FILE}" ]
then
    print_msg "Error creating '${TEMP_FILE}' for temporary working file."
    exit 1
fi

print_msg "Using '${TEMP_FILE}' for temporary working file."


########################################################################
# The below code does the following:
#
# 0) Look up the Policy ID and ensure it exists.
# 1) "Run" the Policy specified via the POLICY_ID variable. This returns
#    the resulting JOB_ID.
# 2) Post the issues to the JOB_ID from above.
# 3) "Resume" the job to allow ZeroNorth to process the posted issues.
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
pol_id=$(echo ${result} | sed 's/^{\"id\":\"//' | sed 's/\".*$//')

if [ ${POLICY_ID} == ${pol_id} ]; then
    print_msg "Policy with ID '${POLICY_ID}' found."
else
    print_msg "No matching policy found!!! Exiting."
    exit 1
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
result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{ \"tags\" : [ \"${SELF}\" ] }" "${URL_ROOT}/policies/${POLICY_ID}/run")

#
# Extract the Job ID from the response. It's needed it in the next step.
#
job_id=$(echo ${result} | sed 's/^.*jobId\":\"//' | sed 's/\".*$//')
print_msg "Got Job ID: '${job_id}'."


########################################################################
# 2) Post the issues.
########################################################################
print_msg "Preparing the two data files into a single data file for upload..."

echo -n "{
  \"issues\":" > ${TEMP_FILE}
cat "${ISSUES_DATA_FILE}" | jq '.issues' >> ${TEMP_FILE}

echo -n ",
  \"stats\":" >> ${TEMP_FILE}
if [ "DUMMY" == "${METRICS_DATA_FILE}" ]; then
    echo "[]" >> ${TEMP_FILE}
else
    cat "${METRICS_DATA_FILE}" | jq '.component.measures' >> ${TEMP_FILE}
fi

echo "}" >> ${TEMP_FILE}

if [ "DUMMY" == "${METRICS_DATA_FILE}" ]; then
    print_msg "Uploading issues..."
else
    print_msg "Uploading issues and metrics..."
fi

result=$(curl -X POST --header "Content-Type: multipart/form-data" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" --form "file=@${TEMP_FILE}" "${URL_ROOT}/onprem/issues/${job_id}")
echo $result


########################################################################
# 3) Resume the job to let it finish.
########################################################################
print_msg "Hang on..."
sleep 5

print_msg "Resuming Job to finish the process..."
curl -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${job_id}/resume"
echo


########################################################################
# 4) Loop, checking for the job status every 3 seconds.
########################################################################

while :
do
   result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${job_id}")
   JOB_STATUS=$(echo ${result} | sed 's/^.*\"status\":\"//' | sed 's/\".*$//')

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
# Done.
########################################################################
rm "${TEMP_FILE}" && print_msg "Temp file '${TEMP_FILE}' removed."
print_msg "Job '${job_id}' done with status '${JOB_STATUS}'."
