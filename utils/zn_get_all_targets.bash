#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# This script lists all Targets, including the tags information for each
# target, but not including "customerMetaData" tags. Optionally, it will
# print Policies and latest job time stamp information if requested. In
# that case, there will be a record for each Target-Policy-Jobs
# combination.
#
# REQUIRES: curl, jq.
#
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
# of 10 calendar years.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."

MY_NAME=`basename $0`
MY_DIR=`dirname $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Print the help info.
########################################################################
if [ ! "$1" ]
then
    echo "
This script will extract for a customer account, all the Targets, and
will show essential attributes.


Usage: $MY_NAME [NO_HEADERS] ALL [POLICIES] [JOBS] [<key_file>]

  Example: $MY_NAME ALL
           $MY_NAME ALL POLICIES
           $MY_NAME ALL POLICIES JOBS
           $MY_NAME ALL key_file

where,

  NO_HEADERS  - If specified, does not print field heading.

  ALL         - Required parameter for safety.

  POLICIES    - Optionally, include the Policies and their run status.
                If this option is used, the output will containe one
                record per Target-Policy combination.  

  JOBS        - Optionally, applicable only in addition to the POLICIES
                option, list the FINISHED jobs history (from the last
                1,000 jobs) for each Target-Policy combination.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
" >&2
    exit 1
fi

# The option to suppress headers.
if [ "$1" == "NO_HEADERS" ]; then
    NO_HEADERS=1
    shift
fi

# Required "ALL" keyword for safety.
TGT_ID="$1"; shift
if [ "$TGT_ID" != "ALL" ]
then
    print_msg "ERROR: You must specify 'ALL' as the first parameter. Exiting."
    exit 1
fi

# The option to add Policies-level info.
if [ "$1" == "POLICIES" ]; then
    INCLUDE_POLICIES=1
    shift
fi

# The option to add Jobs-level info.
if [ "$1" == "JOBS" ]; then
    INCLUDE_JOBS=1
    shift
fi

# API token.
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
cust_name=$(echo "$result" | jq -r '.customer.data.name')
print_msg "Tenant = '$cust_name'"


########################################################################
# Extract the list of all Targets.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets?limit=2000")
tgts=$(echo "$result" | jq -r '.[0][] | .id+"|"+.data.name+"|"+(if (.meta.created != null) then (.meta.created|split(".")|.[0]|sub("T";" ")|sub("Z";"")) else "" end)+"|"+.data.environmentType+"|"+(if (.data.tags != null) then (.data.tags|join(",")) else "" end)')

if [ ! "$tgts" ]; then
    print_msg "No Targets found. Exiting."
    exit
fi

# How many Targets?
tgt_count=$(echo "$result" | jq -r '.[1].count')
print_msg "Found $tgt_count Targets."

# Optionally print or suppress the column headings.
if [ ! "$NO_HEADERS" ]; then
    if [ "$INCLUDE_POLICIES" ]; then
        if [ "$INCLUDE_JOBS" ]; then
            echo "Tenant|TargetID|TargetName|TargetCreated|TargetType|TargetTags|Status|PolicyId|PolicyName|Scanner|job_date"
        else
            echo "Tenant|TargetID|TargetName|TargetCreated|TargetType|TargetTags|Status|PolicyId|PolicyName|Scanner"
        fi
    else
        echo "Tenant|TargetID|TargetName|TargetCreated|TargetType|TargetTags"
    fi
fi

# Iterate through the Targets.
while IFS="|" read tgt_id tgt_name tgt_date tgt_type tgt_tags
do
    # The POLICIES option not specified.
    if [ ! "$INCLUDE_POLICIES" ]; then
        # Print the App/Target-level data.
        echo "$cust_name|$tgt_id|$tgt_name|$tgt_date|$tgt_type|$tgt_tags"
        continue
    fi

    # The POLICIES option is specified, get additional data.
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies?targetId=${tgt_id}")
    pol_count=$(echo "$result" | jq -r '.[1].count')

    # No Policies
    if [ $pol_count -eq 0 ]; then
        echo "$cust_name|$tgt_id|$tgt_name|$tgt_date|$tgt_type|$tgt_tags|No Policies"
        continue
    fi

    policies=$(echo "$result" | jq -r '.[0][] | .id+"|"+.data.name+"|"+.data.scenarios[0].name')

    # For each Policy, determine the job status.
    while IFS="|" read pol_id pol_name pol_scenario
    do
        result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs?policyId=${pol_id}&limit=1000")
        jobs=$(echo "$result" | jq -r '.[0][] | select (.data.status == "FINISHED") | .meta.lastModified|split(".")|.[0]|sub("T";" ")')
        job_count=0; [ "$jobs" ] && job_count=$(echo "$jobs" | wc -l)

        # Does it have FINISHED jobs?
        if [ $job_count -eq 0 ]; then
            pol_status="Not scanned"
        else
            pol_status="Scanned"
        fi

        if [ ! "$INCLUDE_JOBS" ]; then
            echo "$cust_name|$tgt_id|$tgt_name|$tgt_date|$tgt_type|$tgt_tags|$pol_status|$pol_id|$pol_name|$pol_scenario"
        else
            # Iterate through the jobs history.
            while read job_date
            do
                echo "$cust_name|$tgt_id|$tgt_name|$tgt_date|$tgt_type|$tgt_tags|$pol_status|$pol_id|$pol_name|$pol_scenario|$job_date"
            done <<< "$jobs"
        fi
    done <<< "$policies"

done <<< "$tgts"


########################################################################
# Done.
########################################################################
print_msg "Done."
