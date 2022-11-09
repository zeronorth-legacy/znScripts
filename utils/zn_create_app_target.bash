#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to look-up or to create the specified Application and then add
# the specified Target to it if not already a member of the Application.
# All other details about the Application are left as is.
#
# Application and Target look up by name is case insensitive.
#
# Requires: curl, sed, jq
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
# of 10 calendar years.
########################################################################
MY_NAME=`basename $0`

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$2" ]
then
    echo "
Script to look-up or to create the specified Application and then add
the specified Target to it if not already a member of the Application.
All other details about the Application are left as is.

Application and Target look up by name is case insensitive.


Usage: $MY_NAME <app_name> <tgt_name> [<key_file>]

  Example: $MY_NAME MyApp MyTarget
           $MY_NAME MyApp MyTarget zn_key_file


where,

  <app_name>  - The name of the Application you want to create or use.

  <tgt_name>  - The name of the Target you want to add to the specified
                Application.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
" >&2
    exit 1
fi

APP_NAME="$1"; shift
print_msg "Application Name: '${APP_NAME}'"

TGT_NAME="$1"; shift
print_msg "Target Name: '${TGT_NAME}'"

[ "$1" ] && API_KEY=$(cat "$1")

if [ ! "$API_KEY" ]
then
    print_msg "ERROR: No API key provided! Exiting."
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
# The below code does the following:
#
# 1) Look up the Target ID based on the specified Target Name.
# 2) Look up or create the Application with Target
# 3) Update existing Application with Target
#
# If the above steps are successful, the script exits with status of 0
# printing the resulting Application Name and ID.
########################################################################

########################################################################
# 1) Look up the Target ID based on the specified Target Name.
########################################################################
#
# First, check to see if a Target by same name exists
#
# URL encode TGT_NAME
encode_TGT_NAME=$(echo ${TGT_NAME} | sed 's|:|%3A|g' | sed 's|/|%2f|g' | sed 's| |%20|g')

result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets/?name=${encode_TGT_NAME}")

# How many possible matches?
tgt_count=$(jq -r '.[1].count' <<< "$result")

# Found 1 or more...need to look closer.
if [ $tgt_count -gt 0 ]; then
    # Let's look for a full, but case-insensitive match.
    tgt_id=$(jq -r '.[0][]|select((.data.name|ascii_downcase)==("'"$TGT_NAME"'"|ascii_downcase))|.id' <<< "$result")
    if   [ ! "$tgt_id" ]; then
        tgt_count=0
    else
        tgt_count=$(wc -l <<< "$tgt_id")
    fi
fi

# Exactly 1, we can use it!
if [ $tgt_count -eq 1 ]; then
    print_msg "Found '$TGT_NAME', ID: $tgt_id"

# None, die.
elif [ $tgt_count -eq 0 ]; then
    print_msg "ERROR: Target '${TGT_NAME}' does not exist!!! Exiting."
    exit 1

# More than 1, die.
elif [ $tgt_count -gt 1 ]; then
    print_msg "ERROR: Found multiple matches for the Target name '${TGT_NAME}'!!! Exiting."
    exit 1
fi


########################################################################
# 2) Look up or create the Application with Target.
########################################################################
#
# First, check to see if an Application by same name exists
#
# URL encode APP_NAME
encode_APP_NAME=$(echo ${APP_NAME} | sed 's|:|%3A|g' | sed 's|/|%2f|g' | sed 's| |%20|g')

result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications?expand=true&name=${encode_APP_NAME}")

# How many possible matches?
app_count=$(jq -r '.[1].count' <<< "$result")

# Found 1 or more...need to look closer.
if [ $app_count -gt 0 ]; then
    # Let's look for a full, but case-insensitive match.
    app_id=$(jq -r '.[0][]|select((.data.name|ascii_downcase)==("'"$APP_NAME"'"|ascii_downcase))|.id' <<< "$result")
    if   [ ! "$app_id" ]; then
        app_count=0
    else
        app_count=$(wc -l <<< "$app_id")
    fi
fi

# Exactly 1, we can use it!
if [ $app_count -eq 1 ]; then
    print_msg "Found '$APP_NAME', ID: $app_id"

# None. Create one.
elif [ $app_count -eq 0 ]; then
    print_msg "Creating Application '${APP_NAME}'..."
    
    app_params="{\"name\": \"${APP_NAME}\",\"targetIds\": [\"${tgt_id}\"],\"description\":\"\"}"

    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "${app_params}" "${URL_ROOT}/applications")

    app_id=$(echo ${result} | jq -r '.id')
    print_msg "Application '${APP_NAME}' created with ID '${app_id}' and initial Target '${TGT_NAME}'."
    exit

