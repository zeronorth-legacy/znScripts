#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to show, add, or update Jira integration to an existing Target.
# The Target can be specified by either the ID or the Name. If using the
# name, it must be unique or an error will result. Target name matching
# will be case insensitive.
#
# Requires: zn_utils.bashrc
#
########################################################################
# Before using this script, obtain your API key using the instructions
# outlined in the following KB article:
#
#   https://support.zeronorth.io/hc/en-us/articles/115003679033
#
# Save the API key as the sole content into a secured file, which will
# be refereed to as the "key file" when using this script.
#
# IMPORTANT: An API key generated using the above method has life span
# of 10 calendar years.
########################################################################
# Pull in the required ZN BASH Utils library. Must in the same folder.
. `dirname $0`/zn_utils.bashrc


########################################################################
# Read the inputs from the positional parameters
########################################################################
if [ ! "$2" ] || ( [ "$2" != "SHOW" ] && [ "$2" != "DELETE" ] && [ ! "$7" ] )
then
    echo "
Script to show, add, or update Jira integration to an existing Target.
The Target can be specified by either the ID or the Name. If using the
name, it must be unique or an error will result. Target name matching
will be case insensitive.


Usage: $MY_NAME <tgt_name/ID> <MODE> <jira_threshold> <jira_domain> <jira_project> <jira_user> <jira_key> [<key_file>]

where,

  <tgt_name/ID>    - The name or the ID of Target. If a name is specified,
                     a case-insensitive lookup will be done. If more than
                     one match if found, or if no match if found, an error
                     will result and this script will exit.

  <MODE>           - Must be one of:

                     ADD    - Add a new Jira integration
                     SHOW   - Show Jira integration (sans the creds)
                     UPDATE - Updating Jira integration
                     DELETE - Delete Jira integration. The associated Jira
                              secret is also deleted. This can present a
                              problem if (by small chance) the Jira secret
                              is being shared with other Targets.

  <jira_threshold> - Jira ticket creation threshold. Must be one of:

                     CRITICAL
                     HIGH
                     MEDIUM
                     LOW

  <jira_domain>    - The URL/domain to your Jira tenant, e.g. my.atlassian.net

                     See the ZeroNorth knowledge base for more information:
                     https://support.zeronorth.io/hc/en-us/articles/360000429414

  <jira_project>   - The Jira project code or the project ID. The use of Jira
                     project code is only supported for Jira SaaS.

  <jira_user>      - The Jira user name. This is typically in the form of an
                     email address.

  <jira_key>       - The Jira API key associated with <jira_user>.

  <key_file>       - Optionally, the file with the ZeroNorth API key. If not
                     provided, will use the value in the API_KEY variable
                     which can be supplied as an environment variable or be
                     set inside the script.


  Examples: $MY_NAME MyTarget SHOW
            $MY_NAME MyTarget DELETE
            $MY_NAME MyTarget ADD HIGH my.atlassian.net MYPROJ me@my.com 30cTajDdZEZnCvjCeTbN0045
            $MY_NAME MyTarget UPDATE MEDIUM my.atlassian.net MYPROJ2 me@my.com 30cTajDdZEZnCvjCeTbN0045
            $MY_NAME WZ7GzckvTNWRI9C9f7mEgg MyNewTarget key_file
" >&2
    exit 1
fi

# Get the input Target name/ID.
TARGET="$1"; shift
zn_print_info "Target specified is: '${TARGET}'."

# Get the mode/command.
MODE="$1"; shift
if [ "$MODE" != "ADD" ] && [ "$MODE" != "SHOW" ] && [ "$MODE" != "UPDATE" ] && [ "$MODE" != "DELETE" ]; then
    zn_print_error "'$MODE' is not a valid mode. It must be one of 'ADD', 'SHOW', 'UPDATE', or 'DELETE'. Exiting."
    exit 1
fi
zn_print_info "MODE is: '${MODE}'."

#
# For any mode other than "SHOW" or "DELETE", we need more params.
#

if ( [ "$MODE" != "SHOW" ] && [ "$MODE" != "DELETE" ] ); then
    # Get the threshold.
    JIRA_THRESHOLD="$1"; shift
    if [ "$JIRA_THRESHOLD" != "CRITICAL" ] && [ "$JIRA_THRESHOLD" != "HIGH" ] && [ "$JIRA_THRESHOLD" != "MEDIUM" ] && [ "$JIRA_THRESHOLD" != "LOW" ]; then
        zn_print_error "'$JIRA_THRESHOLD' is not a valid value for Jira ticketing Threshold. It must be one of 'CRITICAL', 'HIGH', 'MEDIUM', or 'LOW'. Exiting."
        exit 1
    fi
    zn_print_info "Jira threshold is: '${JIRA_THRESHOLD}'."

    # Get the URL/domain.
    JIRA_DOMAIN="$1"; shift
    zn_print_info "Jira URL/domain is: '${JIRA_DOMAIN}'."

    # Get the project.
    JIRA_PROJECT="$1"; shift
    zn_print_info "Jira project is: '${JIRA_PROJECT}'."

    # Get the Jira user.
    JIRA_USER="$1"; shift
    zn_print_info "Jira user is: '${JIRA_USER}'."

    # Get the Jira API key.
    JIRA_KEY="$1"; shift
    zn_print_info "Jira API key is: `echo -n $JIRA_KEY | wc -c` bytes in length."
