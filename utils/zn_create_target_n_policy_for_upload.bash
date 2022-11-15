#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2022, Harness, Inc., support@harness.io
#
# Script to look-up/or create a Target and a manual upload Policy with
# the specified Target and Policy names. If the named objects already
# exist, they are reused. Prints the resulting Policy ID (created or
# found) to STDOUT.
#
# Requires: curl, jq, sed
#
# Before using this script sign-in to https://fabric.zeronorth.io and
# ensure that the necessary Integration (must of type "Artifact") and
# appropriate Scenarios exist.
#
# 1) Go to znADM -> Scenarios. Locate and activate a Scenario for
#    the appropriate Products.
#
# 2) Go to znADM -> Integrations -> Add an "Artifact" type
#    Integration. In general, you need just one such Integration for
#    all your Artifact type Targets.
#
# Related information in ZeroNorth KB at:
#
#    https://support.zeronorth.io/hc/en-us/articles/115001945114
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
umask 077
trap "func_clean" exit

MY_NAME=`basename $0`
ZN_CURL_CONFIG=~/zn_curl_$$.config


########################################################################
# Utility functions
########################################################################

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
}


#----------------------------------------------------------------------
# Function to exit the script with exit status 1 (error).
#----------------------------------------------------------------------
function func_die {
    print_msg "Exiting due to an error."
    exit 1
}


