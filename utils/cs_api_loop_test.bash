#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., jee@zeronorth.io
#
# Script to repeatedly hit the /v1/policies API endpoint to try to catch
# when the endpoint returns an empty result without an error response.
# This is to investigate Bridgestone report of similar behavior.
#
# Requires: curl, jq, sed
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
# of 10 calendar years.
########################################################################
SLEEP_SECS=60
MY_NAME=`basename $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo -e "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Function to post a message to Slack via the webhook URL
########################################################################
function slack_msg {
    print_msg "$1"
    curl -s -X POST -d '{"text":"'"$1"'"}' ${SLACK_URL} || \
        print_msg "ERROR: critical error posting \"$1\" to URL ${SLACK_URL}"
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$2" ]
then
    echo "
Script to look-up/or create a Target and an onprem SonarQube data loadPolicy
with the specified Target and Policy names. If the named objects exist they
are reused. Prints the resulting Policy ID (created or found) to STDOUT.

The ZeroNorth API key must be provided via the env variable 'API_KEY'.


Usage: $MY_NAME <Policy_Name> <Slack URL> [<key_file>]

where,

  <Policy_Name> - The name of the Policy you want to create or look up.

  <Slack URL>   - The webhook URL to Slack or MS Teams.

  <key_file>    - Optionally, the file with the ZeroNorth API key. If not
                  provided, will use the value in the API_KEY variable,
                  which can be supplied as an environment variable or be
                  set inside the script.


Examples: $MY_NAME My_Scan_Policy
          $MY_NAME My_Scan_Policy my_key_file
" >&2
    exit 1
fi


# Read in the Policy name.
POLICY_NAME="$1"; shift
print_msg "Policy Name: '${POLICY_NAME}'"

# Read in the Slack URL.
SLACK_URL="$1"; shift
print_msg "Slack URL: '${SLACK_URL}'"

[ "$1" ] && API_KEY=$(cat "$1")

if [ ! "$API_KEY" ]
then
    echo "No API key provided! Exiting."
    exit 1
fi
print_msg "API_KEY read in. `echo -n $API_KEY | wc -c` bytes."


########################################################################
# Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"
HEADER_AUTH="Authorization:${API_KEY}"


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
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/${obj_type}/?name=${obj_name}")
    # Check response code.
    if [[ "$result" =~ '"statusCode":' ]]; then
        response=$(jq '.statusCode' <<< "$result")
        if [ $response -gt 299 ]; then
            print_msg "ERROR: API call to look up '$obj_name' failed:\n${result}"
            return 1
        fi
    fi

    # An empty result is also very bad.
    if [ ! "$result" ]; then
        print_msg "ERROR: Unexpected empty result from the API call."
        slack_msg "${MY_NAME}@`hostname`  ERROR  Unexpected empty result from the API call."
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


########################################################################
# 0) Look up the customer name. It's a good test of the API_KEY.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")

# Check response code.
if [[ "$result" =~ '"statusCode":' ]]; then
    response=$(jq '.statusCode' <<< "$result")
    if [ $response -gt 299 ]; then
        print_msg "ERROR: API call for customer name look up failed:
${result}"
        exit 1
    fi
fi

cust_name=$(jq -r '.customer.data.name' <<< "$result")
if [ ! "$cust_name" ]; then
    print_msg "ERROR: unable to retrieve customer name. Exiting."
    exit 1
fi
print_msg "Customer = '$cust_name'"


########################################################################
# 1) Loop, looking up the Policy by the specified name.
########################################################################
while :
do
    pol_id=$(find_by_name policies "$POLICY_NAME")
    if [ $? -gt 0 ]; then
        print_msg "Error status from the call to 'find_by_name'."
    fi

    print_msg "Sleeping for $SLEEP_SECS seconds..."
    sleep $SLEEP_SECS
done


########################################################################
# The End
########################################################################
print_msg "Done."