fi

# Read in the API key.
[ "$1" ] && API_KEY=$(cat "$1")
if [ ! "$API_KEY" ]
then
    echo "No API key provided! Exiting."
    exit 1
fi


########################################################################
#
#                        FUNCTION DEFINITIONS
#
########################################################################

#-----------------------------------------------------------------------
# Function to get existing Jira secret key.
#
# INPUT:  Target data
# OUTPUT: Jira secret key, if any.
#-----------------------------------------------------------------------
function func_get_jira_secret_key {
    tgt_data="$1"

    # Extract the Jira Notification item's secret key.
    secret_key=$(jq -r '.notifications[] | select(.type=="jira") | .options.notify[0].secret' <<< "$tgt_data")

    # In case there isn't one...
    if [ ! "$secret_key" ]; then
        zn_print_info "Specified Target has no Jira integration."
        return
    fi

    echo "$secret_key"
}

#-----------------------------------------------------------------------
# Function to get existing Jira secret.
#
# INPUT:  Target data
# OUTPUT: Jira integration details, including the secret, sans the creds
#-----------------------------------------------------------------------
function func_get_jira_secret {
    tgt_data="$1"

    # Extract the Jira secret key so that we can look it up.
    secret_key=$(func_get_jira_secret_key "$tgt_data")

    # In case there isn't one...
    [ ! "$secret_key" ] && return

    # Looks up the Secret details.
    result=$(zn_get_object secrets $(zn_url_encode "$secret_key")) || return

    # The result will have the Jira API key redacted.
    jq '.data.secret | .password="<redacted>"' <<< "$result"
}


#-----------------------------------------------------------------------
# Function to construct the Target data JSON for the Jira Notification.
#
# INPUT:  Target data, Jira Secret key
# OUTPUT: The modified Target data JSON
#-----------------------------------------------------------------------
function func_make_target_payload {
    tgt_data="$1"
    jira_secret_key="$2"

    # Construct the new "jira" notification element.
    jira_item="{\"type\": \"jira\", \"options\": {\"notify\": [ { \"secret\": \"$jira_secret_key\" } ] } }"

    # Get the notifications array, removing any "jira" type to star with.
    notifications=$(jq '[.notifications[]|select(.type!="jira")]' <<< "$tgt_data")

    # Construct the new array, or add the new notification item into th array.
    # Lack of a new secret key effectively removes existing Jira integration.
    if [ "$jira_secret_key" ]; then
        if [ ! "$notifications" ] || [ "$notifications" == "[]" ]; then
            notifications="[${jira_item}]"
        else
            notifications=$(jq '.=[.[],'"$jira_item"']' <<< "$notifications")
        fi

        # Set the new threshold.
        if   [ "$JIRA_THRESHOLD" == "CRITICAL" ]; then
            threshold=9
        elif [ "$JIRA_THRESHOLD" == "HIGH" ]; then
            threshold=7
        elif [ "$JIRA_THRESHOLD" == "MEDIUM" ]; then
            threshold=4
        elif [ "$JIRA_THRESHOLD" == "LOW" ]; then
            threshold=1
        elif [ "$JIRA_THRESHOLD" == "INFO" ]; then
            threshold=0
        fi    

        # Edit in the new threshold into the Target payload.
        tgt_data=$(jq '.notificationsThreshold='$threshold <<< "$tgt_data")
    fi

    # Edit in the new notifications array into the Target payload.
    tgt_data=$(jq '.notifications='"$notifications" <<< "$tgt_data")

    echo "$tgt_data"
}


#-----------------------------------------------------------------------
# Function to construct a Jira secret.
#
# INPUT:  Jira URL/domain, Jira project, Jira user, Jira API key
# OUTPUT: The JSON payload for a Jira Secret.
#-----------------------------------------------------------------------
function func_make_jira_secret {
    jira_domain="$1"
    jira_project="$2"
    jira_user="$3"
    jira_key="$4"

    jira_secret="
{
  \"type\": \"jira\",
  \"description\": \"jira secret from notifications\",
  \"secret\": {
    \"domain\": \"$jira_domain\",
    \"projectId\": \"$jira_project\",
    \"username\": \"$jira_user\",
    \"password\": \"$jira_key\"
  }
}
"
    echo "$jira_secret"
}


