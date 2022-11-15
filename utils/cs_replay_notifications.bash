########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#
# A script to "replay" or retroactively process Notifications for an
# existing Target after adding a Notification. See the ZeroNorth Field
# team's Confluence article on this topic for background/details:
#
#   https://zeronorth.atlassian.net/wiki/spaces/FIELD/pages/611418268
#
# Requires: curl, jq, sed, tr

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
if [ ! "$4" ]; then
    echo "
************************************************************************
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
*      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!      *
************************************************************************

use this script to retroactively trigger Notifications for an existing
Target. You can use this script against a Target ONLY ONCE.

When to use this script - After adding a Notification for an existing
Target and you want to trigger retroactively process notifications for
existing Issues.

Limitations - this script will NOT work for the following situations:

- After adding a second Notification to a Target that already had a
  Notification, beucase the existing Issues were already Notification-
  processed.

- After using this script to process Notification for a Target,
  running it again won't do anything, because the existing Issues were
  already Notification- processed.


See the ZeroNorth Field team's Confluence article on this topic for more:

  https://zeronorth.atlassian.net/wiki/spaces/FIELD/pages/611418268


REQUIREMENTS: This script can only be used by an authorized/privileged
              ZeroNorth person who has access to the \"backoffice\".

              This script requires the following command-line parameters
              plus the ZN user's \"backoffice\" API token to be entered
              from the terminal prompt interactively. To obtain the back
              office API key, refer to the above Confluence article.


Usage: $MY_NAME [NOEXEC] <cust ID> <cust name> <target ID> <target name> [<cust_key_file>]

where,

  NOEXEC          - If specified, will just do a dry-run and won't trigger any
                    real Notifications.

  <cust ID>       - The Customer ID.

  <cust name>     - The Customer's account/tenant name (for safety check).

  <target ID>     - The Target ID whose Jobs to replay Notifications for.

  <target name>   - The name of the Target (for safety check).

  <cust_key_file> - Optionally, the file with the Customer's ZeroNorth API key.
                    If not provided, will look for the value in the environment
                    variable 'API_KEY'.


  Examples:

    $MY_NAME WEXRx42_Rk-Mi70HKyoPva Acme-Inc JYXejrMvWzqPj8UIfzcH_i my-app-project
    $MY_NAME WEXRx42_Rk-Mi70HKyoPva Acme-Inc JYXejrMvWzqPj8UIfzcH_i my-app-project my-key-file


What happens - Upon collecting all of the required information:

              1) Look up the Customer account and validate that the cust
                 ID and the Customer name match (a case-senstive match).

              2) Look up the Target ID to match against the Target name
                 (again, a case-sensitive match).

              3) Retrive job records for all Synthetic Issues.

              4) For each job:
                 a) Wait $SLEEP_TIME seconds.
                 b) Trigger Notification processing.
                 c) Repeat.
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

# Read in the target ID.
TGT_ID="$1"; shift
zn_print_info "Target ID: '$TGT_ID'"

# Read in the target name.
TGT_NAME="$1"; shift
zn_print_info "Target Name: '$TGT_NAME'"

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

#
# Look up the Target information.
#
tgt_data=$(zn_get_object_data targets "$TGT_ID") || zn_die

# Verify it.
tgt_name=$(jq -r '.name' <<< "$tgt_data")
[ "$tgt_name" != "$TGT_NAME" ] && zn_print_fatal "Target name '$tgt_name' does not match the specified Target name."
zn_print_info "Target name '$tgt_name' validated."


########################################################################
# Find the jobs for the Target.
########################################################################
# Get the jobs. We do this by looking through the Synthetic Issues and
# then looking for the issueJobs behind them, because they are the only
# jobs that contributed to Detection/Remediation of Synthetic Issues.
# Max issues = 1000.
result=$(zn_get_obj_list syntheticIssues "?targetId=${TGT_ID}&limit=1000") || zn_die
job_ids=$(echo "$result" | jq -r '.[0][].data|select(.status!="Remediation" and .ignore==false)|.issueJobs[]|(.runTime|todate)+","+.jobId' | sort -u)

# Any qualifying jobs?
if [ ! "$job_ids" ]; then
    zn_print_info "The specified Target has no qualifying jobs. Nothing to do. Exiting."
    exit
fi

job_count=$(wc -l <<< "$job_ids")
zn_print_info "Found $job_count qualifying job(s)."
zn_print_debug "Job dates and IDs:\n$job_ids"


########################################################################
# Read in the ZN "backoffice" API tokens via the terminal input (ONLY!)
########################################################################
#
# Prompt for the ZeroNorth backoffice API token.
#
read -s -p "Enter your backoffice API Token: " ZNBO_API_KEY
[ $ZNBO_API_KEY ] || zn_print_fatal "You did not supply a Backoffice API token."

# Check key length.
key_len=$(echo -n "$ZNBO_API_KEY" | wc -c)
if   [ $key_len -lt $MIN_TOKEN_LEN ]; then
    zn_print_fatal "The API token seems too short at $key_len bytes."
elif [ $key_len -gt $MAX_TOKEN_LEN ]; then
    zn_print_fatal "The API token seems too long at $key_len bytes."
fi
zn_print_info "Your backoffice API token is $key_len bytes."


########################################################################
# "MAIN" - this is where we do it!
#
#                            !!! DANGER !!!
#                            !!! DANGER !!!
#                            !!! DANGER !!!
#
# This section uses the "backoffice" API which requires special access.
# DO NOT modify the code below unless you know what you are doing!!!
########################################################################

# Set the API key to the ZeroNorth backoffice API key.
API_KEY=$ZNBO_API_KEY   # <--- !!!

zn_print_info "Starting notifications processing. Press Ctrl-c to abort at any time."

# Iterate through the found jobs.
while IFS="," read job_date job_id
do
    # Pause before each jobs for Switchboard some time to process, and
    # to give the user an opportunity to abort.
    zn_print_info "Wait $SLEEP_TIME seconds..."
    sleep $SLEEP_TIME

    zn_print_info "Processing job ID '$job_id' from $job_date..."

    #############################################################
    # The actual API call to the backoffice isn't that special: #
    #                                                           #
    # curl -X POST --header 'Content-Type: application/json'    #
    #   --header 'Accept: application/json'                     #
    #   --header 'Authorization: <backoffice_api_key>'          #
    #   -d '{"jobId":"<job_id>","customerId":"<cust_id>"}'      #
    #   'https://api.zeronorth.io/v1/jobs/replay-notifications' #
    #############################################################

    # Construct the payload.
    data="{\"customerId\":\"$CUST_ID\", \"jobId\":\"$job_id\"}"
    zn_print_debug "Payload: '$data'"

    # So, here we go...
    if [ $NOEXEC -ne 1 ]; then
        zn_api_post "jobs/replay-notifications" "$data"
        if [ $? -gt 0 ]; then
            zn_print_warn "Problem processing job ID '$job_id'. Continuing anyway..."
        else
            zn_print_info "Success processing job ID '$job_id'."
        fi
    fi

done <<< "$job_ids"


########################################################################
# The end.
########################################################################
zn_print_info "Done."
