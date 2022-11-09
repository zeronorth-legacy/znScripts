########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#
# This script lists all Targets and also shows how many Notifications
# each Target has.
#
# Requires: curl, jq
#
########################################################################
MIN_TOKEN_LEN=1000
MAX_TOKEN_LEN=3000
SLEEP_TIME=5

# Pull in the ZN utlitlies library (expecteds in the same directory).
. `dirname $0`/zn_utils.bashrc

# This script cannot be run in "batch" mode.
[ ! "$TERM" ] && zn_print_fatal "You must run this script from a terminal."


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

This script lists all Targets and also shows how many Notifications each
Target has.


Usage: $MY_NAME ALL [<key_file>]

where,

  ALL             - A required parameter for safety.

  <api_key_file>  - Optionally, the file with the Customer's ZeroNorth API key.
                    If not provided, will look for the value in the environment
                    variable 'API_KEY'.


  Examples:

    $MY_NAME ALL
    $MY_NAME ALL my-key-file
" >&2
    exit 1
fi

########################################################################
# Read in the command line parameters.
########################################################################

# Read in the resource type.
[ "$1" != "ALL" ] && zn_print_fatal "Please, specify the required parameter 'ALL'."
shift

# Check key length.
key_len=$(echo -n "$API_KEY" | wc -c)
if [ ! -n $key_len ] || [ $key_len -lt $MIN_TOKEN_LEN ]; then
    zn_print_fatal "The API token seems too short at $key_len bytes."
fi
zn_print_info "The API token is $key_len bytes."


########################################################################
# Validate some more!
########################################################################
#
# Look up the customer account name.
#
cust_name=$(zn_customer_name) || zn_die
zn_print_info "The customer name is '$cust_name'."


########################################################################
# List all Targets.
########################################################################
result=$(zn_get_obj_list targets "?limit=4000") || zn_die

# Print the headings.
echo "tgtId,tgtName,notificationsCount"

# Print the data.
jq -r '.[0]|sort_by(.data.name)|.[]|.id+","+.data.name+","+(.data.notifications|length|tostring)' <<< "$result"


########################################################################
# The end.
########################################################################
zn_print_info "Done."
