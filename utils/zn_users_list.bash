#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to extract Users list for the customer account specified by the
# API token. Prints out the essential information in CSV format.
#
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
MY_DIR=`dirname $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# HELP infomration and input params
########################################################################
if [ ! "$1" ]
then
    echo "
Script to extract Users list for the customer account specified by the
API token. Prints out the essential information in CSV format.


Usage: $MY_NAME [NO_HEADERS] ALL [<key_file>]

  Example: $MY_NAME ALL
           $MY_NAME NO_HEADERS ALL key_file

where,

  NO_HEADERS  - If specified, does not print field headings.

  ALL         - Required parameter for safety.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
" >&2
    exit 1
fi

if [ "$1" == "NO_HEADERS" ]; then
    NO_HEADERS=1
    shift
fi

ALL_PARAM="$1"; shift
if [ "$ALL_PARAM" != "ALL" ]
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
# Look up the customer name.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")
cust_name=$(echo "$result" | jq -r '.customer.data.name')
print_msg "Customer account = '$cust_name'"


########################################################################
# Extract the list of the Users in the customer account.
########################################################################

# Get the list of Users.
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/users?limit=2000")

# How many Users?
user_count=$(echo "$result" | jq -r '.[1].count')
if [ $user_count -eq 0 ]; then
    print_msg "No users found. Exiting."
    exit
else
    print_msg "Found $user_count Users."
fi

# Optinally print the column headings.
[ "$NO_HEADERS" ] || echo "customerName,userId,userName,userEmail,role,isEnabled,isSSOUser"

# Output the Users list.
echo "$result" | jq -r '.[0][] | "'"$cust_name"'"+","+.id+","+.data.name+","+.data.email+","+.data.auth.universal[].role+","+(.data.isEnabled|tostring)+","+(if (.data.useMfa) then "false" else "true" end)'


########################################################################
# Done.
########################################################################
print_msg "Done."
