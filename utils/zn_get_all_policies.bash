#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc. support@zeronorth.io
#
# Policies inventory script.
#
# Requires: curl, sed, jq
#
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
# of 10 calendar years.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."


########################################################################
# Who am I?
########################################################################
MY_NAME=`basename $0`
MAX_POLS=1000


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Read input and print help if input is not right.
########################################################################
if [ ! "$1" ]; then
    echo "
A script to inventory the Policies. By default, this script will list
up to 1000 Policies. If you have more than that, modify the variable
MAX_POLS within this script.

Prints out the following information:

  Policy ID
  Policy Name
  Target ID
  Target Name
  Target Type
  Scenario ID
  Scenario Name
  Policy Type
  Policy Site
and optionally,
  Schedule Count (typically, 0 or 1)
  Schedule Code (in cron-like format)


Usage: $MY_NAME [NO_HEADERS] ALL [SCHEDULE] [<key_file>]

where,

  NO_HEADERS  - If specified, does not print field heading.

  ALL         - Required for safety.

  SCHEDULE    - If specified, will also extract the Policy Schedule if
                there is one. This option significantly increases the
                time this script takes.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.

Examples: $MY_NAME ALL
          $MY_NAME ALL MyKeyFile


See also: 
" >&2
    exit 1
fi


# The option to suppress headers.
if [ "$1" == "NO_HEADERS" ]; then
    NO_HEADERS=1
    shift
fi

# Required "ALL" keyword for safety.
ALL_ID="$1"; shift
if [ "$ALL_ID" != "ALL" ]
then
    print_msg "ERROR: You must specify 'ALL' as the first parameter. Exiting."
    exit 1
fi

# The option to add Schedule info.
if [ "$1" == "SCHEDULE" ]; then
    SCHEDULE=1
    shift
    print_msg "The output will include Policy scheduls, if any."
fi

# API token.
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
# List all policies for this account.
########################################################################
print_msg "Retrieving Policies list..."
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies?limit=$MAX_POLS")

# Were there any Policies?
count=$(echo "$result" | jq -r '. | .[1].count')
if [ ! $count -gt 0 ]; then
    print_msg "No policies found. Exiting."
    exit
fi
print_msg "Found $count Policies."


# Print the field headers.
if [ ! "$NO_HEADERS" ]; then
    echo -n 'polId|polName|tgtId|tgtName|tgtType|scenarioId|scenarioName'
    [ "$SCHEDULE" ] && echo -n '|schedCount|schedCode'
    echo
fi


# Parse the Policies list.
policies=$(echo "$result" | jq -r '.[0][]|.id+"|"+(.data|.name+"|"+(.targets[0]|.id+"|"+.targetName)+"|"+.environmentType+"|"+(.scenarios[0]|.id+"|"+.name))')

# Iterate through the Policies.
while IFS="|" read pol_id pol_rest
do
    # Print the basic Policy info.
    echo -n "$pol_id|$pol_rest"

    if [ "$SCHEDULE" ]; then
        # Look up any Policy Schedule(s).
        result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/${pol_id}/schedules")

        # Just print out the first one, if any.
        echo "$result" | jq -r '"|"+(.[1].count|tostring)+"|"+.[0][0].data.pattern'
    else
        echo
    fi # SCHEDULE
done <<< "$policies"


########################################################################
# Done.
########################################################################
print_msg "Done."
