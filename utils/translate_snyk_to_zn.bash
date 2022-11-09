#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., 2020-Feb, support@zeronorth.io
########################################################################
# This is script is designed to take in a list of information about
# SNYK projects and organizations and pull out all of the isssues
# from them and convert them over to ZN targets and policies
#
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
MY_DIR="`dirname $0`"
########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}

########################################################################
# Set Up Main Variable and Conditions
########################################################################

if [ ! "$2" ]
then
    echo "
Usage: `basename $0` <snyk key file> <zn key file> <snyk org name> <snyk org id> <snyk proj name> <snyk proj id> <snyk project type>

  Example: `basename $0` SnykAPIKeyFile ZnApiKeyFile MySnykOrg MySnykOrgId MySnykProjName MySnykProjID npm
where,
  <SNYK key file>    - The file with the SNYK API keys. The file should
                    contain only the API key as a single string.

  <ZN key file>      - The file with the ZeroNorth API keys. The file should
                    contain only the API key as a single string.
  <snyk org name>    -  Name of the Snyk Organization

  <snyk org id>      - Snyk Organization ID

  <snyk proj name>   - Name of the Snyk Project

  <snyk proj id>     - Snyk Project ID

  <snyk proj type>   - Type of Snyk Project
  
" >&2
    exit 1
fi

SNYK_API_KEY=$(cat "$1"); shift
if [ $? != 0 ]; then
    echo "Can't read SNYK key file! Exiting."
    exit 1
fi

ZN_API_KEY=$(cat "$1");
if [ $? != 0 ]; then
    echo "Can't read ZN key file! Exiting."
    exit 1
fi

ZN_API_KEY_FILE=$1; shift
if [ $? != 0 ]; then
    echo "Can't find ZN key file! Exiting."
    exit 1
fi

SNYK_ORG_NAME=$1; shift
if [ $? != 0 ]; then
    echo "Can't read snyk org name! Exiting."
    exit 1
fi

SNYK_ORG_ID=$1; shift
if [ $? != 0 ]; then
    echo "Can't read snyk org id! Exiting."
    exit 1
fi

SNYK_NAME_PROJECT=$1; shift
if [ $? != 0 ]; then
    echo "Can't read snyk proj name! Exiting."
    exit 1
fi

SNYK_ID_PROJ=$1; shift
if [ $? != 0 ]; then
    echo "Can't read snyk proj id! Exiting."
    exit 1
fi

SNYK_TYPE_PROJ=$1; shift
if [ $? != 0 ]; then
    echo "Can't read snyk project type! Exiting."
    exit 1
fi

TARGET_LIST_FILE=$1; shift
if [ $? != 0 ]; then
    echo "Can't find file to list targets that need to be created! Exiting."
    exit 1
fi

TMP_DIR=$1; shift
if [ $? != 0 ]; then
    echo "Can't find tmp dir to store files! Exiting."
    exit 1
fi

SNYK_TMP_FILE=$1; shift
if [ $? != 0 ]; then
    echo "Can't find tmp file to store snyk issues! Exiting."
    exit 1
fi
ZN_TMP_FILE=$1; shift
if [ $? != 0 ]; then
    echo "Can't find tmp file to store zn datafile! Exiting."
    exit 1
fi

ZN_POLICY_NAME="${SNYK_NAME_PROJECT} Snyk"
ZN_TARGET_NAME=$(echo $SNYK_NAME_PROJECT | cut -f1 -d:)

########################################################################
# Constants
########################################################################
# used for API calls
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH_SNYK="Authorization: token ${SNYK_API_KEY}"
HEADER_AUTH_ZN="Authorization: ${ZN_API_KEY}"
SNYK_URL="https://snyk.io/api/v1/org"

# used for translation
JQ_FILTER="jq.snyk_issues.filter"

# used for uploading to ZN
UPLOAD_SCRIPT="zn_upload_json_v2_issues.bash"

# used for policy creation
INTEGRATION_ID="d_HbyHQyRWugeKDWaftb-w"
INTEGRATION_TYPE="github"
POLICY_TYPE="manualUpload"
SCENARIO_ID="SZandU60TjS4LxAJdiGDgA"

# print Snyk and ZN to console
echo -e "
+----------------+
| Snyk Org Name  | ${SNYK_ORG_NAME}
+----------------+
| Snyk Org ID    | ${SNYK_ORG_ID}
+----------------+
| Snyk Proj Name | ${SNYK_NAME_PROJECT}
+----------------+
| Snyk Proj ID   | ${SNYK_ID_PROJ}
+----------------+
| ZN Target Name | ${ZN_TARGET_NAME}
+----------------+
| ZN Policy Name | ${ZN_POLICY_NAME}
+----------------+
"

########################################################################
# Look up the Policy by Name to verify it exists.
# If there are more than 1 policy with that name, exit.
# If there are no policies with that name and a target exists, create it
########################################################################
#
# First, check to see if a Policy by name exists
#
echo "Checking if policy named '${ZN_POLICY_NAME}' exists..."
encode_ZN_POLICY_NAME=$(echo ${ZN_POLICY_NAME} | sed 's|:|%3A|g' | sed 's|/|%2f|g' | sed 's| |%20|g')
pol_result=$(curl -s -X GET -H "${HEADER_ACCEPT}" -H "${HEADER_AUTH_ZN}" "${URL_ROOT}/policies/?name=${encode_ZN_POLICY_NAME}")
#echo -e "pol_result is:\n${pol_result}"

