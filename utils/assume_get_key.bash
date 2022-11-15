#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., support@zeronorth.io
#
# An administrator user can use this script to assume another customer
# account. This script makes convenient what one would do using the
# /v1/accounts/assume API call. Requires curl in your PATH.
#
# Input: Customer ID
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


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$1" ]
then
    echo "
Use this script to obtain a short-lived API Token for another account
your profile is allowed to assume. The result is the API token of the
assumable account printed to STDOUT.


Usage: `basename $0` <Customer ID> [<key_file>]

where,
  Customer ID  is the ID of the Customer account to assume
  key_file (optional) is the file with your own API key.

  If no key_file is provide, will use the value in the API_KEY
  environment variable.
" >&2
    exit 1
fi

# Read in the customer ID.
CUST_ID="$1"; shift
print_msg "Customer ID = '$CUST_ID'."

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
# The below code does the following:
#
# 1) Attempts to assume the customer indicate by the CUST_ID.
# 2) Print the resulting key if successful.
########################################################################

########################################################################
# 1) Assume the Customer using the CUST_ID.
########################################################################
result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d"{
  \"customerId\": \"${CUST_ID}\"
}" "${URL_ROOT}/accounts/assume")


########################################################################
# 2) Get the resulting API Key.
########################################################################
#
# First, check the resulting key type. It's a way of checking success.
#
key_type=$(echo ${result} | sed 's/^.*\"token_type\":\"//' | sed 's/\".*$//')

if [ "${key_type}" != "Bearer" ]
then
    print_msg "Failed to obtain the key." >&2
    exit 1
fi

api_key=$(echo ${result} | sed 's/^.*\"id_token\":\"//' | sed 's/\".*$//')
print_msg "===== API key below ====="
echo "${api_key}"
print_msg "===== API key above ====="

print_msg "Done."
