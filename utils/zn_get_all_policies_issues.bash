#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to extract Refined Issue compressions ratios for Policies of a
# specific SonarQube Scenario. Run the script without params to see HELP
# info.
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
MY_NAME=`basename $0`

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$2" ]
then
    echo "
Script to extract Refined Issue compressions ratios for Policies of a
specific SonarQube Scenario. Run the script without params to see HELP
info.


Usage: `basename $0` <scenarioID> ALL [<key_file>]

where,

  <scenarioID> - The ID of the SonarQube Scenario.

  ALL          - This keyword is required for safety.

  <key_file>   - Optionally, the file with the ZeroNorth API key. If not
                 provided, will use the value in the API_KEY variable,
                 which can be supplied as an environment variable or be
                 set inside the script.


  Example: `basename $0` Yt5W3l5hRteFcs7uW1pkMg ALL
           `basename $0` Yt5W3l5hRteFcs7uW1pkMg ALL key_file
" >&2
    exit 1
fi

SCN_ID="$1"; shift
print_msg "Scenario ID: '$SCN_ID'"

TGT_ID="$1"; shift
if [ $TGT_ID != "ALL" ]
then
    print_msg "ERROR: You must specify 'ALL' as the first parameter. Exiting."
    exit 1
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
# Look up the customer name.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")
cust_name=$(jq -r '.customer.data.name' <<< "$result")
print_msg "Customer = '$cust_name'"


########################################################################
# Extract the list of Policies.
########################################################################
#
# Get the list of the Policies.
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies?scenarioId=${SCN_ID}&limit=3000")

# How many Policies?
pol_count=$(echo "$result" | jq -r '.[1].count')
if [ $pol_count -eq 0 ]; then
    print_msg "Policy count is $pol_count. Nothing to do. Exiting."
    exit
else
    print_msg "Found $pol_count Policies."
fi

# Get the Policies list.
pols=$(echo "$result" | jq -r '.[0][]|.id+" "+.data.name')


# Print the column headings.
echo "customer,polId,polName,refinedIssueId,severityCode,instances"

pol_num=0
# Extract the Refined Issues for the Policies. Limit 10,000 each.
while read line
do
    set $line; pol_id="$1"; shift; pol_name="$*"

    (( pol_num = pol_num + 1 ))
    print_msg "Policy $pol_num of $pol_count: '$pol_name'..."

    # Get the Issues for the Policy
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/refinedIssues?policyId=${pol_id}&limit=10000")

    # Check for empty result/error.
    if [[ ${result,,} =~ \"statuscode\" ]]; then
        status=$(echo "$result" | jq -r '.statusCode')
        [ ! $status ] || [ "$status" == "400" ] && issues=""
    else
        issues=$(echo "$result" | jq -r '.[0][]|.id+","+.data.severityCode+","+(.data.vulnerabilityDetails|length|tostring)')
    fi

    # Print the "|" delimited line.
    while read issue
    do
        # First print the Policy-level data.
        echo -n "$cust_name,$pol_id,$pol_name,"
        # Now, print the Issues-level data.
        echo "$issue"
    done <<< "$issues"
done <<< "$pols"


########################################################################
# Done.
########################################################################
print_msg "Done."
