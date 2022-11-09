#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to update the Risk Impact assessment scores for the Application
# specified by the Application Name. Dies if the specified Application
# is not found or if there is more than one match by case-insensitive
# look up.
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
if [ ! "$3" ]
then
    echo "
Script to update the Risk Impact assessment scores for the Application specified
by the Application Name. Dies if the specified Application is not found or if
there is more than one match by case-insensitive look up.


Usage: $MY_NAME <app_name> <risk_type> <score,score,score,score> [<key_file>]

where,

  <app_name>  - The name of the Application you want to apply the risk score to.
                Dies if the specified Application is not found or if there is
                more than one match by case-insensitive look up.

  <risk_type> - This must be one of 'business' or 'technical'. The general
                recommendation is to use 'business' type. More information at:
                https://owasp.org/www-community/OWASP_Risk_Rating_Methodology

  <score,...> - An array of 4 comma-separated numbers to for the risk impact
                score in the format n,n,n,n. The order of the score numbers is
                IMPORTANT and must be as follows:

                Business Impact: (w/ valid numeric score values)
                1) Financial damage: 1 3 7 9
                2) Reputation damage: 1 4 5 9
                3) Non-compliance: 2 5 7
                4) Privacy violation: 1 4 5 9

                Technical Impact: (w/ valid numeric score values)
                1) Loss of confidentiality: 2 6 7 9
                2) Loss of integrity: 1 3 5 7 9
                3) Loss of accountability: 1 7 9
                4) Loss of availability: 1 5 7 9

                NOTE: Any score in the range of 1 through 9 will be taken, but
                only the numbers listed above will result in a visible label in
                the ZeroNorth web UI.

                For full details about the scoring numbers, see:
                https://owasp.org/www-community/OWASP_Risk_Rating_Methodology

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable, which can
                be supplied as an environment variable or be set within this
                script (this last option is not recommended).

Examples: $MY_NAME MyApp business 7,5,5,9
          $MY_NAME MyApp technical 6,5,7,7
          $MY_NAME MyApp technical 6,5,7,7 key_file
" >&2
    exit 1
fi

# Read in the Application name.
APP_NAME="$1"; shift
print_msg "Application Name: '${APP_NAME}'"

# Read in the risk type.
RISK_TYPE="$1"; shift
if [ "$RISK_TYPE" == "business" ] || [ "$RISK_TYPE" == "technical" ]; then
    print_msg "Risk type: '${RISK_TYPE}'"
else
    print_msg "ERROR: '$RISK_TYPE' is not a valid value for risk type. Exiting."
    exit 1
fi

# Read in the risk score array.
RISK_SCORE="$1"; shift
if [[ ${RISK_SCORE} =~ ^[0-9],[0-9],[0-9],[0-9]$ ]]; then
    print_msg "Risk score: '$RISK_SCORE'"
else
    print_msg "ERROR: Risk score must of the form 'n,n,n,n'. Exiting."
    exit 1
fi
# Parse out the risk score numbers.
risk_scores=($(echo "$RISK_SCORE" | sed 's/,/ /g'))
#echo "DEBUG: score1 = '${risk_scores[0]}'" >&2
#echo "DEBUG: score2 = '${risk_scores[1]}'" >&2
#echo "DEBUG: score3 = '${risk_scores[2]}'" >&2
#echo "DEBUG: score4 = '${risk_scores[3]}'" >&2

# Get the API key by one of two means.
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
# The below code does the following:
#
# 1) Look up the Application by name, obtaining the ID / details.
# 2) Construct the JSON payload for updating the Application.
# 3) Update the existing Application with the new risk impact info.
#
# If the above steps are successful, the script exits with status of 0.
########################################################################

########################################################################
# 1) Look up the Application by name, obtaining the ID / details.
########################################################################
# URL encode APP_NAME
encode_APP_NAME=$(echo "$APP_NAME" | sed 's/:/%3A/g; s/\//%2f/g; s/ /%20/g')

