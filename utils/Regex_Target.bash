#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., 2020-Feb, support@zeronorth.io
#
# Script using CURL and SED to look-up/or create Artifact type Targets,
# and SonarQube Data Load Policies using the specified Target and
# Policy names. If the named objects alredy exist, they are reused.
#
# Before using this script sign-in to https://fabric.zeronorth.io and
# ensure that the necessary Integration (must of type "Artifact") and
# appropriate Scenarios exist.
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
# of 1 calendar year.
########################################################################

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}

########################################################################
# Constants
########################################################################

if [ ! "$2" ]
then
    echo "
Usage: `basename $0` <key file> <target file>

  Example: `basename $0` MyAPIKeyFile My_Targets

where,

  <key file>      - The file with the ZeroNorth API keys. The file should
                    contain only the API key as a single string.

  <target file>   - The file with all of the needed information about the 
  					targets being created which can be found above in the
					Constants info area
" >&2
    exit 1
fi

API_KEY=$(cat "$1"); shift
if [ $? != 0 ]; then
    echo "Can't read key file!!! Exiting."
    exit 1
fi

URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"

input="$1"; shift
pro=$(cat ${input})
echo "$pro" | while IFS="," read -r a b;
do
	PROJECT_NAME="$a"
	REGEX="$b"
	TARGET=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets" | jq -r '.[0][] | select(.data.parameters.name | strings | test("$REGEX")) | .id')
	result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications?expand=false")

	# How many matching targets?
	app_count=$(echo ${result} | sed 's/^.*\"count\"://' | sed 's/\,.*$//')

	# more than 1, die
	if [ $app_count -gt 1 ]; then
	    print_msg "Found multiple matches for the Application Name '${PROJECT_NAME}'!!! Exiting."
	    exit
		# exactly 1, we can use it
		elif [ $app_count -eq 1 ]; then
		    print_msg "Application '${PROJECT_NAME}' found."
			echo "$TARGET" | while IFS= -r line
			TARGET_ID="$line"
			PROJECT_ID=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications?expand=false&name="${PROJECT_NAME}"" | jq -r '.[0][].id')
			APPLICATION=$(curl -X PUT --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{\"name\": \"${PROJECT_NAME}\",\"targetIds\": \"${TARGET_ID}\",}" "${URL_ROOT}/applications/${PROJECT_ID}")
		# else (i.e. 0), we create one
	else
		echo "$TARGET" | while IFS= -r line
		TARGET_ID="$line"
		PROJECT_ID=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/applications?expand=false&name="${PROJECT_NAME}"" | jq -r '.[0][].id')
	APPLICATION=$(curl -X PUT --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "{\"name\": \"${PROJECT_NAME}\",\"targetIds\": \"${TARGET_ID}\",}" "${URL_ROOT}/applications")
done