#!/bin/bash
#set -xv
########################################################################
# Script to extract Synthetic Issues for a Target, and the examine those
# Target so see:
# 1) what JobID and Policy contributed to it
# 2) Which Target the Job/Policy was supposed to point to
#
# Requires curl, jq.
# Run the script without params to see HELP info.
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
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# Input validation and HELP.
########################################################################
if [ ! "$1" ]
then
    echo "
Usage: `basename $0` <target ID> [<key_file>]

  Example: `basename $0` QIbGECkWRbKvhL40ZvsVWh
           `basename $0` QIbGECkWRbKvhL40ZvsVWh key_file

where,
  <target ID> - The ID of the Target whose synthetic issues you want.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
" >&2
    exit 1
fi

# Read in the Target ID.
TARGET_ID="$1"; shift
print_msg "Target ID: '${TARGET_ID}'"

# Read in the API key.
[ "$1" ] && API_KEY=$(cat "$1")
if [ ! "$API_KEY" ]
then
    echo "No API key provided! Exiting."
    exit 1
else
    key_len=$(echo $API_KEY | wc -c)
    print_msg "API Key read in: $key_len bytes."
fi


########################################################################
# Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"


########################################################################
# FUNCTION to examine the details of the Specified Job ID.
# -inputs: Issue ID, Job ID
########################################################################
function lookup_job {

    iid=$1
    jid=$2

    # Look up the Job details
    job=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${jid}")

    # Examine the job details
    jtid=$(echo "$job" | jq -r '.data.targetId')
    jtime=$(echo "$job" | jq -r '.meta.lastModified')

    echo -n "$iid"
    echo -n ",$jid"
    echo -n ",$jtid"
    echo -n ",$jtime"
    if [ $jtid == $TARGET_ID ]; then
        echo -n ",Y"
    else
        echo -n ",N"
    fi
    echo
}


########################################################################
# FUNCTION to examine the details of the Specified Synthetic Issue
# -input: Issue ID
########################################################################
function get_jobs {
    iid=$1

    # Look up the Synthetic Issue and extract the list of Jobs
    jids=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/syntheticIssues/${iid}" | jq -r '.data.issueJobs[].jobId')

    # For each Job from the above list, extract the jobID and look it up
    echo "$jids" | while read jid
    do
        # Look up the job details
        lookup_job $iid $jid
    done
}


########################################################################
# MAIN: Extract the list of Synthetic Issues.
########################################################################
# Get the Issues for the specified Target.
issues=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/syntheticIssues/?targetId=${TARGET_ID}&limit=1000" | jq -r '.[0][].id')

# Look up each Issue by ID
i_count=$(echo "$issues" | wc -l)
print_msg "Found $i_count Synthetic Issue records."
echo
echo "Issue ID,Job ID,Target ID,Job Timestamp,Target Match"

echo "$issues" | while read issue
do
    get_jobs $issue
done


########################################################################
# Done.
########################################################################