#-----------------------------------------------------------------------
# Function to check ZeroNorth REST API response code.
#
# NOTE: This function is not recommended when dealing with large amount
# of response data as the value of the data to evaluate is being passed
# as a copy of the original.
#-----------------------------------------------------------------------
function func_check_response {
    result="$1"

    if [[ "$result" =~ '"status":' ]] || [[ "$result" =~ '"statusCode":' ]]; then
        response=$(jq '.status+.statusCode' <<< "$result")
        if [ "$response" -gt 299 ]; then
            print_msg "ERROR: API call returned error response code ${response}, with message:
${result}"
            return 1
        fi
    fi
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$4" ]
then
    echo "
Script to look-up/or create a Target and a manual upload Policy with the
specified Target and Policy names. If the named objects already exist,
they are reused. Prints the resulting Policy ID (created or found) to
STDOUT.

The ZeroNorth API key must be provided via the env variable 'API_KEY'.


Usage: $MY_NAME <Policy_Name> <ScenarioID> <IntegrationID> <Target_Name>


where,

  <Policy_Name>   - The name of the Policy you want to create or look up.

  <ScenarioID>    - The ID of the Scenario you want to use for the Policy.

  <IntegrationID> - The ID of the Artifact Type Integraiton you want to
                    use for the Target creation.

  <target_name>   - The name of the Target you want to create or use.


Example: `basename $0` My_Scan_Policy OtzOhx2SRxWhKjz10kqrnW XMopwSg7QqGglxtGAf9TSw My_Artifact_Target
" >&2
    exit 1
fi


if [ ! "$API_KEY" ]; then
    echo "No API key provided! Please, provide the ZeroNorth API key via the API_KEY environment variable."
    func_die
fi
print_msg "API_KEY read in. `echo -n $API_KEY | wc -c` bytes."

POLICY_NAME="$1"; shift
print_msg "Policy Name: '${POLICY_NAME}'"

SCENARIO_ID="$1"; shift
print_msg "Scenario ID: '${SCENARIO_ID}'"

INTEGRATION_ID="$1"; shift
print_msg "Integration ID: '${INTEGRATION_ID}'"

TARGET_NAME="$1"; shift
print_msg "Target Name: '${TARGET_NAME}'"


########################################################################
# Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"
HEADER_AUTH="Authorization:${API_KEY}"


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


#-----------------------------------------------------------------------
# Function to URL-encode the specified string.
#-----------------------------------------------------------------------
function url_encode {
    sed 's/:/%3A/g; s/\//%2f/g; s/ /%20/g' <<< "$1"
}


#-----------------------------------------------------------------------
# Function to look up a ZeroNorth object by name. This function is for
# API endpoints that allow a name search and returns a list of possible
# matches, such as Environments, Applications, Targets, Policies, etc.
#
# INPUT:  Object type - Basically, the name of the API endpoint to use.
#                       For example, to look up an Application, specify
#                       "applications".
#         Object name - The name of the object to lookup. Do not URL-
#                       encode the name. I will take care of it.
#
#
# OUTPUT: Object ID, if unique match found.
#         Empty output if not found.
#         Returns status 1 if error. Some errors will cause exit.
#
# NOTE:   The Name search is case insensitive.
#-----------------------------------------------------------------------
function find_by_name {
    obj_id=''

    # Read input params.
    obj_type="$1"; shift
    obj_name="$1"; shift

    # URL-encode for web safety.
    encode_obj_name=$(url_encode "$obj_name")

    # Get all possible matches.
    result=$(curl -s -X GET -K ${ZN_CURL_CONFIG} "${URL_ROOT}/${obj_type}/?name=${encode_obj_name}")
    func_check_response "$result" || return 1

    # An empty result is also very bad.
    if [ ! "$result" ]; then
        print_msg "ERROR: Unexpected empty result from the API call."
        return 1
    fi

    # How many possible matches?
    obj_count=$(jq -r '.[1].count' <<< "$result")

    # Found 1 or more...need to look closer.
    if [ $obj_count -gt 0 ]; then
        # Let's look for a full, but case-insensitive match.
        obj_id=$(jq -r '.[0][]|select((.data.name|ascii_downcase)==("'"${obj_name}"'"|ascii_downcase))|.id' <<< "$result")
        if   [ ! "$obj_id" ]; then
            obj_count=0
        else
            obj_count=$(wc -l <<< "$obj_id")
        fi
    fi

    # Exactly 1, we can use it!
    if [ $obj_count -eq 1 ]; then
        print_msg "Found '$obj_name', ID: $obj_id"
        echo "$obj_id"
        return

    # We still got multiple matches. No good.
    elif [ $obj_count -gt 1 ]; then
        print_msg "Found multiple matches for the Name '$obj_name'!"
        return 1

    # Didn't find any.
    elif [ $obj_count -eq 0 ]; then
        print_msg "Did not find '$obj_name'."

    fi
}


#-----------------------------------------------------------------------
# This function is a wrapper around the above function for find by name,
# but performs the search twice to reduce the chances of duplicates from
# race conditions.
#
# INPUT:  Object type - Basically, the name of the API endpoint to use.
#                       For example, to look up an Application, specify
#                       "applications".
#         Object name - The name of the object to lookup. Do not URL-
#                       encode the name. I will take care of it.
#
# OUTPUT: Object ID, if unique match found.
#         Empty output if not found.
#-----------------------------------------------------------------------
function find_by_name_twice {
    obj_id1=''
    obj_id2=''
    (( sleep_sec = $RANDOM / 8096 ))

    # Read input params.
    obj_type="$1"; shift
    obj_name="$1"; shift

    while true; do
        # First try.
        print_msg "Looking up '$obj_name'. Try #1..."
        obj_id1=$(find_by_name "$obj_type" "$obj_name") || return 1

        print_msg "Sleeping for $sleep_sec seconds..."
        sleep $sleep_sec

        # Second try.
        print_msg "Looking up '$obj_name'. Try #2..."
        obj_id2=$(find_by_name "$obj_type" "$obj_name") || return 1

        if [ "$obj_id1" == "$obj_id2" ]; then
            echo "$obj_id2"
            return
        fi

        print_msg "Hmmm...let's try that again..."
    done
    
}


########################################################################
# Look up the ZeroNorth customer name. It's a good test of the API_KEY.
########################################################################
result=$(curl -s -X GET -K ${ZN_CURL_CONFIG} "${URL_ROOT}/accounts/me")
func_check_response "$result" || func_die

cust_name=$(jq -r '.customer.data.name' <<< "$result")
if [ ! "$cust_name" ]; then
    print_msg "ERROR: unable to retrieve customer name."
    func_die
fi
print_msg "Customer: '$cust_name'"


########################################################################
# The below code does the following:
#
# 0) Look up the given Integration by ID to get the type.
# 1) Look up or create the Target based on the specified Integration ID
#    and the specified Target Name.
# 2) Look up or create the Policy based on the specified Scenario ID and
#    the specified Target Name.
#
# If the above steps are successful, the script exits with status of 0
# printing the resulting Policy ID.
########################################################################

########################################################################
# 0) Look up the Integration by ID to get the type.
########################################################################
result=$(curl -s -X GET -K ${ZN_CURL_CONFIG} "${URL_ROOT}/environments/${INTEGRATION_ID}")
func_check_response "$result" || func_die

# An empty result is also very bad.
if [ ! "$result" ]; then
    print_msg "ERROR: Unexpected empty result from the API call."
    func_die
fi

# Get the type information.
int_type=$(jq -r '.data.type' <<< "$result")
print_msg "Integration type is '$int_type'."


########################################################################
# 1) Lookup/create a Target using the specified Integration ID.
########################################################################
# First, check to see if a Target by same name exists (case-insensitive)
tgt_id=$(find_by_name_twice targets "$TARGET_NAME") || func_die

# We found it.
if [ "$tgt_id" ]; then
    print_msg "Target '${TARGET_NAME}' found with ID '$tgt_id'."

# None, so we create one.
else
    # Construct the base JSON payload.
    data="{
      \"name\": \"${TARGET_NAME}\",
      \"environmentId\": \"${INTEGRATION_ID}\",
      \"environmentType\": \"${int_type}\",
      \"parameters\": {}
    }"

    # Amend the above based on the Target type.
    if [ "$int_type" == "direct" ]; then
        data=$(jq '.parameters.hostname="dummy"' <<< "$data")
    fi

    print_msg "Creating a target with name '${TARGET_NAME}'..."
    result=$(curl -s -X POST -K ${ZN_CURL_CONFIG} -d "$data" "${URL_ROOT}/targets")
    func_check_response "$result" || func_die

    # Extract the target ID from the response--needed for the next step.
    tgt_id=$(echo "$result" | jq -r '.id')
    print_msg "Target '${TARGET_NAME}' created with ID '${tgt_id}'."
