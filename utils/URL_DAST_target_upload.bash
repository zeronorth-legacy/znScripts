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
#
# PLEASE REMOVE HTTP:// or HTTPS:// from list of URLs
########################################################################

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}

########################################################################
# Constants

# For this you will need 2 separate files, these files will be added
# to the runtime call:
#	1. The first will contain the API Key of the environment you are
#	uploading to
#	2. The second will be the exported JSON of your Projects that are tied
# 	to the Integration and Scenario IDs listed at runtime

########################################################################

if [ ! "$2" ]
then
    echo "
Usage: `basename $0` <key file> <URL file> <integration_name> <scenario_name> <suffix> <protocol>

  Example: `basename $0` MyAPIKeyFile My_Targets Integration Scenario Suffix

where,

  <key file>      - The file with the ZeroNorth API keys. The file should
                    contain only the API key as a single string.

  <target file>   - The file with all relevant URLs
  
  <integration name> - The ingregration found FabricADM -> Integrations
  
  <scenario_name> - The name of scenario found FabricADM -> Scenarios
  
  <suffix> 		  - The suffix you would like added to policies, 
  					recommended to be related to the scenario name
					(eg. Sonarqube would be -SQ)
					
  <protocol>	  - Is this a list of http or https URLs
" >&2
    exit 1
fi

API_KEY=$(cat "$1"); shift
if [ $? != 0 ]; then
    echo "Can't read key file!!! Exiting."
    exit 1
fi

URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"

########################################################################
# Variable Set Up
########################################################################

input="$1"
project=$(cat ${input})
echo "$project" | while IFS= read -r line;
do	
	URL="$line"
	TARGET_NAME="$URL"
	if [ ! "URL" ]
		then
		    echo "No URLS provided! Exiting."
		    exit 1
	fi
	
in=$(echo $2 | sed 's/ /%20/g')
integration=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/environments?name=${in}")
INTEGRATION_ID=$(echo ${integration} | jq -r '.[0][].id')
if [ ! "INTEGRATION_ID" ]
	then
	    echo "No Integration Name provided! Exiting."
	    exit 1
fi

sn=$3
scenario=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/scenarios?name=${sn}&expand=false")
SCENARIO_ID=$(echo ${scenario} | jq -r '.[0][].id')
if [ ! "SCENARIO_ID" ]
	then
	    echo "No Project SCENARIO_ID provided! Exiting."
	    exit 1
fi

protocol=$5

if protocol="https"
then
	port="443"
else
	port="80"
fi

POLICY_NAME_SUFFIX="$4"
POLICY_NAME="${URL}${POLICY_NAME_SUFFIX}"
POLICY_NAME_MOD=$(echo ${POLICY_NAME} | sed 's/ /%20/g' | sed 's/_/-/g')
TARGET_NAME_MOD=$(echo ${TARGET_NAME} | sed 's/ /%20/g' | sed 's/&/and/g' | sed 's/_/-/g')

########################################################################
# The below code does the following:
#
# 1) Look up or create the Target based on the specified Integration ID
#    and the specified Target Name.
# 2) Look up or create the Policy based on the specified Scenario ID and
#    the specified Target Name.
#
# If the above steps are successful, the script exits with status of 0
# printing the resulting Policy ID.
########################################################################

########################################################################
# 1) Create a Target using the specified Integration ID.
#    Assumes "Artifact" Type Integration.
########################################################################
#
# First, check to see if a Target by same name exists
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets/?name=${TARGET_NAME_MOD}")

# How many matching targets?
tgt_count=$(echo ${result} | sed 's/^.*\"count\"://' | sed 's/\,.*$//')

# more than 1, die
if [ "$tgt_count" -gt 1 ]; then
    print_msg "Found multiple matches for the Target Name '${TARGET_NAME}'!!! Exiting."
    exit
# exactly 1, we can use it
elif [ "$tgt_count" -eq 1 ]; then
    tgt_id=$(echo ${result} | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Target '${TARGET_NAME}' found with ID '${tgt_id}'."
# else (i.e. 0), we create one
else
    print_msg "Creating a target with name '${TARGET_NAME}'..."
    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{
  \"name\": \"${TARGET_NAME}\",
  \"environmentId\": \"${INTEGRATION_ID}\",
  \"environmentType\": \"direct\",
  \"parameters\": {\"protocol\": \"${protocol}\",
					\"port\": \"${port}\", 
					\"hostname\": \"${URL}\"}
}" "${URL_ROOT}/targets")
    #
    # Extract the target ID from the response--needed for the next step.
    #
    tgt_id=$(echo ${result} | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Target '${TARGET_NAME}' created with ID '${tgt_id}'."
fi

if [ $tgt_id = "{" ]; then
    print_msg "Target look-up/creation failed!!! Exiting."
    exit 1
fi


########################################################################
# 2) Create a Policy using the Target from above and other input params.
########################################################################
#
# First, check to see if a Policy by same name exists
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/?name=${POLICY_NAME_MOD}")

# How many matching policies?
pol_count=$(echo ${result} | sed 's/^.*\"count\"://' | sed 's/\,.*$//')

# more than 1, die
if [ "$pol_count" -gt 1 ]; then
    print_msg "Found multiple matches for the Policy Name '${POLICY_NAME}'!!! Exiting."
    exit
# exactly 1, we can use it
elif [ "$pol_count" -eq 1 ]; then
    pol_id=$(echo ${result} | sed 's/,\"customerId\":.*$//' | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Policy '${POLICY_NAME}' found with ID '${pol_id}'."
# else (i.e. 0), we create one
else
    print_msg "Creating a policy with name '${POLICY_NAME}'..."

    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{
  \"name\": \"${POLICY_NAME}\",
  \"environmentId\": \"${INTEGRATION_ID}\",
  \"environmentType\": \"artifact\",
  \"targets\": [
    {
      \"id\": \"${tgt_id}\"
    }
  ],
  \"policyType\": \"dataLoad\",
  \"scenarioIds\": [
    \"${SCENARIO_ID}\"
  ],
  \"description\": \"Policy created via API\",
  \"permanentRunOptions\":
    {
      \"sonarqubeApplicationLookupType\": \"byKey\",
      \"projectKey\": \"${PROJECT_KEY}\"
    }
}" "${URL_ROOT}/policies")

    #
    # Extract the policy ID from the response--and print it as output.
    #
    pol_id=$(echo ${result} | sed 's/^{\"id\":\"//' | sed 's/\".*$//')
    print_msg "Policy '${POLICY_NAME}' created with ID '${pol_id}'."
fi

if [ $pol_id = "{" ]; then
    print_msg "Policy look-up/creation failed!!! Exiting."
    exit 1
fi

POLICY_ID="${pol_id}"
done