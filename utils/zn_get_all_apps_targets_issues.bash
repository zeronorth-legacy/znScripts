#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to extract Synthetic Issues for all Applications.
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
This script will extract for a customer account, all of the Synthetic
Issues for all of the Applications found. For each Application, it
iterates through the Targets and lists the essential information from
the Synthetic Issues.

Because this script starts from the to by looking for Applications, it
will not work for customer accounts that do not have any Applications
defined. To list the Synthetic Issues at the Targets level, see the
script \"zn_get_all_issues.bash\".


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

APP_ID="$1"; shift
if [ $APP_ID != "ALL" ]
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
# Extract the list of Applications and their Targets and their Issues.
########################################################################
# Extract the Applications list.
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications?expand=false&limit=1000")
apps=$(echo "$result" | jq -r '.[0][] | .id+"|"+.data.name')

if [ ! "$apps" ]
then
    print_msg "No Applications found. Exiting."
    exit
else
    app_count=$(echo "$apps" | wc -l)
    print_msg "Found $app_count Applications."
fi

# Print the column headings.
echo "customer|appId|appName|tgtId|tgtName|tgtType|tgtCreated|tgtTags|AST|issueId|scanner|issueKey|issueName|issueSeverity|issueSeverityCode|issueStatus|ignoreFlag|issueDetectionDate|issueRemediationDate|issueAgeDays|A1|A2|A3|A4|A5|A6|A7|A8|A9|A10"

now=`date +%s`
app_num=0
# Iterate throug each Application.
while IFS="|" read app_id app_name
do
    (( app_num = app_num + 1 ))
    print_msg "Application ($app_num of $app_count): '$app_name'..."

    # Get the list of Targets for each Application.
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications/${app_id}?expand=false")
    tgts=$(echo "$result" | jq -r '.data.targets[] | .id+"|"+.data.name+"|"+.data.environmentType')

    [ ! "$tgts" ] && continue
    tgt_count=$(echo "$tgts" | wc -l)

    # Iterate through the Targets.
    tgt_num=0
    while IFS="|" read tgt_id tgt_name tgt_type
    do
        (( tgt_num = tgt_num + 1 ))
        print_msg "     Target ($tgt_num of $tgt_count): '$tgt_name'..."

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
                if   ("|"+.id+"|" | inside("|22|23|35|59|200|201|219|264|275|276|284|285|352|359|377|402|425|441|497|538|540|548|552|566|601|639|651|668|706|862|863|913|922|1275|")) then 
                  "A1"
                elif ("|"+.id+"|" | inside("|261|296|310|319|321|322|323|324|325|326|327|328|329|330|331|335|336|337|338|340|347|523|720|757|759|760|780|818|916|")) then 
                  "A2"
                elif ("|"+.id+"|" | inside("|20|74|75|77|78|79|80|83|87|88|89|90|91|93|94|95|96|97|98|99|100|113|116|138|184|470|471|564|610|643|644|652|917|")) then 
                  "A3"
                elif ("|"+.id+"|" | inside("|73|183|209|213|235|256|257|266|269|280|311|312|313|316|419|430|434|444|451|472|501|522|525|539|5792|598|602|642|646|650|653|656|657|799|807|840|841|927|1021|1173|")) then 
                  "A4"
                elif ("|"+.id+"|" | inside("|2|11|13|15|16|260|315|520|526|537|541|547|611|614|756|776|942|1004|103220176|1174|")) then 
                  "A5"
                elif ("|"+.id+"|" | inside("|937|1035|1104|")) then 
                  "A6"
                elif ("|"+.id+"|" | inside("|255|259|287|288|290|294|295|297|300|302|304|306|307|346|384|521|613|620|640|798|940|1216|")) then 
                  "A7"
                elif ("|"+.id+"|" | inside("|345|353|426|494|502|565|784|829|830|915|")) then 
                  "A8"
                elif ("|"+.id+"|" | inside("|117|223|532|778|")) then 
                  "A9"
                elif ("|"+.id+"|" | inside("|918|")) then 
                  "AX"
                else
                  empty
                end
                # if   (.id=="77" or .id=="89" or .id=="564" or .id=="917") then "A1"
                # elif (.id=="287" or .id=="384") then "A2"
                # elif (.id=="202" or .id=="310" or .id=="311" or .id=="312" or .id=="319" or .id=="326" or .id=="327" or .id=="359") then "A3"
                # elif (.id=="611") then "A4"
                # elif (.id=="22" or .id=="284" or .id=="285" or .id=="639") then "A5"
                # elif (.id=="2" or .id=="16" or .id=="388") then "A6"
                # elif (.id=="79") then "A7"
                # elif (.id=="502") then "A8"
                # elif (.id=="223" or .id=="778") then "AX"
                # else empty
                # end
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

            # First print the Cust/App/Target-level data.
            echo -n "$cust_name|$app_id|$app_name|$tgt_id|$tgt_name|$tgt_type|$tgt_date|$tgt_tags|$ast|"
            # Now, print the Issues-level data.
            echo "$issue"
        done <<< "$issues"
    done <<< "$tgts"
done <<< "$apps"


########################################################################
# Done.
########################################################################
print_msg "Done."
