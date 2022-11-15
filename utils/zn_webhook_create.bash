#!/bin/bash
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., support@zeronorth.io
#
# Script to add a webhook for triggering a run of an existing Policy.
# Before using this script to add a webhook, check to see if one already
# exists by going to FabricOPS > Policies, locating the Policy and then
# examining its details.
#
# Input: Policy ID
#        key file (optional)
#
# Output: If successful, prints the resulting webhook URL.
#
# To use the resulting webhook, below is an example using curl:
#
#   curl -X POST --data '' <webhook url>
#
# Note that you do have to pass in an empty --data parameter.
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
# of 1 calendar year.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$1" ]
then
    echo "
Usage: `basename $0` <Policy ID> [<key_file>]

where,
  Policy ID is the ID of the Policy you want to run using the webhook.
  key_file (optional) is the file with your own API key.

  If no key_file is provide, will use the value in the API_KEY
  environment variable.
" >&2
    exit 1
else
    POLICY_ID="$1"; shift
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
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# The below code does the following:
#
# 0) Look up the Policy by ID to verify it exists.
# 1) Make the API call to add a Webhook.
# 2) Print the resulting Webhook URL.
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

if [ ${POLICY_ID} = ${pol_id} ]; then
    print_msg "Policy with ID '${POLICY_ID}' found."
else
    print_msg "No matching policy found!!! Exiting."
    exit 1
fi
    

########################################################################
# 1) Make the API call to add a Webhook.
########################################################################
result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d"{
  \"isEnabled\": true,
  \"jobType\": \"policyRun\",
  \"jobData\": {
    \"policyId\": \"${POLICY_ID}\"
  }
}" "${URL_ROOT}/webhooks")


########################################################################
# 2) Get the resulting Webhook URL.
########################################################################
#
# Extract the resulting webhook URL and print it to STDOUT.
#
webhook_url=$(echo ${result} | sed 's/^.*\"url\":\"//' | sed 's/\".*$//')
echo "===== Webhook URL below ====="
echo "${webhook_url}"
echo "===== Webhook URL above ====="

print_msg "Done."
