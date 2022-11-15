#!/bin/bash
########################################################################
# (c) Copyright 2022, Harness, Inc., support@harness.io
#
# Script to add, retrieve, or delete a usernamePassword type secret.
#
# Requires: curl, jq
########################################################################
MY_NAME=`basename $0`


########################################################################
# Basic functions
########################################################################

#----------------------------------------------------------------------
# Functions to print time-stamped messages
#----------------------------------------------------------------------
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME:${BASH_LINENO[0]}  $1" >&2
}


#----------------------------------------------------------------------
# Function to URL-encode the specified string.
#----------------------------------------------------------------------
function url_encode {
    sed 's/:/%3A/g; s/\//%2f/g; s/ /%20/g' <<< "$1"
}


#----------------------------------------------------------------------
# Function to exit the script with exit status 1 (error).
#----------------------------------------------------------------------
function func_die {
    print_msg "Exiting due to an error."
    exit 1
}


#-----------------------------------------------------------------------
# Function to check ZeroNorth REST API response code.
#
# NOTE: This function is not recommended when dealing with large amount
# of response data as the value of the data to evaluate is being passed
# as a copy of the original.
#-----------------------------------------------------------------------
function func_check_response {
    result="$1"

    if [[ "$result" =~ '"status":' ]] || [[ "$result" =~ '"statusCode":' ]]; then
        response=$(jq '.status+.statusCode' <<< "$result")
        if [ "$response" -gt 299 ]; then
            print_msg "ERROR: API call returned error response code ${response}, with message:
${result}"
            return 1
        fi
    fi
}


########################################################################
# Read and validate input params.
########################################################################
if [ ! "$1" ]
then
    echo "
Script to add, retrieve, or delete a usernamePassword type secret.
A usernamePassword type secret in ZeroNorth is just that, a secret that
has two parts: 1) username (string) and 2) password (string).

Requires: curl, jq


Usage: $MY_NAME <mode> [<secret_key>] [<key_file>]

where,

  <mode>     - One of:

               ADD - Add a new secret. This mode is allowed only when running
                     this script from a terminal, because it will prompt the
                     user for <username> and <password>.

                     IMPORTANT: a successful ADD operation will print the
                     resulting secret key (a 45-character string) as the
                     output of this script. Capture and store this securely.
                     You will NEVER see it again.

               GET - Retrieve the secret specified by <secret_key>.
               DELETE - Delete the secret specified by <secret_key>.

                     The secret key is a 45-character string. For example:
                     MNF39DeyTAqlZea-5hHBHA/ZHzwCdEdQuyNUE-wXP8U4T

  <key_file> - Optionally, the file with the ZeroNorth API key. If not
               provided, will use the value in the API_KEY variable,
               which can be supplied as an environment variable or be
               set inside the script.


Examples:

  $MY_NAME ADD
  $MY_NAME ADD my_key_file
  $MY_NAME GET MNF39DeyTAqlZea-5hHBHA/ZHzwCdEdQuyNUE-wXP8U4T
  $MY_NAME GET MNF39DeyTAqlZea-5hHBHA/ZHzwCdEdQuyNUE-wXP8U4T my_key_file
  $MY_NAME DELETE MNF39DeyTAqlZea-5hHBHA/ZHzwCdEdQuyNUE-wXP8U4T
  $MY_NAME DELETE MNF39DeyTAqlZea-5hHBHA/ZHzwCdEdQuyNUE-wXP8U4T my_key_file

" >&2
   exit 1
fi

# Get the mode.
MODE="$1"; shift
if   [ "$MODE" == "ADD" ]; then
    print_msg "MODE: '$MODE'"

    if [ ! "$TERM" ]; then
        print_msg "ERROR: ADD is allowed only from a terminal."
        func_die
    fi

    read -p "Enter username: " UNAME
    read -s -p "Enter password: " PASSW; echo

elif [ "$MODE" == "GET" ] || [ "$MODE" == "DELETE" ]; then
    print_msg "MODE: '$MODE'"
    SECRET_KEY="$1"; shift

else
    print_msg "ERROR: '$MODE' is not supported. Specify one of 'ADD', 'GET', or 'DELETE'."
    func_die
fi

# Read in the API key.
[ "$1" ] && API_KEY=$(cat "$1")

if [ ! "$API_KEY" ]
then
    print_msg "ERROR: No API key provided!"
    func_die
fi


########################################################################
# Constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"

ZN_SECRET_TYPE="usernamePassword"


########################################################################
# Look up the customer name. It's a good test of the API_KEY.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")
func_check_response "$result" || func_die

cust_name=$(jq -r '.customer.data.name' <<< "$result")
if [ ! "$cust_name" ]; then
    print_msg "ERROR: unable to retrieve customer name."
    func_die
fi
print_msg "Customer: '$cust_name'"


########################################################################
# Let's do it!
########################################################################
if [ "$MODE" == "ADD" ]; then
    # For ADD - add a new secret and output the resulting secret key.
    print_msg "Creating a new secret of type '$ZN_SECRET_TYPE'..."

    data="{
  \"type\": \"${ZN_SECRET_TYPE}\",
  \"secret\": { \"username\":\"${UNAME}\",\"password\":\"${PASSW}\" },
  \"description\": \"Added by ${MY_NAME}\"
}"

    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "$data" "${URL_ROOT}/secrets")
    func_check_response "$result" || func_die

    # Output the secret key.
    jq -r '.key' <<< "$result"


elif [ "$MODE" == "GET" ]; then
    # For GET - retrieve the secret key, printing the result to STDOUT in
    # the username:password format.

    secret_encoded=$(url_encode "${SECRET_KEY}")
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/secrets/${secret_encoded}")
    func_check_response "$result" || func_die

    # Output the values as username:password.
    jq -r '.data.secret | .username+":"+.password' <<< "$result"


elif [ "$MODE" == "DELETE" ]; then
    # For DELETE - delete the secret key.
    secret_encoded=$(url_encode "${SECRET_KEY}")
    result=$(curl -s -X DELETE --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/secrets/${secret_encoded}")
    func_check_response "$result" || func_die

    print_msg "Secrete successfully deleted."


else
    print_msg "'$MODE' is not yet supported."

fi


########################################################################
# Done.
########################################################################
print_msg "Done."
