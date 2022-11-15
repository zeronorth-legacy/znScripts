#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to look-up/or create an Artifact type Target with the specified
# Target name and Integration ID. If the named Target alredy exists, no
# action is taken.
#
# Prints the resulting Target ID (created or found) to STDOUT.
#
# Requires: curl, jq
#
# Before using this script sign-in to https://fabric.zeronorth.io and
# ensure that the necessary Integration (must of type "Artifact")
# exists:
#
#    Go to FabricADM -> Integrations -> Add an "Artifact" type
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
MY_NAME=`basename $0`

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Check for dependent utilities.
########################################################################
if [ ! `which jq 2>/dev/null` ]; then
    print_msg "ERROR: missing required utility 'jq'. Exiting."
    exit 1
fi


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$2" ]
then
    echo "
Script to look-up/or create an Artifact type Target with the specified
Target name and Integration ID. If the named Target alredy exists, no
action is taken.

Prints the resulting Target ID (created or found) to STDOUT.


Usage: $MY_NAME <IntegrationID> <Target_Name> [<key_file>]

where,

  <IntegrationID> - The ID of the Artifact Type Integraiton you want to
                    use for the Target creation.

  <Target_Name>   - The name of the Target you want to create or use.

  <key_file>      - Optionally, the file with the ZeroNorth API key. If not
                    provided, will use the value in the API_KEY variable,
                    which can be supplied as an environment variable or be
                    set inside the script.


Examples: $MY_NAME OtzOhx2SRxWhKjz10kqrnW My_Artifact_Target
          $MY_NAME OtzOhx2SRxWhKjz10kqrnW My_Artifact_Target MyKeyFile
" >&2
    exit 1
fi

# Get the integration ID.
INTEGRATION_ID="$1"; shift
print_msg "Integration ID: '${INTEGRATION_ID}'"

# Get the Target name.
TARGET_NAME="$1"; shift
print_msg "Target Name: '${TARGET_NAME}'"

# Read in the API key.
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
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"
HEADER_AUTH="Authorization:${API_KEY}"


########################################################################
# Create a Target using the specified Integration ID. Assumes "Artifact"
# Type Integration.
# Prints the resulting Target ID to STDOUT.
########################################################################
#
# First, check to see if a Target by same name exists
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets/?name=${TARGET_NAME}")

# How many possible matches?
tgt_count=$(jq -r '.[1].count' <<< "$result")

# Found 1 or more...need to look closer.
if [ $tgt_count -gt 0 ]; then
    # Let's look for a full, but case-insensitive match.
    tgt_id=$(jq -r '.[0][]|select((.data.name|ascii_downcase)==("'"${TARGET_NAME}"'"|ascii_downcase))|.id' <<< "$result")
    if   [ ! "$tgt_id" ]; then
        tgt_count=0
    else
        tgt_count=$(wc -l <<< "$tgt_id")
    fi
fi

# More than 1, die.
if [ $tgt_count -gt 1 ]; then
    print_msg "Found multiple matches for the Target Name '${TARGET_NAME}'!!! Exiting."
    exit 1
# Exactly 1, just return the Target ID.
elif [ $tgt_count -eq 1 ]; then
    print_msg "Target '${TARGET_NAME}' found with ID '${tgt_id}'."
    echo "$tgt_id"
    exit
fi

# We we get there, we need to create one.
print_msg "Creating a target with name '${TARGET_NAME}'..."
result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{
  \"name\": \"${TARGET_NAME}\",
  \"environmentId\": \"${INTEGRATION_ID}\",
  \"environmentType\": \"artifact\",
  \"parameters\": {
    \"name\":\"${TARGET_NAME}\"
  }
}" "${URL_ROOT}/targets")

# Check response code.
response=$(echo "$result" | jq '.statusCode')
if ([ "$response" != "null" ] && [ "$response" -gt 299 ] ); then
    print_msg "ERROR: Target create failed."
    exit 1
fi


#
# Extract the target ID from the response.
#
tgt_id=$(echo "$result" | jq -r '.id')
print_msg "Target '$TARGET_NAME' created with ID '$tgt_id'."
echo "$tgt_id"


########################################################################
# The End
########################################################################
print_msg "Done."
