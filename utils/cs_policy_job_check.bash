#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to check the status of the jobs that should have run in the
# past 24 hours for the specified Policy ID.
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
MY_NAME=`basename $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1"
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
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$2" ]
then
    echo "
Script to check the status of the jobs that should have run in the
past 24 hours for the specified Policy ID.


Usage: $MY_NAME <policy ID> <Notify URL> [<key_file>]

where,

  <policy ID>  - The ID of the Policy you want to check recent jobs for.

  <Notify URL> - The webhook URL to Slack or MS Teams.

  <key_file>   - Optionally, the file with the ZeroNorth API key. If not
                 provided, will use the value in the API_KEY variable,
                 which can be supplied as an environment variable or be
                 set inside the script.


Examples: $MY_NAME QIbGECkWRbKvhL40ZvsVWh https://hooks.slack.com/services/...
          $MY_NAME QIbGECkWRbKvhL40ZvsVWh https://myteam.webhook.office.com/webhookb2/...
" >&2
    exit 1
fi

# Read in the Policy ID.
POLICY_ID="$1"; shift

# Read in the Slack URL.
SLACK_URL="$1"; shift

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
# Look up the customer name. It's a good test of the API_KEY.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")

# Check response code.
if [[ "$result" =~ '"statusCode":' ]]; then
    response=$(jq '.statusCode' <<< "$result")
    if [ "$response" -gt 299 ]; then
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
# The below code does the following:
#
# 0) Look up the Policy ID and ensure it exists.
# 1) "Run" the Policy specified via the POLICY_ID variable. This returns
#    the resulting job_id.
# 2) Posts the issues to the job_id from above.
# 3) "Resume" the job to allow ZeroNorth to process the posted issues.
# 4) Loop, checking for the job status every 3 seconds.
#
# After the above steps, you can see the results in the ZeroNorth UI.
########################################################################

########################################################################
# 0) Look up the Policy by ID to verify it exists.
########################################################################
#
# First, check to see if a Policy by same name exists
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/${POLICY_ID}")

# Extract the resulting policy ID
pol_id=$(jq -r '.id' <<< "$result")
pol_nm=$(jq -r '.data.name' <<< "$result")

if [ "$POLICY_ID" = "$pol_id" ]; then
    print_msg "Found Policy '${pol_nm}' with ID '${POLICY_ID}'."
else
    print_msg "ERROR: No Policy with ID '${POLICY_ID}' found!!! Exiting."
    exit 1
fi


########################################################################
# 1) Looks for job(s) that completed in the previous day.
########################################################################
print_msg "Looking for jobs..."

# First, compute the "since" date based on NOW - 24 hrs
now=$(date '+%s')                             # Seconds since epoch
(( ss = now - 86400 ))                        # Go back 24 hrs
since=$(date --date="@$ss" '+%Y-%m-%dT%H:%M') # ISO-8601 in UTC

# Look for the job(s)
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/?policyId=${POLICY_ID}&since=${since}")

# Were there any jobs?
count=$(echo "$result" | jq -r '.[1].count')
if [ "$count" -lt 1 ]; then
    slack_msg "Policy '$pol_nm' (ID '${POLICY_ID}'), no jobs in last 24 hours!!!"
    exit 1
fi
print_msg "Found $count job(s) in the past 24 hours for Policy ID ${POLICY_ID}."


########################################################################
# Check the most recent job status. Assume most recent is the first one
# in the list.
########################################################################
# Get the most recent job.
#job=$(jq -r '.[0][0]' <<< "$result")
job=$(jq -r '.[0] | sort_by(.meta.created) | last' <<< "$result")

# Get the job ID
job_id=$(jq -r '.id' <<< "$job")

# Get the job STATUS
last_status=$(jq -r '.data.status' <<< "$job")

# Compute the job duration
job_st=$(jq -r '.meta.created' <<< "$job")
job_ft=$(jq -r '.meta.lastModified' <<< "$job")

job_ss=$(date '+%s' --date=$job_st)
job_fs=$(date '+%s' --date=$job_ft)
[ "$last_status" == "RUNNING" ] && job_fs=$(date '+%s')

(( job_ds = job_fs - job_ss ))

if [ "$job_ds" -lt 60 ]; then
    job_dur="$job_ds second"
    [ "$job_ds" -gt 1 ] && job_dur="${job_dur}s"
else
    (( job_dm = job_ds / 60 ))
    job_dur="$job_dm minute"
    [ "$job_dm" -gt 1 ] && job_dur="${job_dur}s"
fi

# Ouput the job result.
if [ "$last_status" == "FINISHED" ]; then
    print_msg "Job with ID '$job_id' has status '$last_status'."
    slack_msg "$cust_name: Policy \`$pol_nm\`, Job ID \`$job_id\` ran for $job_dur and has status *${last_status}*."
    exit 0
elif [ "$last_status" == "RUNNING" ]; then
    print_msg "Job with ID '$job_id' is currently '$last_status'."
    slack_msg "$cust_name: Policy \`$pol_nm\`, Job ID \`$job_id\` is still *${last_status}* for $job_dur."
    exit 0
else
    print_msg "The most recent job was ID '$job_id', with status '$last_status'."
    slack_msg "$cust_name: Policy \`$pol_nm\`, Job ID \`$job_id\` ran for $job_dur and has status *${last_status}*."
    exit 1
fi


########################################################################
# The End
########################################################################
print_msg "Done."
