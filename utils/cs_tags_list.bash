########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#
# A script to show the NEW tags for the specified object or object type.
# For example, you can use this script to list tags for an Appication,
# for all Applications, for a Targets, or for all Targets, etc.
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
if [ ! "$2" ]; then
    echo "
************************************************************************
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
************************************************************************

A script to show the NEW tags for the specified object or object type.
For example, you can use this script to list tags for an Appication,
for all Applications, for a Targets, or for all Targets, etc.


Usage: $MY_NAME <resource_type> <resource_name> [<key_file>]

where,

  <resource_type> - Valid values are things like \"application\",
                    \"target\", etc. As of 2021-09, only these two resource
                    types are supported.

  <resource_name> - The name of the resource. In other words, the name of the
                    Application or the Target to list tags for. Specify \"ALL\"
                    to list all items of the specified resource type.

  <api_key_file>  - Optionally, the file with the Customer's ZeroNorth API key.
                    If not provided, will look for the value in the environment
                    variable 'API_KEY'.


  Examples:

    $MY_NAME application ALL
    $MY_NAME application NodeGoat
    $MY_NAME application NodeGoat my-key-file
    $MY_NAME target ALL
    $MY_NAME target ALL my-key-file
" >&2
    exit 1
fi

########################################################################
# Read in the command line parameters.
########################################################################

# Read in the resource type.
R_TYPE="$1"; shift
zn_print_info "Resource type: '$R_TYPE'"

# Read in the resource name.
R_NAME="$1"; shift
zn_print_info "Resource name: '$R_NAME'"
[ "$R_NAME" == "ALL" ] && zn_print_info "All ${R_TYPE}s will be listed."

# The customer API key.
[ "$1" ] && API_KEY=$(cat "$1")
[ ! "$API_KEY" ] && zn_print_fatal "Customer API key not provided!"

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
zn_print_info "Customer name '$cust_name' validated."


########################################################################
# List the requested resource(s).
########################################################################
if [ "$R_NAME" == "ALL" ]; then
    result=$(zn_get_obj_list ${R_TYPE}s "?limit=10000") || zn_die
    r_list=$(jq -r '.[0][]|.id+"|"+.data.name' <<< "$result")
else
    result=$(zn_get_by_name ${R_TYPE}s "$R_NAME") || zn_die
    result=$(zn_get_object ${R_TYPE}s "$result") || zn_die
    r_list=$(jq -r '.id+"|"+.data.name' <<< "$result")
fi

r_count=$(sed '/^$/d' <<< "$r_list" | wc -l)
if [ $r_count -gt 1 ]; then
    zn_print_info "Found $r_count matching ${R_TYPE}s."
else
    zn_print_info "Found $r_count matching ${R_TYPE}."
fi


########################################################################
# For each resource, look up the tags data.
########################################################################
while IFS='|' read r_id r_name
do
    zn_print_debug "Looking up tags info for $r_id '$r_name'..."
    result=$(zn_get_obj_list tags "/${R_TYPE}/${r_id}") || zn_die
    t_list=$(jq -r '.[0][]|.id+"|"+.data.name+"|"+.data.value' <<< "$result")
    while IFS='|' read t_id t_name t_value
    do
        echo "$r_id|$r_name|$t_id|$t_name|$t_value"
    done <<< "$t_list"
done <<< "$r_list"


########################################################################
# The end.
########################################################################
zn_print_info "Done."
