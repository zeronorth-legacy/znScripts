#!/bin/bash
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., 2018-Dec, support@zeronorth.io
#
# NOTE: This script does NOT work on MacOS.
# NOTE: This script does NOT work on MacOS.
# NOTE: This script does NOT work on MacOS.
#
# This example shows a sequence of BASH commands to extract up to
# 10,000 SonarQube Issues. Requires sed, egrep, curl, and jq.
#
# To use:
#
# 1) Edit the variable SONAR_URL with the URL to your SonarQube server.
#
# 2) Check step 2 for additional instructions about limiting your Issues
#    export to certain severities and certain types. This is especially
#    useful if your project has more than 10,000 issues. By default, it
#    will extract Issues, Bugs, and Code Smells of all severities except
#    for INFO level severity.
#
# 3) Project key and Sonar API key must be passed in as parameters.
########################################################################

########################################################################
# Constants
########################################################################
#
# Leave out the trailing "/" when specifycing the URL.
# Don't forget the port number if applicable.
#
SONAR_URL="https://sonarqube.mycompany.com"


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


if [ ! "$2" ]
then
    echo "
IMPORTANT: Prior to using this script, edit it and set the variable SONAR_URL.
IMPORTANT: Prior to using this script, edit it and set the variable SONAR_URL.
IMPORTANT: Prior to using this script, edit it and set the variable SONAR_URL.

Usage: `basename $0` <project_key> <sonar_key>

  Example: `basename $0` MyProject.name 4522745adbae325484cc55b7f6ffae8d69cc2318

where,
  <project_key> - The Application ID (project "Key") as known in Sonar.
  <sonar_key>   - The API key to access the SonarQube server with.
" >&2
    exit 1
else
    PROJECT_KEY="$1"; shift
    print_msg "Project Key: '${PROJECT_KEY}'"
    SONAR_KEY="$1"; shift
    print_msg "Sonar Key accepted."
fi


########################################################################
# 1. Prepare the file to write to.
########################################################################
# Prepare unique string for the temporary work files
TEMP_FILE_PREFIX="sonar.${PROJECT_KEY}"

# Create an empty extract file
echo -n > ${TEMP_FILE_PREFIX}.out.json


########################################################################
# 2. Extract the Sonar Issues by having curl iterate. By default, it
#    will export issues of all types and all severities, except for INFO
#    level severities. If you want to limit your export, add/edit these
#    query parameters:
#      &severities=BLOCKER,CRITICAL,MAJOR,MINOR
#      &types=VULNERABILITY,BUG,CODE_SMELL
#    The Sonar API limits total # of Issues extracted to 10,000.
########################################################################
curl -u ${SONAR_KEY}: "${SONAR_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&types=VULNERABILITY,BUG,CODE_SMELL&severities=BLOCKER,CRITICAL,MAJOR,MINOR&pageSize=500&p=[1-20]" >> ${TEMP_FILE_PREFIX}.out.json


########################################################################
# 3. The following long chain of commands does:
#    a) Strip away the curl command echoed into the output.
#    b) Extract just the issues arrays as entire bodies.
#    c) Omit the empty arrays (happens when there are less than 20 pages
#       of Issues.
#    d) Strip away the square brackets, replacing the closing bracket
#       with a comma.
#    e) Omit the final comma.
########################################################################
cat ${TEMP_FILE_PREFIX}.out.json | sed 's/--_curl_.*$//' | jq '.issues' | egrep -v '^\[\]$' | sed 's/^\[$//' | sed 's/^\]$/,/' | head -n -1 > ${TEMP_FILE_PREFIX}.elements.json


########################################################################
# 4. Complete the JSON structure by adding back the head and the tail.
########################################################################
echo '{"issues": [' > ${TEMP_FILE_PREFIX}.rebuilt.json
cat ${TEMP_FILE_PREFIX}.elements.json >> ${TEMP_FILE_PREFIX}.rebuilt.json
echo ']}' >> ${TEMP_FILE_PREFIX}.rebuilt.json


########################################################################
# 5. Make it look nice.
########################################################################
cat ${TEMP_FILE_PREFIX}.rebuilt.json | jq . > ${TEMP_FILE_PREFIX}.issues.json
print_msg "Results written to '${TEMP_FILE_PREFIX}.issues.json'."


########################################################################
# 6. Clean up after myself.
########################################################################
rm ${TEMP_FILE_PREFIX}.out.json ${TEMP_FILE_PREFIX}.elements.json ${TEMP_FILE_PREFIX}.rebuilt.json
