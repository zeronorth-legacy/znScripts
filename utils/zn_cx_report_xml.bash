#!/bin/bash
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to extract a Checkmarx SAST scan results XML report for the
# specified project name. Extracts the latest \"Finished\" scan report
# in XML format.
#
# Requires: curl, jq
########################################################################
MYNAME=`basename $0`

########################################################################
# Constants
########################################################################
DOC_FORMAT="application/json"
CX_CLIENT_ID="resource_owner_client"
# see private version for legacy cx client secret
CX_CLIENT_SECRET="<REDACTED>"


########################################################################
# Function definitions
########################################################################

#----------------------------------------------------------------------
# Functions to print time-stamped messages
#----------------------------------------------------------------------
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MYNAME  $1" >&2
}


#----------------------------------------------------------------------
# Function to URL-encode the specified string.
#----------------------------------------------------------------------
function url_encode {
    sed 's/:/%3A/g; s/\//%2f/g; s/ /%20/g' <<< "$1"
}


########################################################################
# Read and validate input params.
########################################################################
if [ ! "$5" ]
then
    echo "
Script to extract a Checkmarx SAST scan results XML report for the specified
project name. Extracts the latest \"Finished\" scan report in XML format.


Usage: $MYNAME <CX API URL root> <CX user> <password> <project> <out file>

where,

  <CX API URL root> E.g. \"https://cx.my.com/cxrestapi\"

  <CX user>         The username of the Checkmarx user. This user should
                    have sufficient privileges to view results and create
                    reports.

  <password>        The password for the username.

  <project>         The Checkmarx project name.

  <out file>        The path to the output file. The output will be an XML
                    document. If the file path contains SPACE characters,
                    be sure to quote the path properly.

Examples:

  $MYNAME https://cx.my.com/cxrestapi joe pass1234 my-cx-project cx_report.xml
" >&2
   exit 1
fi

CX_URL_BASE="$1"; shift
print_msg "Checkmarx server URL root: '$CX_URL_BASE'"

CX_USER="$1"; shift
print_msg "Username: '$CX_USER'"
user=$(url_encode "$CX_USER")

CX_PASSWORD="$1"; shift
print_msg "Password: (hidden)"
pwd=$(url_encode "$CX_PASSWORD")

CX_PROJECT="$1"; shift
print_msg "Project: '$CX_PROJECT'"
proj=$(url_encode "$CX_PROJECT")

OUT_FILE="$1"; shift
print_msg "Output file: '$OUT_FILE'"


########################################################################
# 1) Authenticate to obtain the token.
########################################################################
post_data="username=${user}&password=${pwd}&grant_type=password&scope=sast_rest_api&client_id=${CX_CLIENT_ID}&client_secret=${CX_CLIENT_SECRET}"
result=$(curl -s -X POST --header "Content-Type: application/x-www-form-urlencoded" --header "Accept: $DOC_FORMAT" -d "$post_data" ${CX_URL_BASE}/auth/identity/connect/token)

# Extract the token (looks like a JWT).
token=$(jq -r '.access_token' <<< "$result")

if [ ! "$token" ] || [ "$token" == "null" ]; then
    print_msg "ERROR  authentication failure:
$result"
    exit 1
fi


########################################################################
# 2) List the project.
########################################################################
result=$(curl -s -X GET --header "Authorization: Bearer $token" --header "Accept: $DOC_FORMAT" ${CX_URL_BASE}/projects)

# Obtain the project ID.
pid=$(jq -r '.[] | select (.name == "'"$CX_PROJECT"'") | .id' <<< "$result")

if [ ! "$pid" ] || [ "$pid" == "null" ]; then
    print_msg "ERROR  unable to locate project '$CX_PROJECT'."
    exit 1
fi
print_msg "Project '$CX_PROJECT' found with ID $pid."


########################################################################
# 3) Get the latest Finished scan ID of the project.
########################################################################
result=$(curl -s -X GET --header "Authorization: Bearer $token" --header "Accept: $DOC_FORMAT" ${CX_URL_BASE}/sast/scans?projectId=$pid&last=1&scanStatus=Finished)
sid=$(jq -r '.[0].id' <<< "$result")

if [ ! "$sid" ] || [ "$sid" == "null" ]; then
    print_msg "ERROR  unable to find finished scans for '$CX_PROJECT'."
    exit 1
fi
print_msg "Found scan ID $sid."


########################################################################
# Register a new XML report.
########################################################################
post_data='{
  "reportType": "XML",
  "scanId": '$sid'
}'
result=$(curl -s -X POST --header "Authorization: Bearer $token" --header "Content-Type: application/json" --header "Accept: $DOC_FORMAT" -d "$post_data" ${CX_URL_BASE}/reports/sastscan)

# Examine the response for next step details.
rid=$(jq -r '.reportId' <<< "$result")

if [ ! "$rid" ] || [ "$rid" == "null" ]; then
    print_msg "ERROR  failed registering a new report:
$result"
    exit 1
fi
print_msg "Got report id $rid."


########################################################################
# Go into 5 second loop checking for the report status.
########################################################################
while :
do
    sleep 5
    result=$(curl -s -X GET --header "Authorization: Bearer $token" --header "Accept: $DOC_FORMAT" ${CX_URL_BASE}/reports/sastscan/$rid/status)
    rstatus=$(jq -r '.status.id' <<< "$result")

    # 1 = In Process
    if   [ "$rstatus" == "1" ]; then
        print_msg "Report still in process..."
        continue

    # 2 = Created (done)
    elif [ "$rstatus" == "2" ]; then
        # Extract the report.
        ruri=$(jq -r '.link.uri' <<< "$result")
        rctype=$(jq -r '.contentType' <<< "$result")
        curl -s -X GET --header "Authorization: Bearer $token" --header "Accept: $rctype" ${CX_URL_BASE}$ruri > "$OUT_FILE"
        break

    # 3 = Failed
    elif [ "$rstatus" == "3" ]; then 
        print_msg "ERROR  report generation failed."
        exit 1

    # This should not happen.
    else
        print_msg "ERROR  received unknown report status code '$rstatus'."
        exit 1
    fi
done


########################################################################
# Done.
########################################################################
print_msg "Done."
