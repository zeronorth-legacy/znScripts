#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to extract Synthetic Issues for Targets. Requires curl, jq.
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

MY_NAME=`basename $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$1" ]
then
    echo "
This script will extract for a customer account, all of the Synthetic Issues
for all of the Targets. For each Target, it lists the essential information
from the Synthetic Issues.

To list the Synthetic Issues at starting for the Applications, see the script
\"zn_get_all_app_targets_issues.bash\".


Usage: $MY_NAME ALL [<key_file>]

where,

  ALL         - This keyword is required for safety.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.


Examples: $MY_NAME ALL
          $MY_NAME ALL key_file
" >&2
    exit 1
fi

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
# Look up the customer name. It's a good test of the API_KEY.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")

# Check response code.
if [[ "$result" =~ '"statusCode":' ]]; then
    response=$(jq '.statusCode' <<< "$result")
    if [ $response -gt 299 ]; then
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
# Extract the list of Targets.
########################################################################
#
# Get the list of the Targets.
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets?limit=1000")

# How many Targets?
tgt_count=$(echo "$result" | jq -r '.[1].count')
if [ $tgt_count -eq 0 ]; then
    print_msg "Target count is $tgt_count. Nothing to do. Exiting."
    exit
else
    print_msg "Found $tgt_count Targets."
fi

# Get the Targets list.
tgts=$(echo "$result" | jq -r '.[0][]|.id+" "+.data.environmentType+" "+.data.name')


# Print the column headings.
echo "customer|tgtId|tgtName|tgtType|tgtCreated|tgtTags|AST|issueId|scanner|issueKey|issueName|issueSeverity|issueSeverityCode|issueStatus|ignoreFlag|issueDetectionDate|issueRemediationDate|issueAgeDays|A1|A2|A3|A4|A5|A6|A7|A8|A9|A10"

now=`date +%s`
tgt_num=0
# Extract the Synthetic Issues for the Targets. Limit 1,000 each.
while read line
do
    set $line; tgt_id="$1"; shift; tgt_type="$1"; shift; tgt_name="$*"

    (( tgt_num = tgt_num + 1 ))
    print_msg "Target ($tgt_num of $tgt_count): '$tgt_name'..."

    # Get more Target tags info.
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets/${tgt_id}")
    tgt_date=$(echo "$result" | jq -r '(if (.meta.created != null) then (.meta.created|split(".")|.[0]|sub("T";" ")|sub("Z";"")) else "" end)')
    tgt_tags=$(echo "$result" | jq -r '(if (.data.tags != null) then (.data.tags|join(",")) else "" end)')

    # Get the Issues for the Target
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/syntheticIssues/?targetId=${tgt_id}&limit=1000")
    issues=$(echo "$result" | jq -r '.[0][]
      | .id+"|"+
      .data.issueJobs[0].product+"|"+
      .data.key+"|"+
      .data.issueName+"|"+
      (.data.severity|tostring)+"|"+
      .data.severityCode+"|"+
      .data.status+"|"+
      (.data.ignore|tostring)+"|"+
      (if .data.detectionDate   == 0 then "" else ((.data.detectionDate|todate|split(".")|.[0]|sub("T";" ")|sub("Z";""))) end)+"|"+
      (if .data.remediationDate == 0 then "" else ((.data.remediationDate|todate|split(".")|.[0]|sub("T";" ")|sub("Z";""))) end)
      +"|"+
      (
        if (.data.status == "Remediation") then
          if (
               .data.remediationDate != null and .data.remediationDate > 0
               and
               .data.detectionDate   != null and .data.detectionDate   > 0
             ) then
            (
              (.data.remediationDate - .data.detectionDate) / 1440 / 60 | round | tostring
            )
          else
            empty
          end
        else
          if (.data.detectionDate != null and .data.detectionDate > 0) then
            (
              ('$now' - .data.detectionDate) / 1440 / 60 | round | tostring
            )
          else
            empty
          end
        end
      )
      +"|"+
      (
        [
          .data.referenceIdentifiers[]
          |
          select(.type == "cwe")
          |
          (
            if   (.id=="77" or .id=="89" or .id=="564" or .id=="917") then "A1"
            elif (.id=="287" or .id=="384") then "A2"
            elif (.id=="202" or .id=="310" or .id=="311" or .id=="312" or .id=="319" or .id=="326" or .id=="327" or .id=="359") then "A3"
            elif (.id=="611") then "A4"
            elif (.id=="22" or .id=="284" or .id=="285" or .id=="639") then "A5"
            elif (.id=="2" or .id=="16" or .id=="388") then "A6"
            elif (.id=="79") then "A7"
            elif (.id=="502") then "A8"
            elif (.id=="223" or .id=="778") then "AX"
            else empty
            end
          )
        ]
        | join("|")
        | (if (contains("A1")) then "A1" else "" end) +"|"+
          (if (contains("A2")) then "A2" else "" end) +"|"+
          (if (contains("A3")) then "A3" else "" end) +"|"+
          (if (contains("A4")) then "A4" else "" end) +"|"+
          (if (contains("A5")) then "A5" else "" end) +"|"+
          (if (contains("A6")) then "A6" else "" end) +"|"+
          (if (contains("A7")) then "A7" else "" end) +"|"+
          (if (contains("A8")) then "A8" else "" end) +"|"+
          (if (contains("A9")) then "A9" else "" end) +"|"+
          (if (contains("AX")) then "A10" else "" end)
      )'
    )

    # Print the "|" delimited line.
    while read issue
    do
        # Try to determine the scanner type.
        scanner=$(echo "$issue" | cut -d'|' -f2)
        if   [[ "$scanner" == "app-scan" ]]; then
            ast='DAST'
        elif [[ "$scanner" == "aqua" ]]; then
            ast='Container'
        elif [[ "$scanner" == "aqua-trivy" ]]; then
            ast='Container'
        elif [[ "$scanner" == "bandit" ]]; then
            ast='SAST'
        elif [[ "$scanner" == "blackduckhub" ]]; then
            ast='SCA'
        elif [[ "$scanner" == "brakeman" ]]; then
            ast='SAST'
        elif [[ "$scanner" == "burp" ]]; then
            ast='DAST'
        elif [[ "$scanner" == "checkmarx" ]]; then
            ast='SAST'
        elif [[ "$scanner" == "coverity" ]]; then
            ast='SAST'
        elif [[ "$scanner" == "data-theorem" ]]; then
            ast='SAST'
        elif [[ "$scanner" == "docker-content-trust" ]]; then
            ast='Container'
        elif [[ "$scanner" == "docker-image-scan" ]]; then
            ast='Container'

            elif [ "$scanner" == "fortify" ] || [ "$scanner" == "fortifyondemand" ]; then
                if [ "$tgt_type" == "artifact" ]; then
                    ast='SAST'
                elif [ "$tgt_type" == "direct" ]; then
                    ast='DAST'
                else
                    ast='Unknown'
                fi

        elif [[ "$scanner" == "nessus" ]]; then
            ast='TVM'
        elif [[ "$scanner" == "nexusiq" ]]; then
            ast='SCA'
        elif [[ "$scanner" == "nikto" ]]; then
            ast='TVM'
        elif [[ "$scanner" == "nmap" ]]; then
            ast='TVM'
        elif [[ "$scanner" == "openvas" ]]; then
            ast='TVM'
        elif [[ "$scanner" == "owasp" ]]; then
            ast='SCA'
        elif [[ "$scanner" == "prowler" ]]; then
            ast='TVM'
        elif [[ "$scanner" == "qualys" ]]; then
            ast='DAST'
        elif [[ "$scanner" == "shiftleft" ]]; then
            ast='SAST'
        elif [[ "$scanner" == "snyk" ]]; then
            ast='SCA'
        elif [[ "$scanner" == "sonarqube" ]]; then
            ast='SAST'
        elif [[ "$scanner" == "tenableio" ]]; then
            ast='TVM'
        elif [[ "$scanner" == "twistlock" ]]; then
            ast='Container'
        elif [[ "$scanner" == "veracode" ]]; then
            ast='SAST'
        elif [[ "$scanner" == "whitesource" ]]; then
            ast='SCA'
        elif [[ "$scanner" == "zap" ]]; then
            ast='DAST'
        elif [[ ! "$scanner" ]]; then
            ast=''
        else
            ast='Unknown'
        fi

        # First print the Target-level data.
        echo -n "$cust_name|$tgt_id|$tgt_name|$tgt_type|$tgt_date|$tgt_tags|$ast|"
        # Now, print the Issues-level data.
        echo "$issue"
    done <<< "$issues"
done <<< "$tgts"


########################################################################
# Done.
########################################################################
print_msg "Done."
