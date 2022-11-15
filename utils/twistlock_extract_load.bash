#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2019-Aug, support@zeronorth.io
#
# Script using CURL to first extract a specified Twistlock image scan
# results (a JSON file) and then to upload the JSON file to a ZeroNorth
# Policy.
#
# Requires: curl
#           zn_upload_issues.bash in the same directory as this script.
#
# Before using this script sign-in to https://fabric.zeronorth.io to
# prepare a shell Policy that will accept the issues:
#
# 1) Go to znADM -> Scenarios. Locate and activate a Scenario for
#    Twistlock.
#
# 2) Go to znADM -> Integrations -> Add an Integration of type "Docker".
#    setting Initiate Scan From to "MANUAL". It is not necessary for
#    this Integration to actually connect to a Docker registry. So, one
#    can use "dummy" for URL, Username, and Password.
#
# 3) Go to znOPS -> Targets -> Add Target. Using the Integration from
#    step 2, create a shell Target.
#
# 4) Go to znOPS -> Policies -> Add Policy. Create a shell policy using
#    the items from the above steps.
#
# Related information in ZeroNorth KB at:
#
#    https://support.zeronorth.io/hc/en-us/articles/115001945114
#
########################################################################
#
# Before using this script, obtain your API key using the instructions
# outlined in the following KB article:
#
#   https://support.zeronorth.io/hc/en-us/articles/115003679033
#
# IMPORTANT: An API key generated using the above method has life span
# of 10 years.
#
########################################################################
MY_DIR="`dirname $0`"


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$3" ]
then
    echo "
Usage: `basename $0` <image name> <policy ID> <creds_file>

  Example: `basename $0` myImage:latest QIbGECkWRbKvhL40ZvsVWh twist.creds

where,
  <image name> - Name of the container image whose scan results you
                 want to extract for loading into ZeroNorth.

  <policy ID>  - The ID of the ZeroNorth Policy you want to load the data to.

  <creds_file> - The file with credentials for both the Twistlock API and the
                 ZeroNorth API. The file should set two env variable like this
                 (omit the angled brackets):

                 export TWIST_CRED=<username>:<password>
                 export API_KEY=<ZeroNorth API key>
" >&2
    exit 1
else
    IMAGE_NAME="$1"; shift
    print_msg "Image Name: '${IMAGE_NAME}'"
    POLICY_ID="$1"; shift
    print_msg "Policy ID: '${POLICY_ID}'"
    CRED_FILE="$1"; shift
    print_msg "Creds file: '${CRED_FILE}'"
fi

#
# Input validation
#
if ( [ ! -e "$CRED_FILE" ] || [ ! -s "$CRED_FILE" ] || [ ! -r "$CRED_FILE" ] )
then
    print_msg "The specified credentials file '$CRED_FILE' is missing, empty, or not readable."
    exit 1
fi

. "$CRED_FILE"

if [ ! "${TWIST_CRED}" ]
then
    echo "No Twistlock credentials provided! Exiting."
    exit 1
fi

if [ ! "${API_KEY}" ]
then
    echo "No ZeroNorth API key provided! Exiting."
    exit 1
fi

########################################################################
# Constants
########################################################################
TWIST_API_ROOT="https://twistlock.aetna.com:8083/api/v1"
ZN_API_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"
UPLOAD_SCRIPT="zn_upload_issues.bash"


########################################################################
# The below code does the following:
#
# 0) Prepare a temporary file to hold the extract results.
# 1) Uses curl to extract the Twistlock scan results as a JSON file.
# 2) Calls zn_upload_issues.bash to upload the the issues in the JSON
#    file to the Policy with the specified Policy ID.
########################################################################

########################################################################
# 0) Use curl to extract the Twistlock scan results as a JSON file.
########################################################################
#
# Find a suitable working directory
#
[ "${TEMP}" ] && TEMP_DIR="${TEMP}" || TEMP_DIR="/tmp"
#
# Create the working file in the working directory
#
TEMP_FILE="${TEMP_DIR}/twist_issues.`date '+%s'`.json"
touch "${TEMP_FILE}"
#
# Check to see that we got a file created.
#
if [ ! -e "${TEMP_FILE}" ]
then
    print_msg "Error creating '${TEMP_FILE}' for temporary results file."
    exit 1
fi


########################################################################
# 1) Use curl to extract the Twistlock scan results as a JSON file.
########################################################################
#
# First, check to see if a Policy by same name exists
#
result=$(curl -s -u "${TWIST_CRED}" -X GET "${TWIST_API_ROOT}/images/${IMAGE_NAME}" > ${TEMP_FILE})



########################################################################
# 2) Call the zn_upload_issues.bash script with the results from above.
########################################################################

if [ ! "`which ${MY_DIR}/${UPLOAD_SCRIPT}`" ]
then
    print_msg "Can't find '${UPLOAD_SCRIPT}'. Make sure it's installed in '${MY_DIR}'."
    exit 1
fi

print_msg "Invoking '${UPLOAD_SCRIPT}' to upload the results..."
print_msg "${MY_DIR}/${UPLOAD_SCRIPT} ${POLICY_ID} ${TEMP_FILE}"
${MY_DIR}/${UPLOAD_SCRIPT} ${POLICY_ID} ${TEMP_FILE}

if [ "$?" -gt 0 ]
then
    print_msg "Error while running '${UPLOAD_SCRIPT}.'"
    exit 1
fi


########################################################################
# The End
########################################################################
[ "${TEMP_FILE}" ] && [ -w ${TEMP_FILE} ] && rm "${TEMP_FILE}" && print_msg "Temp file '${TEMP_FILE}' removed."
print_msg "Done."