result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications?expand=true&name=${encode_APP_NAME}")

# How many possible matches?
app_count=$(jq -r '.[1].count' <<< "$result")

# Found 1 or more...need to look closer.
if [ $app_count -gt 0 ]; then
    # Let's look for a full, but case-insensitive match.
    app_id=$(jq -r '.[0][]|select((.data.name|ascii_downcase)==("'"${APP_NAME}"'"|ascii_downcase))|.id' <<< "$result")
    if   [ ! "$app_id" ]; then
        app_count=0
    else
        app_count=$(wc -l <<< "$app_id")
    fi
fi

# Exactly 1, we can use it!
if [ $app_count -eq 1 ]; then
    print_msg "Found '$APP_NAME', ID: $app_id"

# None, die.
elif [ $app_count -eq 0 ]; then
    print_msg "ERROR: Application '${APP_NAME}' does not exist!!! Exiting."
    exit 1

# More than 1, die.
elif [ $app_count -gt 1 ]; then
    print_msg "ERROR: Found multiple matches for the Application name '${APP_NAME}'!!! Exiting."
    exit 1
fi

# Now, look up the Application details using the ID.
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications/${app_id}")
app_data=$(echo "$result" | jq -r '.data')
#echo "DEBUG: app_data is
#$app_data" >&2;exit


########################################################################
# 2) Construct the JSON payload for updating the Application.
########################################################################
# Grab the array of existing targetIds.
existing_tgts=$(echo "$app_data" | jq -r '.targetIds')

# Grab the existing Description.
existing_desc=$(echo "$app_data" | jq -r '.description')

# Construct for business Risk Impact.
if [ "$RISK_TYPE" == "business" ]; then
    app_payload="
{
  \"name\": \"${APP_NAME}\",
  \"targetIds\": ${existing_tgts},
  \"typeOfRiskEstimate\": \"${RISK_TYPE}\",
  \"businessImpact\":
    {
      \"financialDamage\":  ${risk_scores[0]},
      \"reputationDamage\": ${risk_scores[1]},
      \"nonCompliance\":    ${risk_scores[2]},
      \"privacyViolation\": ${risk_scores[3]}
    },
  \"description\": \"${existing_desc}\"
}"

# Construct for technical Risk Impact.
elif [ "$RISK_TYPE" == "technical" ]; then
    app_payload="
{
  \"name\": \"${APP_NAME}\",
  \"targetIds\": ${existing_tgts},
  \"typeOfRiskEstimate\": \"${RISK_TYPE}\",
  \"technicalImpact\":
    {
      \"confidentialityLoss\": ${risk_scores[0]},
      \"integrityLoss\":       ${risk_scores[1]},
      \"accountabilityLoss\":  ${risk_scores[2]},
      \"availabilityLoss\":    ${risk_scores[3]}
    },
  \"description\": \"${existing_desc}\"
}"

# Otherwise..., we should never end up here.
else
    print_msg "ERROR: Unexpected condition. Exiting."
    exit 1
fi


########################################################################
# 3) Update the existing Application with the new risk impact info.
########################################################################
print_msg "Updating Application '$APP_NAME'..."
result=$(curl -s -X PUT --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "${app_payload}" "${URL_ROOT}/applications/${app_id}")

# Check to see if there was an error.
error_code=$(echo "$result" | jq -r '.statusCode')
if [ "$error_code" != "null" ]; then
    err_rsp=$(echo "$result" | jq -r '.error')
    err_msg=$(echo "$result" | jq -r '.message')
    print_msg "ERROR: code '${error_code}', '${err_rsp}'"
    print_msg "ERROR: ${err_msg}"
    print_msg "Exiting."
    exit 1
fi

# All went well.
print_msg "Application '${APP_NAME}' updated."


########################################################################
# The End
########################################################################
print_msg "Done."
