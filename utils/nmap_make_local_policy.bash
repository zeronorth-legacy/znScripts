#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2018-Mar, support@zeronorth.io
#
# Sample script using CURL to create a Target and a Policy for an nmap
# host port discovery (or similar) scans. Requires curl in your PATH.
#
# Inputs: Policy Name
#         Integration ID (not name)
#         Target Name
#         Target IP
#         Scenario ID
#         
# Output: Policy ID
#
# Before using this script sign-in to https://fabric.zeronorth.io to
# prepare a shell Policy that will to what you need to do.
#
# Related information in ZeroNorth KB at:
#
#    https://support.zeronorth.io/hc/en-us/articles/115001945114
#
########################################################################
#
# Before using this script, obtain your API_KEY via the UI.
# See KB article https://support.zeronorth.io/hc/en-us/articles/115003679033
#
API_KEY="....."


########################################################################
# Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"

#
# Constants specific to this script
#
CYBRIC_ENV_TYPE="direct"
CYBRIC_TARGET_PARAM="hostname"          # Could also be "ip"


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$5" ]
then
    echo "
Usage: `basename $0` <policy name> <integration ID> <target name> <target specs> <scenario ID>

  Example: `basename $0` MyNmapPolicy QIbGECkWRbKvhL40ZvsVWh MyNmapTarget 192.168.1.2 ISmcREEkQYC5nZNWNTDY0h

The supplied integration ID must be of proper type (e.g. Custom) and
scope (e.g. CYBRIC, Customer, Manual). The target spec can be host name
or IP depending on how this script is configured (see the script variable
CYBRIC_TARGET_PARAM).
" >&2
    exit 1
else
    POLICY_NAME="$1"; shift
    print_msg "Policy name:    '${POLICY_NAME}'"
    INTEGRATION_ID="$1"; shift
    print_msg "Integration ID: '${INTEGRATION_ID}'"
    TARGET_NAME="$1"; shift
    print_msg "Target name:    '${TARGET_NAME}'"
    TARGET_SPEC="$1"; shift
    print_msg "Target spec:    '${TARGET_SPEC}'"
    SCENARIO_ID="$1"; shift
    print_msg "Scenario ID:    '${SCENARIO_ID}'"
fi


########################################################################
# The below code does the following:
#
# 0) Verify that the supplied Integration ID exists.
# 1) Create a Target of type "Direct/Custom/Host".
# 2) Create a Policy, assuming the Scenario
# 3) Print the final status of the job.
#
# After the above steps, you can see the results in the CYBRIC UI.
########################################################################

########################################################################
# 0) Look up the Integration/Environment by ID
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/environments/${INTEGRATION_ID}")

# Extract the Integration ID and match it to the supplied one.
int_id=$(echo ${result} | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')

if [ ${INTEGRATION_ID} = ${int_id} ]; then
    print_msg "Integration ID: '${int_id}'"
else
    print_msg "Invalid Integration ID!"
    exit
fi


########################################################################
# 1) Create a Target using the input params.
#    The supplied TARGET_SPEC must be consistent with the value set in
#    the variable CYBRIC_TARGET_PARAM. For example:
#
#        for CYBRIC_TARGET_PARAM="hostname", supply a DNS alias
#        for CYBRIC_TARGET_PARAM="ip", supply an IP address
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
    print_msg "Creating a target for '${TARGET_NAME}' with ${CYBRIC_TARGET_PARAM} set to '${TARGET_SPEC}'..."
    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{
  \"name\": \"${TARGET_NAME}\",
  \"environmentId\": \"${INTEGRATION_ID}\",
  \"environmentType\": \"direct\",
  \"parameters\": {
    \"${CYBRIC_TARGET_PARAM}\": \"${TARGET_SPEC}\"
  }
}" "${URL_ROOT}/targets")
    #
    # Extract the target ID from the response--needed for the next step.
    #
    tgt_id=$(echo ${result} | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Target '${TARGET_NAME}' created with ID '${tgt_id}'."
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
    print_msg "Creating a policy for '${POLICY_NAME}'..."
    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{
  \"name\": \"${POLICY_NAME}\",
  \"environmentId\": \"${INTEGRATION_ID}\",
  \"environmentType\": \"direct\",
  \"targets\": [
    {
      \"id\": \"${tgt_id}\"
    }
  ],
  \"scenarioIds\": [
    \"${SCENARIO_ID}\"
  ],
  \"description\": \"Policy created via API\"
}" "${URL_ROOT}/policies")
    #
    # Extract the policy ID from the response--and print it as output.
    #
    pol_id=$(echo ${result} | sed 's/,\"customerId\":.*$//' | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Policy '${POLICY_NAME}' created with ID '${pol_id}'."
fi
exit

########################################################################
# 3) Done.
########################################################################
print_msg "Done."