#
# How many matching policies?
#
pol_count=$(echo ${pol_result} | jq -r '.|.[1].count')

# more than 1, exit
if [ $pol_count -gt 1 ]; then
    echo "Found multiple matches for the Policy Name '${ZN_POLICY_NAME}'! Exiting."
    exit
# exactly 1, we can use it
elif [ $pol_count -eq 1 ]; then
    PolId=$(echo ${pol_result} | jq -r '.|.[0][]|.id')
    echo "Found 1 policy."
    echo "PolicyID is '${PolId}'"
# if 0, check for target than create it
elif [ $pol_count -eq 0 ]; then
    echo "Did not find a policy named '${ZN_POLICY_NAME}'."
    echo "Will create policy if a target named '${ZN_TARGET_NAME}' exists."
    encode_ZN_TARGET_NAME=$(echo ${ZN_TARGET_NAME} | sed 's|/|%2f|g')
    #echo $encode_ZN_TARGET_NAME
    tar_result=$(curl -s -X GET -H "${HEADER_ACCEPT}" -H "${HEADER_AUTH_ZN}" "${URL_ROOT}/targets/?name=${encode_ZN_TARGET_NAME}")
    #echo $tar_result | jq

    #
    # How many matching targets?
    #
    tar_count=$(echo ${tar_result} | jq -r '.| .[1].count')
    
    # if more than 1, exit
    if [ $tar_count -gt 1 ]; then
        echo "Found multiple matches for the target name '${ZN_TARGET_NAME}'! Exiting."
        exit
    # if exactly 1 target use it to create policy
    elif [ $tar_count -eq 1 ]; then
        TarId=$(echo ${tar_result} | jq -r '.|.[0][]|.id')
        echo "A target with the name '${ZN_TARGET_NAME}' exists."
        echo "Creating a policy with name '${ZN_POLICY_NAME}'"
        # contstruct params
        pol_params="{\"name\": \"${ZN_POLICY_NAME}\",\"environmentId\": \"${INTEGRATION_ID}\",\"environmentType\": \"${INTEGRATION_TYPE}\",\"targets\": [{\"id\": \"${TarId}\"}],\"policyType\": \"${POLICY_TYPE}\",\"scenarioParameters\": [],\"scenarioIds\": [\"${SCENARIO_ID}\"]}"
        #echo $pol_params | jq
    
        #
        # create policy
        #
        pol_result=$(curl -s -X POST -H "${HEADER_CONTENT_TYPE}" -H "${HEADER_ACCEPT}" -H "${HEADER_AUTH_ZN}" -d "${pol_params}" "${URL_ROOT}/policies")
        #echo "curl -s -X POST -H '${HEADER_CONTENT_TYPE}' -H '${HEADER_ACCEPT}' -H '${HEADER_AUTH_ZN}' -d '${pol_params}' '${URL_ROOT}/policies'"
        #echo $pol_result
        
        #
        # extract policy id
        #
        PolId=$(echo ${pol_result} | jq -r '.id')
        PolName=$(echo ${pol_result} | jq -r '.data.name')
        echo "Created policy '$PolName'." 
        echo "Policy ID '$PolId'"
        ZN_POLICY_NAME="$PolName"
        echo "$ZN_POLICY_NAME"
    # if 0, do not create a target, exit
    elif [ $tar_count -eq 0 ]; then
        echo "A target with the name '${ZN_TARGET_NAME}' does not exist."
        echo "Create this target or remove item from list. Exiting..."
        echo "${ZN_TARGET_NAME}" >> $TARGET_LIST_FILE
        exit
    fi
fi


########################################################################
# SNYK API Call and Export
########################################################################
echo "Storing snyk project data in '${SNYK_TMP_FILE}'"
result=$(curl -s -X POST -H "${DOC_FORMAT}" -H "${HEADER_AUTH_SNYK}" "${SNYK_URL}/${SNYK_ORG_ID}/project/${SNYK_ID_PROJ}/issues" | jq > ${SNYK_TMP_FILE})
#echo "curl -X POST -H "${DOC_FORMAT}" -H "${HEADER_AUTH_SNYK}" "${SNYK_URL}/${SNYK_ORG_ID}/project/${SNYK_ID_PROJ}/issues""

########################################################################
# Translate SNYK API Output to ZN JSON Schema
########################################################################
echo "Translating Snyk API output to ZeroNorth JSON schema..."
cat ${SNYK_TMP_FILE} | jq -rf ${JQ_FILTER} > ${ZN_TMP_FILE}
echo "Finished translation."


########################################################################
# Use the $UPLOAD_SCRIPT to upload ZN_TMP_FILE
########################################################################

if [ ! "`which ${MY_DIR}/${UPLOAD_SCRIPT}`" ]
then
    print_msg "Can't find '${UPLOAD_SCRIPT}'. Make sure it's installed in '${MY_DIR}'."
    exit 1
fi

print_msg "Invoking '${UPLOAD_SCRIPT}' to upload the results..."

${MY_DIR}/${UPLOAD_SCRIPT} ${PolId} ${ZN_TMP_FILE} ${ZN_API_KEY_FILE}