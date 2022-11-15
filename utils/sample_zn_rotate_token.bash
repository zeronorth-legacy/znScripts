#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# A demo script to show how to automated ZeroNorth long-lived API token
# rotation.
#
# Requires: curl, jq
#
########################################################################
#
# If you are not providing your API key via a file, before using
# this script, obtain your API_KEY via the UI. See KB article
# https://support.zeronorth.io/hc/en-us/articles/115003679033
#
#API_KEY="....."


########################################################################
# Because...
########################################################################
MY_NAME=`basename $0`
TOKEN_PREFIX="auto"


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$2" ]
then
    echo "
Use this script to obtain a new long-lived token and then delete the current
one. You must provide the customer account / tenant name, the ID of the
existing token, and the token value itself.


Usage: $MY_NAME <cust Name> <token ID> [<token_file>]

where,

  <cust name>   the name of the Customer account/tenant. While this information
                is implied in the API token you are providing via the key_file
                or via the API_KEY environment variable, specify it anyway for
                safety. Be sure to quote the name if it contains WHITE SPACE.

  <token ID>    The ID of the current token. Current token refers to the API
                token you are using for this script to access ZeroNorth. This
                ID is embedded in the current token, but we ask for it anyway
                for safety. The very first time you run this script, you can
                obtain the ID of the API token you are using by:

                1) Use the ZeroNorth API endpoint /v1/tokens to list and locate
                   your token.
                2) Parse your JWT and then look for the tokenId attribute.

  <token file>  Optionally, the path to the file that contains the API token.
                If omitted, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be set
                inside the script. If you are executing this script via
                SUDO, use must the key file method.


Output in two separate lines:

  <token ID>  The ID of the new token. Be sure to record this.

  <token>     The new token. This is a JWT and is seen only here, once. Be sure
              to record it securely.
" >&2
    exit 1
fi

# Read in the customer name.
CUST_NM="$1"; shift
print_msg "Customer Name (input) = '$CUST_NM'."

# Read in the token ID.
TOKEN_ID="$1"; shift
print_msg "Token ID = '$TOKEN_ID'."

# Read in the API key.
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
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"


########################################################################
# Look up and verify the customer/tenant name.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")
cust_nm=$(jq -r '.customer.data.name' <<< "$result")
print_msg "Customer name (found) = '$cust_nm'"

if [ "$CUST_NM" != "$cust_nm" ]; then
    print_msg "ERROR: found an unexpected customer account / tenant. Exiting."
    exit 1
fi


########################################################################
# Generate a new API token.
########################################################################
print_msg "Generating a new API token..."

dt_stamp=`date +'%Y-%m-%dT%T'`
result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d"{\"description\": \"${TOKEN_PREFIX}_${dt_stamp}\"}" "${URL_ROOT}/tokens")

# Check response code.
if [[ "$result" =~ '"statusCode":' ]]; then
    response=$(jq '.statusCode' <<< "$result")
    if [ $response -gt 299 ]; then
        print_msg "ERROR: API call for token creation failed:\n${result}"
        exit 1
    fi
fi

token_id=$(jq -r '.id' <<< "$result")
token_jwt=$(jq -r '.data.id_token' <<< "$result")

if [ ! "$token_id ] || [ ! "$token_jwt ]; then
    print_msg "ERROR: unable to retrieve token ID / JWT. Exiting."
    exit 1
fi


########################################################################
# Output the result
########################################################################
echo "$token_id"
echo "$token_jwt"


########################################################################
# Delete the current token.
########################################################################
print_msg "Deleting the current API token whose ID is '$TOKEN_ID'..."
#
# Note that we are talking about deleting the API token we are curently using.
#
result=$(curl -s -X DELETE --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/tokens/${TOKEN_ID}")

# Check response code.
if [[ "$result" =~ '"statusCode":' ]]; then
    response=$(jq '.statusCode' <<< "$result")
    if [ $response -gt 299 ]; then
        print_msg "WARNING: API call to delete the current token failed:\n${result}"
    fi
fi


########################################################################
# Done.
########################################################################
print_msg "Done."
