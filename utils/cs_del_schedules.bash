########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#
# A script to delete all schedules for one or all Policies within the
# customer account specified by the API Token.
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
if [ ! "$3" ]; then
    echo "
************************************************************************
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
************************************************************************

Use this script to delete scheduule for one or all Policies within the 
customer account specified by the API Token


Usage: $MY_NAME [NOEXEC] <cust ID> <cust name> DELET_ALL_POLICIES_SCHEDULES [<api_key_file>]

where,

  NOEXEC          - If specified, will just do a dry-run and won't trigger any
                    real Notifications.

  <cust ID>       - The Customer ID.

  <cust name>     - The Customer's account/tenant name (for safety check).

  DELET_ALL_POLICIES_SCHEDULES - Required keyword for safety.

  <api_key_file>  - Optionally, the file with the Customer's ZeroNorth API key.
                    If not provided, will look for the value in the environment
                    variable 'API_KEY'.


  Examples:

    $MY_NAME WEXRx42_Rk-Mi70HKyoPva Acme-Inc 
    $MY_NAME WEXRx42_Rk-Mi70HKyoPva Acme-Inc DELET_ALL_POLICIES_SCHEDULES my-key-file


What happens - Upon collecting all of the required information:

              1) Look up the Customer account and validate that the cust
                 ID and the Customer name match (a case-senstive match).

              3) Inventory the Policies that have schedule(s), and the schedules.

              4) Prompt the user for confirmation.

              5) Delete all schedules for all Policies.
" >&2
    exit 1
fi

########################################################################
# Read in the command line parameters.
########################################################################

# Dry run?
NOEXEC=0
if [ "$1" == "NOEXEC" ]; then
    NOEXEC=1; shift
    zn_print_info "Running in noexec/dry-run mode. No actions will be taken."
fi

# Read in the customer ID.
CUST_ID="$1"; shift
zn_print_info "Customer ID: '$CUST_ID'"

# Read in the customer name.
CUST_NAME="$1"; shift
zn_print_info "Customer Name: '$CUST_NAME'"

# Read in the Policy ID.
POL_ID="$1"; shift
if [ "$POL_ID" != "DELET_ALL_POLICIES_SCHEDULES" ]; then
    zn_print_fatal "Must specify the required string constant parameter 'DELET_ALL_POLICIES_SCHEDULES'!"
fi

# The customer API key.
[ "$1" ] && API_KEY=$(cat "$1")
[ ! "$API_KEY" ] && zn_print_fatal "Customer API key not provided!"

# Check key length.
key_len=$(echo -n "$API_KEY" | wc -c)
if [ ! -n $key_len ] || [ $key_len -lt $MIN_TOKEN_LEN ]; then
    zn_print_fatal "The customer API token seems too short at $key_len bytes."
fi
zn_print_info "Customer API token is $key_len bytes."


########################################################################
# Validate some more!
########################################################################
#
# Look up the customer account name.
#
cust_name=$(zn_customer_name) || zn_die

# Verify it.
[ "$cust_name" != "$CUST_NAME" ] && zn_print_fatal "Customer name '$cust_name' does not match the specified customer name."
zn_print_info "Customer name '$cust_name' validated."


########################################################################
# Inventory the qualifying Policies and their schedules.
########################################################################
result=$(zn_get_obj_list policies "?limit=10000") || zn_die
pol_list=$(jq -r '.[0][]|.id+"|"+.data.name' <<< "$result")


pol_count=$(sed '/^$/d' <<< "$pol_list" | wc -l)
zn_print_info "There are $pol_count policies in total."


########################################################################
# For each Policy ID, look up the schedule, if any.
########################################################################
pol_sched_list=$(while IFS='|' read pol_id pol_name
                 do
                     zn_print_info "Looking up schedule info for $pol_id '$pol_name'..."
                     result=$(zn_get_obj_list policies "/${pol_id}/schedules") || zn_die
                     sched_list=$(jq -r '.[0][].id' <<< "$result")
                     while read sched_id
                     do
                         if [ $sched_id ]; then
                             zn_print_info "Found schedule with ID $sched_id."
                             echo "$pol_id|$pol_name|$sched_id"
                         fi
                     done <<< "$sched_list"
                 done <<< "$pol_list")


########################################################################
# Do a tally of the Policies and Schedules.
########################################################################
p_count=0; s_count=0
p_count=$(sed '/^$/d' <<< "$pol_sched_list" | cut -d '|' -f1 | sort -u | wc -l)
s_count=$(sed '/^$/d' <<< "$pol_sched_list" | cut -d '|' -f3 | sort -u | wc -l)

if [ ! $s_count ] || [ $s_count -eq 0 ]; then
    zn_print_info "No schedules to delete. Done."
    exit
fi
zn_print_info "Found $s_count schedules across $p_count Policies."


########################################################################
# Prompt the user for final confirmation.
########################################################################
while :
do
    read -p "Enter the number of schedules shown above to proceed with deleting the schedules, or press CTRL-C to abort: " USER_S_COUNT
    [ $USER_S_COUNT -eq $s_count ] && break
    zn_print_error "You did not enter the correct value."
done


########################################################################
# "MAIN" - this is where we do it!
#
#                            !!! DANGER !!!
#                            !!! DANGER !!!
#                            !!! DANGER !!!
#
# The schedule deletes are final and irreversible.
########################################################################

zn_print_info "Starting schedule deletes. Press CTRL-C to abort at any time."

# Iterate through the schedules.
while IFS="|" read pol_id pol_name sched_id
do
    zn_print_info "Deleting schedule $sched_id for Policy '$pol_name'..."

    # Here we go...
    if [ $NOEXEC -ne 1 ]; then
        zn_delete_obj_by_type_id "policies" "${pol_id}/schedules/${sched_id}"
        if [ $? -gt 0 ]; then
            zn_print_warn "Problem deleting schedule. Continuing anyway..."
        else
            zn_print_info "Success deleting schedule."
        fi
    fi
done <<< "$pol_sched_list"


########################################################################
# The end.
########################################################################
zn_print_info "Done."