#-----------------------------------------------------------------------
# Function to add a Jira secret.
#
# INPUT:  Jira URL/domain, Jira project, Jira user, Jira API key
# OUTPUT: The Secret key for the resulting Secret. Don't lose it!!!
#         Error causes this function to exit the script with status 1.
#-----------------------------------------------------------------------
function func_add_jira_secret {

    jira_secret=$(func_make_jira_secret $*)

    # Create the new Jira Secret.
    result=$(zn_post_obj_by_type secrets "$jira_secret") || exit 1

    # Get the result and check for error.
    key=$(jq -r '.key' <<< "$result")
    if [ ! "$key" ] || [ "$key" == "null" ]; then
        zn_print_error "Failed creating a new Jira Secret."
        exit 1
    fi

    zn_print_info "New Jira secret created with key: $key"
    echo "$key"
}


#-----------------------------------------------------------------------
# Function to delete a Jira secret.
#
# INPUT:  Jira Secret key
# OUTPUT: none.
#-----------------------------------------------------------------------
function func_del_jira_secret {
    jira_secret_key="$1"

    zn_print_info "Deleting Jira secret with key '$jira_secret_key'..."
    jira_secret_key=$(zn_url_encode "$1")

    # Delete the Jira Secret.
    result=$(zn_delete_obj_by_type_id secrets "$jira_secret_key")

    # Check for error.
    if [ $? -gt 0 ]; then
        zn_print_warn "Delete of old Jira Secret failed. Proceeding."
    else
        zn_print_info "Previous Jira secret deleted."
    fi
}


########################################################################
# "MAIN" - process the user request by calling various function.
########################################################################
#
# Target look up.
#
tgt_data=''

# Maybe we have a Target ID?
tlen=$(echo -n "$TARGET" | wc -c)
[ $tlen -eq 22 ] && tgt_data=$(zn_get_object_data targets "$TARGET")

# See if the ID lookup worked.
if [ "$tgt_data" ]; then
    tgt_id="$TARGET"

# No, so try by name.
else
    tgt_id=$(zn_get_by_name targets "$TARGET")

    # Still didn't find it.
    if [ ! "$tgt_id" ]; then
        zn_print_fatal "Target '$TARGET' not found. Exiting."
    fi

    # Finally, try my 2nd attempt to look up the Target details.
    tgt_data=$(zn_get_object_data targets "$tgt_id")
fi

#
# Process the input command.
#

# SHOW - Display the existing Jira integration secret, redacted.
if   [ "$MODE" == "SHOW" ]; then
    func_get_jira_secret "$tgt_data"
    exit

# ADD - Create new Jira secret, and then update the Target with it.
elif [ "$MODE" == "ADD" ]; then
    jira_secret_key=$(func_add_jira_secret "$JIRA_DOMAIN" "$JIRA_PROJECT" "$JIRA_USER" "$JIRA_KEY")
    tgt_data=$(func_make_target_payload "$tgt_data" "$jira_secret_key")

# DELETE - Delete the existing Jira secret, and then update the Target.
elif [ "$MODE" == "DELETE" ]; then
    jira_secret_key=$(func_get_jira_secret_key "$tgt_data")
    if [ "$jira_secret_key" ]; then
        func_del_jira_secret "$jira_secret_key"
        tgt_data=$(func_make_target_payload "$tgt_data" "")
    else
        exit
    fi

# UPDATE - Delete the existing Jira secret, create a new one, update the Target.
elif [ "$MODE" == "UPDATE" ]; then
    jira_secret_key=$(func_get_jira_secret_key "$tgt_data")
    [ "$jira_secret_key" ] && func_del_jira_secret "$jira_secret_key"

    jira_secret_key=$(func_add_jira_secret "$JIRA_DOMAIN" "$JIRA_PROJECT" "$JIRA_USER" "$JIRA_KEY")
    tgt_data=$(func_make_target_payload "$tgt_data" "$jira_secret_key")

# I don't understand the command.
else
    zn_print_error "Command '$MODE' is not supported."
    exit 1
fi

#
# Final touches to deal with old, bad data that we sometimes see.
#
tgt_data=$(jq '(if (.includeRegex == null) then (.includeRegex = []) else . end) | (if (.excludeRegex == null) then (.excludeRegex = []) else . end) | (if (.notifications == {} or .notifications == null) then (.notifications = []) else . end)' <<< "$tgt_data")

#
# The final step is to update the Target with the new details.
#
zn_print_info "Updating Target '$TARGET'..."
result=$(zn_put_obj_by_type_id targets "$tgt_id" "$tgt_data") || exit 1
zn_print_info "Jira '$MODE' operation to Target '$TARGET' successful."

# Show the result.
func_get_jira_secret "$tgt_data"


########################################################################
# The End
########################################################################
zn_print_info "Done."