fi

if [ ! "$tgt_id" ] || [ "$tgt_id" == "null" ]; then
    print_msg "Target look-up/creation failed!!!"
    func_die
fi


########################################################################
# 2) Lookup, or create a Policy using the Target from above.
#    Assumes a manual upload Policy.
########################################################################

# First, check to see if a Policy by same name exists (case insensitive)
pol_id=$(find_by_name_twice policies "$POLICY_NAME") || func_die

# We found it.
if [ "$pol_id" ]; then
    print_msg "Policy '${POLICY_NAME}' found with ID '${pol_id}'."

# None, we create one.
else
    print_msg "Creating a policy with name '${POLICY_NAME}'..."
    result=$(curl -s -X POST -K ${ZN_CURL_CONFIG} -d "{
  \"name\": \"${POLICY_NAME}\",
  \"environmentId\": \"${INTEGRATION_ID}\",
  \"environmentType\": \"${int_type}\",
  \"policySite\": \"manual\",
  \"policyType\": \"manualUpload\",
  \"targets\": [
    {
      \"id\": \"${tgt_id}\"
    }
  ],
  \"scenarioIds\": [
    \"${SCENARIO_ID}\"
  ],
  \"description\": \"Policy created by ${MY_NAME}\",
  \"permanentRunOptions\":{}
}" "${URL_ROOT}/policies")
    func_check_response "$result" || func_die

    # Extract the policy ID from the response.
    pol_id=$(echo "$result" | jq -r '.id')
    print_msg "Policy '${POLICY_NAME}' created with ID '${pol_id}'."
fi

if [ ! "$pol_id" ] || [ "$pol_id" == "null" ]; then
    print_msg "Policy look-up/creation failed!!!"
    func_die
fi

# The final result.
POLICY_ID="${pol_id}"


########################################################################
# The End
########################################################################
echo "${POLICY_ID}"
print_msg "Done."
