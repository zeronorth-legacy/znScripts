#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., 2020-June, support@zeronorth.io
#
# Script to look-up/or create Artifact type Targets and orchestrated
# scan Policies using the specified Target and Policy names. If the
# named objects alredy exist, they are reused.
#
# Prints the resulting Policy ID (created or found) to STDOUT.
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
MY_NAME=`basename $0`

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$5" ]
then
    echo "
Usage: `basename $0` <key_file> <Policy_Name> <ScenarioID> <IntegrationID> <Target_Name> [{custom params as a JSON Object}]

  Example: `basename $0` MyAPIKeyFile My_Scan_Policy OtzOhx2SRxWhKjz10kqrnW XMopwSg7QqGglxtGAf9TSw My_Artifact_Target

where,

  <key_file>      - The file with the ZeroNorth API key. The file should
                    contain only the API key as a single string.

  <Policy_Name>   - The name of the Policy you want to create or look up.

  <ScenarioID>    - The ID of the Scenario you want to use for the Policy.

  <IntegrationID> - The ID of the Artifact Type Integraiton you want to
                    use for the Target creation.

  <target_name>   - The name of the Target you want to create or use.


  Optionally, provide a JSON object (enclosed in curly brackets) with the
  set of attributes for some types of policies. For example, for SonarQube,
  use parameters like the following to set the project name and key to use
  within the SonarQube server:

    {\"projectName\": \"my-project-name\",\"projectKey\": \"my.project.key\"}


  and for Sonatype NexusIQ:

    {\"projectName\": \"myFavApplication\"}


  It may be necessary to enlose the JSON object string in single quotes:

    `basename $0 ` .... '{\"projectName\": \"my-project-name\",\"projectKey\": \"my.project.key\"}'

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

POLICY_NAME="$1"; shift
print_msg "Policy Name: '${POLICY_NAME}'"

SCENARIO_ID="$1"; shift
print_msg "Scenario ID: '${SCENARIO_ID}'"

INTEGRATION_ID="$1"; shift
print_msg "Integration ID: '${INTEGRATION_ID}'"

TARGET_NAME="$1"; shift
print_msg "Target Name: '${TARGET_NAME}'"

if [ "$1" ]; then
    CUSTOM_PARM="$1"; shift
    print_msg "Custom Params: '${CUSTOM_PARM}'"
fi


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
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets/?name=${TARGET_NAME}")

# How many matching targets?
tgt_count=$(echo ${result} | sed 's/^.*\"count\"://' | sed 's/\,.*$//')

# more than 1, die
if [ $tgt_count -gt 1 ]; then
    print_msg "Found multiple matches for the Target Name '${TARGET_NAME}'!!! Exiting."
    exit
# exactly 1, we can use it
elif [ $tgt_count -eq 1 ]; then
    tgt_id=$(echo ${result} | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Target '${TARGET_NAME}' found with ID '${tgt_id}'."
# else (i.e. 0), we create one
else
    print_msg "Creating a target with name '${TARGET_NAME}'..."
    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{
  \"name\": \"${TARGET_NAME}\",
  \"environmentId\": \"${INTEGRATION_ID}\",
  \"environmentType\": \"artifact\",
  \"parameters\": {}
}" "${URL_ROOT}/targets")
    #
    # Extract the target ID from the response--needed for the next step.
    #
    tgt_id=$(echo ${result} | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Target '${TARGET_NAME}' created with ID '${tgt_id}'."
fi

if [ $tgt_id == "{" ]; then
    print_msg "Target look-up/creation failed!!! Exiting."
    exit 1
fi


########################################################################
# 2) Create a Policy using the Target from above and other input params.
########################################################################
#
# First, check to see if a Policy by same name exists
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/?name=${POLICY_NAME}")

# How many matching policies?
pol_count=$(echo ${result} | sed 's/^.*\"count\"://' | sed 's/\,.*$//')

# more than 1, die
if [ $pol_count -gt 1 ]; then
    print_msg "Found multiple matches for the Policy Name '${POLICY_NAME}'!!! Exiting."
    exit
# exactly 1, we can use it
elif [ $pol_count -eq 1 ]; then
    pol_id=$(echo ${result} | sed 's/,\"customerId\":.*$//' | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Policy '${POLICY_NAME}' found with ID '${pol_id}'."
# else (i.e. 0), we create one
else
    print_msg "Creating a policy with name '${POLICY_NAME}'..."

    # construct the permanentRunOptions if supplied as CUSTOM_PARM
    custom_parm="{}"
    if [ "$CUSTOM_PARM" ]; then
        print_msg "Using optional custom permanentRunOptions..."
        custom_parm="$CUSTOM_PARM"
    fi

    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{
  \"name\": \"${POLICY_NAME}\",
  \"environmentId\": \"${INTEGRATION_ID}\",
  \"environmentType\": \"artifact\",
  \"targets\": [
    {
      \"id\": \"${tgt_id}\"
    }
  ],
  \"scenarioIds\": [
    \"${SCENARIO_ID}\"
  ],
  \"description\": \"Policy created by ${MY_NAME}\",
  \"permanentRunOptions\":${custom_parm}
}" "${URL_ROOT}/policies")

    #
    # Extract the policy ID from the response--and print it as output.
    #
    pol_id=$(echo ${result} | sed 's/^{\"id\":\"//' | sed 's/\".*$//')
    print_msg "Policy '${POLICY_NAME}' created with ID '${pol_id}'."
fi

if [ $pol_id == "{" ]; then
    print_msg "Policy look-up/creation failed!!! Exiting."
    exit 1
fi

POLICY_ID="${pol_id}"


########################################################################
# The End
########################################################################
echo "${POLICY_ID}"
print_msg "Done."
