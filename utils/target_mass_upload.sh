#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., 2020-Feb, support@zeronorth.io
#
# Script using CURL and SED to look-up/or create Artifact type Targets,
# and SonarQube Data Load Policies using the specified Target and
# Policy names. If the named objects alredy exist, they are reused.
#
# Before using this script sign-in to https://fabric.zeronorth.io and
# ensure that the necessary Integration (must of type "Artifact") and
# appropriate Scenarios exist.
#
# 1) Go to FabricADM -> Scenarios. Locate and activate a Scenario for
#    the appropriate Products.
#
# 2) Go to FabricADM -> Integrations -> Add an "Artifact" type
#    Integration. In general, you need just one such Integration for
#    all your Artifact type Targets.
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

API_KEY=$(cat "$1"); shift
if [ $? != 0 ]; then
    echo "Can't read key file!!! Exiting."
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
# Variable Set Up
########################################################################

input="$1"
while IFS="," read -r a b c;
do	
	PROJECT_KEY="$a"
	echo "${PROJECT_KEY}"
	
in=$(echo $b | sed 's/ /%20/g')
integration=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/environments?name=${in}")
INTEGRATION_ID=$(echo ${integration} | jq -r '.[0][].id')
echo "${INTEGRATION_ID}"

sn=$c
scenario=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/scenarios?name=${sn}&expand=false")
SCENARIO_ID=$(echo ${scenario} | jq -r '.[0][].id')
echo "${SCENARIO_ID}"

./zn_create_target_n_sq_data_load_policy.bash $API_KEY $PROJECT_KEY $TARGET_ID $SCENARIO_ID

done < "$input"

	