#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to send Slack notifications on job failures detected within the
# the time period specified looking back from now.
#
# Requires: curl, sed, jq
#           job_list_w_resume.bash (in the same folder as this script)
#
########################################################################
#
# Before using this script, obtain your API_KEY via the UI.
# See KB article https://support.zeronorth.io/hc/en-us/articles/115003679033
#
# The API key can then be used in one of the following ways:
# 1) Stored in secure file and then setting API_KEY to the its path.
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
# Other basics
########################################################################
MY_NAME=`basename $0`
MY_DIR=`dirname $0`


########################################################################
# Fundamental constants
########################################################################
JOB_LIST_SCRIPT="cs_job_list_w_resume.bash"


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Function to post a message to Slack via the webhook URL
########################################################################
function slack_msg {
#    print_msg "$1"
    curl -s -X POST -d '{"text":"'"$1"'"}' ${SLACK_URL} || \
        print_msg "ERROR: critical error posting \"$1\" to URL ${SLACK_URL}"
}


########################################################################
# Check to ensure that the script we need is also found.
########################################################################
which "$MY_DIR/$JOB_LIST_SCRIPT"

if [ $? -ne 0 ]; then
    print_msg "ERROR: necessary script '$JOB_LIST_SCRIPT' not found. It must be in the same directory as this script. Existing."
    exit 1
fi


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$2" ]; then
    echo "
Usage: $MY_NAME <lookback hours> <Slack webhook URL> [<key_file>]


where,

  <lookback hours> - The number of hours to look back in jobs history.
                     Specify as an integer.

  <Slack webhook URL> - The webhook URL to send Slack notifications to.
                        Sends one message per failure detection.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.

  EXAMPLE:

   $MY_NAME 24 https://hooks.slack.com/services/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

  NOTE: This script uses the script job_list_w_resume.bash to create the
  initial list of job failures. There is limit to how many failures that
  script will list. If there are too many failures, or too many jobs in
  the look-back time period, the resulting list may not be complete.
" >&2
    exit 1
fi


# Read the look-back value.
LOOKBACK="$1"; shift
print_msg "Will look back ${LOOKBACK} hours."
#SINCE=$(echo "${SINCE}" | sed 's/:/%3A/g')

# Read the Slack webhook URL.
SLACK_URL="$1"; shift
print_msg "Slack webhook URL is '${SLACK_URL}'."

# Read in the API token.
[ "$1" ] && export API_KEY=`cat "$1"`

if [ ! "$API_KEY" ]
then
    echo "No API key provided! Exiting."
    exit 1
fi


########################################################################
# Web constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"


########################################################################
# 0) Get the current customer info.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")
cust_name=$(echo "$result" | jq -r '.customer.data.name')
print_msg "Customer account is '$cust_name'."


########################################################################
# 1) Get a list of the failed jobs using the job_list_w_resume.bash
#    script.
########################################################################

# Compute the since time based on the specified look-back value.
now=$(date '+%s')
(( ss = now - ( 3600 * $LOOKBACK ) ))
since=$(date --date="@$ss" '+%Y-%m-%dT%H:%M')

# Use the other script to obtain the list of job failures.
result=$(${MY_DIR}/${JOB_LIST_SCRIPT} $since NOW 1000 FAILED)

if [ $? -ne 0 ]; then
    print_msg "ERROR: failed to retrieve the jobs list using the script '$JOB_LIST_SCRIPT'. Exiting."
    exit 1
fi

# Were there any failures?
fail_num=$(echo "$result" | grep ',FAILED,' | wc -l)

if [ $fail_num -eq 0 ]; then
    print_msg "No job failures detected. Bye."
    slack_msg "No job failures detected for customer '$cust_name' in the past $LOOKBACK hours."
    exit
fi


########################################################################
# 2) Iterate through the list of failures, sending a Slack notification
#    for each failure.
########################################################################
echo "$result" | grep ',FAILED,' | while IFS=',' read customer job_start job_end job_id status pol_id pol_nm
do
    # For each failure job ID, look up the most recent event message.
    job_err_msg=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/events?jobId=${job_id}" | jq -r '.[0][0].data.message')

    # Construct the message to send as the notification.
    message="
*ZERONORTH JOB FAILURE NOTIFICATION*

- Cust Name = ${cust_name}
- Pol Name = \`${pol_nm}\`
- Job ID = \`${job_id}\`
- Error Message: ${job_err_msg}
"

    # Sanitize the message for use as safe JSON payload.
    message=$(echo "$message" | sed 's/"/'\''/g')
#    echo "DEBUG: message = $message"

    # Send the notification.
    print_msg "Sending notification for job ID '$job_id'..."
    slack_msg "$message"; echo
done


########################################################################
# 3) Done.
########################################################################
print_msg "Done."
