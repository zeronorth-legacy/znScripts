#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to administer ZeroNorth "platform" (i.e., non-sso) users.
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
#
# IMPORTANT: An API key generated using the above method has life span
# of 10 calendar years.
#
########################################################################
MY_NAME=`basename $0`
MY_DIR=`dirname $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME:${BASH_LINENO[0]}  $1" >&2
}


########################################################################
# Function to check ZeroNorth REST API response code.
#
# NOTE: This function is not recommended when dealing with large amount
# of response data as the value of the data to evaluate is being passed
# as a copy of the original.
########################################################################
function func_check_response {
    result="$1"

    if [[ "$result" =~ '"statusCode":' ]]; then
        response=$(jq '.statusCode' <<< "$result")
        if [ "$response" -gt 299 ]; then
            print_msg "ERROR: API call returned error response code ${response}, with message:
${result}"  
            return 1
        fi
    fi
}


########################################################################
# HELP information and input params
########################################################################
if [ ! "$2" ]
then
    echo "
Script to administer ZeroNorth users. This script operates only for the non-SSO
user profiles, expept for when used in the 'LIST'mode, in which case all types
of user profiles can be listed.


Usage: $MY_NAME <mode> <user_email|ALL> [role] [<key_file>]

where,

  <mode>          - Must be one of (case sensitive):

                    LIST - If found, show the user details.
                           Specifying 'ALL' for the user email will list
                           all users.
                    ADD     - Add the user by the specified email address.

  <userEmail|ALL> - ZeroNorth users are identified by their email address.
                    NOT case sensitive. You can optionally specify 'ALL'
                    for the LIST mode.

  <role>          - For the ADD mode, specify the user's role as one of
                    (case sensitive):

                    admin        - administrator
                    user         - non-admin, ops user
                    userReadOnly - read-only user

  <key_file>      - Optionally, the file with the ZeroNorth API key. If not
                    provided, will use the value in the API_KEY variable,
                    which can be supplied as an environment variable or be
                    set inside the script.


Examples: $MY_NAME LIST joe@me.com
          $MY_NAME LIST ALL
          $MY_NAME ADD joe@me.com userReadOnly
          $MY_NAME ADD joe@me.com admin my-key-file
" >&2
    exit 1
fi


########################################################################
# Read input params.
########################################################################

# Get the input mode.
MODE="$1"; shift
if ( [ "$MODE" != "LIST" ] && [ "$MODE" != "ADD" ] ); then
    print_msg "ERROR: '$MODE' is not a valid mode. Exiting."
    exit 1
fi
print_msg "Mode: '${MODE}'"

# Read in the email address.
U_EMAIL="$1"; shift
if [ "$U_EMAIL" == "ALL" ] && [ "$MODE" != "LIST" ]; then
    print_msg "ERROR: 'ALL' valid only for the 'LIST' mode. Exiting."
    exit 1
fi

[ "$U_EMAIL" != "ALL" ] && print_msg "User email: '$U_EMAIL'"

# Read in the user role for ADD mode.
if [ "$MODE" == "ADD" ]; then
    U_ROLE="$1"; shift
    if [ "$U_ROLE" != "admin" ] && [ "$U_ROLE" != "user" ] && [ "$U_ROLE" != "userReadOnly" ]; then
        print_msg "ERROR: user role must be one of 'admin', 'user', 'userReadOnly'. Exiting."
        exit 1
    fi
    print_msg "User role: '$U_ROLE'"
fi

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
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"


########################################################################
# Functions for the core purposes of this script.
########################################################################

#-----------------------------------------------------------------------
# An Internal function to retrieve the full list of the users. This is
# necessary/userful, becuase the [GET] /v1/users API endpoint does not
# have filter query options.
#
# Input:  None
# Output: The users list as an array of JSON objects
#         If no users, returns nothing (not an empty array).
#-----------------------------------------------------------------------
function func_find_all_users {

    # Get the full list of Users.
    result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/users?limit=2000")
    func_check_response "$result" || exit 1

    # Are there any uers?
    user_count=$(jq -r '.[1].count' <<< "$result")

    # No.
    [ $user_count -eq 0 ] && return

    # yes.
    jq -r '.[0]' <<< "$result"
}


#-----------------------------------------------------------------------
# An Internal function to retrieve a user by the specified email. This
# is necessary/userful, becuase the [GET] /v1/users API endpoint does
# not have filter query options.
#
# NOTE that an email can match multiple user profiles.
#
# Input:  user email
# Output: The users list as an array of JSON objects
#         If no matching users, returns nothing (not an empty array).
#-----------------------------------------------------------------------
function func_find_a_user {

    # Get the full list of Users.
    list=$(func_find_all_users)

    # No users.
    [ ! "$list" ] && return

    list=$(jq -r '[.[] | select((.data.email|ascii_downcase)==("'"$u_email"'"|ascii_downcase))]' <<< "$list")

    # Are there any matches?
    user_count=$(jq -r '. | length' <<< "$list")

    [ "$user_count" -eq 0 ] && return

    echo "$list"
}


#-----------------------------------------------------------------------
# Function to list one or ALL users.
#
# Input:  user email or 'ALL'
# Output: listing of matching user or all users
#-----------------------------------------------------------------------
function func_list_user {
    u_email="$1"

    if [ "$u_email" == "ALL" ]; then
        list=$(func_find_all_users)
        if [ ! "$list" ]; then
            print_msg "There are no users."
            return
        fi
    else
        list=$(func_find_a_user "$u_email")
        if [ ! "$list" ]; then
            print_msg "There are no matching users."
            return
        fi
    fi

    if [ ! "$list" ]; then
        print_msg "There are no users."
        return
    fi

    # Print the column headings.
    echo "customerName,userId,userName,userEmail,role,isEnabled,type"

    # Output the Users list.
    echo "$list" | jq -r '.[] | "'"$cust_name"'"+","+.id+","+.data.name+","+.data.email+","+.data.auth.universal[].role+","+(.data.isEnabled|tostring)+","+(if (.data.type=="openidConnection") then "SSO" else "Platform" end)'
}


#-----------------------------------------------------------------------
# Function to add one or more users. Checks to ensure that the specified
# email address is not already in the system as a "Platform" user.
#
# Input:  user email
#         user role, must be one of 'admin', 'user', 'userReadOnly'
# Output: None
#-----------------------------------------------------------------------
function func_add_user {
    u_email="$1"; shift
    u_role="$1"; shift

    # First, check to see that the user doesn't aready exist.
    list=$(func_find_a_user "$u_email")

    # Something was found. Look closer.
    if [ "$list" ]; then
        # Look to see if any of the profiles are "Platform" profiles.
        count=$(jq -r '[.[] | select(.data.type=="auth0")] | length' <<< "$list")
        if [ "$count" -gt 0 ]; then
            print_msg "User '$u_email' already exists in the system."
            return
        fi
    fi

    # Construct the JSON payload
    data="{
  \"email\": \"$u_email\",
  \"role\": \"$u_role\",
  \"useMfa\": true,
  \"isEnabled\": true
}"

    # Add the specified user.
    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "$data" "${URL_ROOT}/users")
    func_check_response "$result" || exit 1

    # Extract the resulting user ID.
    u_id=$(jq -r '.id' <<< "$result")
    print_msg "User '$u_email' created with the ID '$u_id'."

    echo "$u_id"
}


########################################################################
# Look up the customer name. It's a good test of the API_KEY.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")
func_check_response "$result" || exit 1

cust_name=$(jq -r '.customer.data.name' <<< "$result")
if [ ! "$cust_name" ]; then
    print_msg "ERROR: unable to retrieve customer name. Exiting."
    exit 1
fi
print_msg "Customer = '$cust_name'"


########################################################################
# "MAIN" - process the user request by calling various function.
########################################################################

# Process the input command.
if   [ "$MODE" == "LIST" ]; then
    func_list_user "$U_EMAIL"
elif [ "$MODE" == "ADD" ]; then
    func_add_user "$U_EMAIL" "$U_ROLE"
# elif [ "$MODE" == "DISABLE" ]; then
#     func_disable_user "$U_EMAIL"
# elif [ "$MODE" == "DELETE" ]; then
#     func_delete_user "$U_EMAIL"
else
    print_msg "ERROR: command '$MODE' is not yet supported."
    exit 1
fi


########################################################################
# The End
########################################################################
print_msg "Done."