# More than 1, die.
elif [ $app_count -gt 1 ]; then
    print_msg "Found multiple matches for the Application name '${APP_NAME}'!!! Exiting."
    exit 1
fi


########################################################################
# 3) Update existing Application with the new Target.
########################################################################

# Get App details using app_id
result=$(curl -s -X GET --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications/${app_id}?expand=false")

# Grab list of targetIds and convert to comma separated string
existing_tgt_ids=$(echo "$result" | jq -r '.data.targetIds | map(.) | join("\",\"")')
check_existing_tgt_ids=$(echo "$result" | jq -r '.data.targetIds | map(.) | join(" ")')

# Check if tgt_id is already included.
#for i in $(echo $check_existing_tgt_ids | sed "s/,/ /g")
for i in $(echo $check_existing_tgt_ids)
do
    if [ "$tgt_id" == "$i" ]; then
        print_msg "Target '$TGT_NAME' is already a member of Appliation '${APP_NAME}'. We are good!!!"
        exit
    fi
done

# Update the list of the Target IDs.
new_tgt_ids="\"${existing_tgt_ids}\",\"${tgt_id}\""

#
# Does the application have OWASP Risk Estiamte? We need to preserve it.
#

# Risk estimate type
print_msg "Checking if '$APP_NAME' has risk impact calculated..."
risk_type=$(echo "$result" | jq -r '.data.typeOfRiskEstimate')

# technical
if [ "$risk_type" == "technical" ]; then
    print_msg "'$APP_NAME' is using '$risk_type' risk impact assessment."
    integrityLoss=$(echo "$result" | jq -r '.data.technicalImpact.integrityLoss')
    confidentialityLoss=$(echo "$result" | jq -r '.data.technicalImpact.confidentialityLoss')
    availabilityLoss=$(echo "$result" | jq -r '.data.technicalImpact.availabilityLoss')
    accountabilityLoss=$(echo "$result" | jq -r '.data.technicalImpact.accountabilityLoss')
    # create app data with technical risk info and new target ids
    app_params="{\"name\": \"${APP_NAME}\",\"targetIds\": [${new_tgt_ids}],\"typeOfRiskEstimate\": \"${risk_type}\",\"technicalImpact\": {\"confidentialityLoss\": ${confidentialityLoss},\"integrityLoss\": ${integrityLoss},\"availabilityLoss\": ${availabilityLoss},\"accountabilityLoss\": ${accountabilityLoss}},\"description\":\"\"}"

# business
elif [ "$risk_type" == "business" ]; then
    print_msg "'$APP_NAME' is using '$risk_type' risk impact assessment."
    financialDamage=$(echo "$result" | jq -r '.data.businessImpact.financialDamage')
    privacyViolation=$(echo "$result" | jq -r '.data.businessImpact.privacyViolation')
    nonCompliance=$(echo "$result" | jq -r '.data.businessImpact.nonCompliance')
    reputationDamage=$(echo "$result" | jq -r '.data.businessImpact.reputationDamage')
    # create app data with business risk info and new target ids
    app_params="{\"name\": \"${APP_NAME}\",\"targetIds\": [${new_tgt_ids}],\"typeOfRiskEstimate\": \"${risk_type}\",\"businessImpact\": {\"financialDamage\": ${financialDamage},\"reputationDamage\": ${reputationDamage},\"nonCompliance\": ${nonCompliance},\"privacyViolation\": ${privacyViolation}},\"description\":\"\"}"

# None
else
    print_msg "'$APP_NAME' does not have risk impact assessment."
    app_params="{\"name\": \"${APP_NAME}\",\"targetIds\": [${new_tgt_ids}],\"description\":\"\"}"
fi

# Replace the application.
print_msg "Updating Application '$APP_NAME'..."
result=$(curl -s -X PUT --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "${app_params}" "${URL_ROOT}/applications/${app_id}")

# Check to see if there was an error.
error_code=$(echo "$result" | jq -r '.statusCode')
if [ "$error_code" != "null" ]; then
    err_rsp=$(echo "$result" | jq -r '.error')
    err_msg=$(echo "$result" | jq -r '.message')
    print_msg "ERROR: code '${error_code}', '${err_rsp}'"
    print_msg "ERROR: ${err_msg}"
    exit 1
fi

# All went well.
print_msg "Application '${APP_NAME}' updated with Target '${TGT_NAME}'."


########################################################################
# The End
########################################################################
print_msg "Done."
