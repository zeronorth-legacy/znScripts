#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2019-May, support@zeronorth.io
#
# Script to remove orphant Schedules. Orphant Schedules are Schedules
# that once belonged to a Policy, but was not cleaned up when the Policy
# was archived without first removing the schedule(s) associated with
# the Policy. An orphant Schedule continues to get picked up for
# processing but fails due to Policy not being found. One can see these
# in the #failed-prod-jobs Slack channel.
#
# At this point, there is no API endpoint to list the orphant Schedules.
# Therefore, this script required the Policy ID suspected of having one
# or more orphant Schedules. It will then:
#
# 1) Confirm that there is no Policy by the given ID.
# 2) Delete all Schedules associated with the Policy ID.
#
# Requires sed, curl, and jq.
#
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
# of 10 calendar years.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$1" ]
then
    echo "
Usage: `basename $0` <policy ID> [<key_file>]

  Example: `basename $0` QIbGECkWRbKvhL40ZvsVWh [MyKeyFile]

where,
  <policy ID> - The ID of the Policy you want to deleted Schedules for.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
" >&2
    exit 1
else
    POLICY_ID="$1"; shift
    print_msg "Policy ID: '${POLICY_ID}'"
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
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"


########################################################################
# The below code does the following:
#
# 0) Look up the Policy ID and ensure it does NOT exist.
# 1) Look up the existing Schedules for the given Policy ID.
# 2) Iterate through the Schedules and DELETE them.
########################################################################

########################################################################
# 0) Look up the Policy by ID to verify that it does NOT exist.
########################################################################
#
# First, check to see if a Policy by same name exists
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/${POLICY_ID}")

# Extract the resulting policy ID
pol_id=$(echo "$result" | jq -r '.id')

if [ ${POLICY_ID} = ${pol_id} ]; then
    print_msg "Policy with ID '${POLICY_ID}' found. Aborting!"
    exit 1
else
    print_msg "No Policy with ID '${POLICY_ID}'. Safe to proceed."
fi


########################################################################
# 1) Look up the existing Schedules for the given Policy ID.
########################################################################
print_msg "Looking up Schedules..."
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/${POLICY_ID}/schedules")

#
# Are there any? How many?
#
count=$(echo "$result" | jq -r '.[1].count' )
if [ $? != "0" ]; then
    print_msg "Error during schedule retrieval. Exiting!"
    exit 1
elif [ $count -eq 0 ]; then
    print_msg "Found 0 Schedules. Nothing to delete."
    exit 0
else
    print_msg "Found $count Schedules to delete."
fi

schedules=$(echo "$result" | jq -r '.[0][] | .meta.etag+" "+.data.policyId+" "+.id')


########################################################################
# 2) Iterate through the Schedules deleting each.
########################################################################
echo "$schedules" | while read etag pid sid
do
    result=$(curl -s -X DELETE --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" --header "etag: $etag" "${URL_ROOT}/policies/$pid/schedules/$sid")
    status=$(echo "$result" | jq '.statusCode')
    if ([ $? != 0 ] || [ $status ]); then
        print_msg "Error while trying to delete schedule with ID '$sid'."
    else
        print_msg "Schedule with ID '$sid' deleted."
    fi
done


########################################################################
# The End
########################################################################
print_msg "Done."
