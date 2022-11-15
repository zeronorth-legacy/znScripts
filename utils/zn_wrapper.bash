#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# This script is a generic wrapper for the various ZN scripts. It will
# iterate through the customer accounts assumable by the the provided
# API Token and executes the specified script (with the specified params
# for each assumable account.
#
# REQUIREMENTS: curl, jq
#               assume_get_key.bash script in the same folder
#               For safety reasons, the script to execute must reside in
#               the same folder as this script.
########################################################################
# Basic Constants
########################################################################
MY_NAME=`basename $0`
MY_DIR=`dirname $0`
ASSUME_SCRIPT="assume_get_key.bash"
MIN_TOKEN_LEN=1000
SEPARATOR="#########################################"


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Help and input params.
########################################################################
if ( [ $API_KEY ] && [ ! "$1" ] ) || ( [ ! $API_KEY ] && [ ! "$2" ] )
then
    echo "
This script is a generic wrapper for the various ZN scripts. It will iterate
through the customer accounts assumable by the the provided API token and
executes the specified script (with the specified params for each assumable
account.

REQUIREMENTS: The script to execute must be in the same directory as me.
              $ASSUME_SCRIPT must be in the same directory as me.
              curl and jq

Usage: $MY_NAME [<key_file>] [INCLUDE_ROOT] <script name> <params to pass to the script...>

  Examples:
    $MY_NAME my_script.bash param1 param2
    $MY_NAME keys_file my_script.bash param1 param2

where,

  <key_file>   -  Use this parameter to specify the path to the API key file
                  ONLY if you are not providing the API key via the API_KEY
                  environment variable (the preferred method).

  INCLUDE_ROOT  - If specified, will include the root (top-level) account in
                  the iterations. Otherwise, will iterate through only the
                  assumable accounts.

  <script name> - The name of the script to execute. The specified script must
                  be in the same directory as this script.

  <params>      - The parameters to pass on to the script being run.


All log/diagnostic messages by this script are written to STDERR. This script
does not alter what output streams the executing script writes to.

" >&2
    exit 1
fi

# Conditionally, read in the API token.
if [ ! $API_KEY ]; then
    API_KEY=`cat $1`; shift
fi

# Check the length of the API key.
key_len=$(echo "$API_KEY" | wc -c)
if [ ! -n $key_len ] || [ $key_len -lt $MIN_TOKEN_LEN ]; then
    print_msg "ERROR: the API token seems too short at $key_len bytes. Existing."
    exit 1
fi

# Keep the main API key for myself.
ROOT_KEY=$API_KEY

# Optional INCLUDE_ROOT param
if [ "$1" == "INCLUDE_ROOT" ]; then
    INCLUDE_ROOT=1
    shift
    print_msg "'InCLUDE_ROOT' Specified. Will include the root account."
fi

# Read in the target script name.
SCRIPT_NAME="$1"; shift
print_msg "Target script: '$SCRIPT_NAME'"

# Read in the parameters. Typically, we expect "ALL".
PARAMS="$*"
print_msg "Parameters to pass on: '$PARAMS'"


########################################################################
# Web Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${ROOT_KEY}"


########################################################################
# Who am I?
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")

# Check response statusCode.
statusCode=$(echo "$result" | jq -r '.statusCode')
if [ $statusCode != "null" ] && [ $statusCode -gt 299 ]; then
    print_msg "ERROR: failed to lookup your profile."
    echo "$result" | jq -r '.error'
    echo "$result" | jq -r '.message'
    print_msg "Exiting."
    exit 1
fi

# The following line assumes that emails don't have white space.
my_info=$(echo "$result" | jq -r '.email+" "+.customer.id+" "+.customer.data.name')
read my_email cust_id cust_name <<< "$my_info"
print_msg "You are '$my_email' at '$cust_name' ($cust_id)."


########################################################################
# Extract the list of the assumable customers from the above result.
########################################################################
assumables=$(echo "$result" | jq -r '.customer.data.assumableCustomers | sort_by(.name) | .[] | .id+" "+.name')

if [ ! "$assumables" ]; then
    print_msg "No assumable customers. Exiting."
    exit
fi

# How many assumable customers?
assumables_count=$(echo "$assumables" | wc -l)

# Optionally prepend the root account.
if [ "$INCLUDE_ROOT" ]; then
    assumables=$(echo $cust_id $cust_name; echo "$assumables")
    print_msg "Root account plus $assumables_count assumable accounts."
else
    print_msg "$assumables_count assumable accounts."
fi

accounts_count=$(echo "$assumables" | wc -l)


########################################################################
# Interate through the assumable customers.
########################################################################
i=0
while read cust_id cust_name
do
    (( i = i + 1 ))
    print_msg "$SEPARATOR"
    print_msg "Customer $i of $accounts_count: $cust_id '$cust_name'..."

    # Assume into the customer account, obtaining an API token.
    export API_KEY=$ROOT_KEY
    assume_key=`${MY_DIR}/${ASSUME_SCRIPT} $cust_id`

    # Examine the key for minimum length (2,000 bytes).
    key_len=$(echo "$assume_key" | wc -c)
    if [ ! -n $key_len ] || [ $key_len -lt $MIN_TOKEN_LEN ]; then
        print_msg "ERROR: the API token seems too short at $key_len bytes. Skipping this customer."
        continue
    fi

    # Set the API token for the script to call.
    export API_KEY=$assume_key

    # Look up the new profile to ensure that it matches.
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "Authorization: ${API_KEY}" "${URL_ROOT}/accounts/me")
    new_me=$(echo "$result" | jq -r '.customer.data.name')

    if [ "$new_me" != "$cust_name" ]; then
        print_msg "ERROR: Critical error, assume failed. Exiting the script."
        exit 1
    fi
    print_msg "Confirming that I am now '$new_me' and therefore proceeding..."

    # Execute the Target script.
    print_msg "Executing script: '${MY_DIR}/${SCRIPT_NAME} $PARAMS'"
    "$MY_DIR"/"$SCRIPT_NAME" $PARAMS
    print_msg "Back from the script call with exit status of '$?'."
done <<< "$assumables"
print_msg "$SEPARATOR"


########################################################################
# Done.
########################################################################
print_msg "Done."
