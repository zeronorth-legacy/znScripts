########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#
# A script to extract the SIEM data that the specified API token has access
# to and then print out the basic information in CSV format.
#
# Requires: curl, jq
#
########################################################################
MIN_TOKEN_LEN=1000
MAX_TOKEN_LEN=3000
MY_NAME=`basename $0`


########################################################################
# Help.
########################################################################
if [ ! "$1" ]; then
    echo "
************************************************************************
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
************************************************************************

A script to extract the SIEM data that the specified API token has access
to and then print out the basic information in CSV format.


Usage: $MY_NAME <lookback mins> [<key_file>]

where,

  <lookback mins> - The number of minutes to look back. Specify an integer.

  <key_file>      - Optionally, the file with the ZeroNorth API key. If not
                    provided, will use the value in the API_KEY variable.

" >&2
    exit 1
fi

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Read in the command line parameters.
########################################################################

# Read the look-back value.
LOOKBACK="$1"; shift
print_msg "Will look back ${LOOKBACK} minutes."

# The customer API key.
[ "$1" ] && API_KEY=$(cat "$1")
if [ ! "$API_KEY" ]; then
    print_msg "ERROR: Customer API key not provided! Exiting."
    exit 1
fi


########################################################################
# Web constants
########################################################################
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization: ${API_KEY}"
SIEM_URL="https://audit-trail.zeronorth.io/api/v1/cloudwatch/logs"


########################################################################
# 0) Look up the customer name. It's a good test of the API_KEY.
########################################################################
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")

# Check response code.
if [[ "$result" =~ '"statusCode":' ]]; then
    response=$(jq '.statusCode' <<< "$result")
    if [ $response -gt 299 ]; then
        print_msg "ERROR: API call for customer name look up failed:
${result}"
        exit 1
    fi
fi

cust_name=$(jq -r '.customer.data.name' <<< "$result")
if [ ! "$cust_name" ]; then
    print_msg "ERROR: unable to retrieve customer name. Exiting."
    exit 1
fi
print_msg "Customer = '$cust_name'"


########################################################################
# Compute the startTime time based on the specified look-back value.
########################################################################
now=$(date '+%s')
(( st = now - (60 * $LOOKBACK) ))
(( stm = st * 1000 ))
std=$(date --date="@${st}")
print_msg "startTime = '$stm', which is ${std}." >&2


########################################################################
# Retrieve the SIEM data using the legacy API endpoint.
########################################################################
# Make the SIEM query.
result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}"  -d "{\"startTime\": $stm}" "${SIEM_URL}")

# Check response code.
if [[ "$result" =~ '"statusCode":' ]]; then
    response=$(jq '.statusCode' <<< "$result")
    if [ $response -gt 299 ]; then
        print_msg "ERROR: API call for customer name look up failed:
${result}"
        exit 1
    fi
fi

# Check for other soft error conditions (hacky).
if [[ "$result" =~ ^'{"message":' ]]; then
    print_msg "ERROR: unexpected response:
${result}"
    exit 1
fi

# Print the column headings.
echo "dateTime(UTC),userEmail,userIPv4,activity"

# Parse the result and print the essential information as CSV.
jq -r '
.[] | 
(
  (.timestamp / 1000) | todate | sub("T";" ") | sub("Z";"")
)
+","+
(
  .message |
  (
    .identity.email
    +","+
    (
      if   (.identity.ipAddress != null) then
        .identity.ipAddress
      elif (.request.body.originHeaders[]|has("x-envoy-external-address")) then
        (.request.body.originHeaders[]|select(."x-envoy-external-address" != null)|."x-envoy-external-address")
      else
        empty
      end
    )
    +","+
    .message.data
  )
)
' <<< "$result"


########################################################################
# The end.
########################################################################
print_msg "Done."
