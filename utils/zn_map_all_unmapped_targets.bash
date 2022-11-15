#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to map all unmapped Targets to place-holder Applications of a
# specified Application name prefix. If run repeated, existing place-
# holder Applications with matching names (by prefix) will first be
# deleted. Then, all Targets not mapped to Applications will be mapped
# to the new place-holder Applications.
#
# Requires: zn_utils.bashrc
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

# Pull in the required ZN BASH Utils library. Must in the same folder.
. `dirname $0`/zn_utils.bashrc

MAX_BATCH_SIZE=200


########################################################################
# Print the help info.
########################################################################
if [ ! "$2" ]
then
    echo "
Script to map all unmapped Targets to place-holder Applications of a
specified Application name prefix. If run repeated, existing place-
holder Applications with matching names (by prefix) will first be
deleted. Then, all Targets not mapped to Applications will be mapped
to the new place-holder Applications.


Usage: $MY_NAME <LIST|ADD|DELETE|UPDATE> <place-holder app prefix> <batch size> [<key_file>]

where,

  <LIST|ADD|UPDATE|DELETE>

    The operation command:

      LIST   - list existing place-holder Applications and their Targets.
      ADD    - Add place-holder Applications.
      DELETE - Remove all place-holder Applications by prefix match.
      UPDATE - Similar to ADD, but first does DELETE, and then ADD.

  <place-holder app prefix>

    The prefix to to use for the place-holder Applications that will
    map the unmapped Targets. An unmapped Target is a Target that is
    not mapped to any of the Applications other than the place-holder
    Application. Since each Application can only map a limited number
    of Targets, if more than one place-holder Application is needed,
    they will use the specified prefix, followed by a sequnce number.
    For example, for prefix 'UNMAPPED-TARGETS', names will be like:

      UNMAPPED-TARGETS-1
      UNMAPPED-TARGETS-2
      UNMAPPED-TARGETS-3
      etc.

  <batch size>

    The number of Targets to map to each place-holder Application. The
    current upper limit in the ZeroNorth system for Application-to-
    Targets mapping is $MAX_BATCH_SIZE. Suggested batch size is 100.

  <key_file>

    Optionally, the file with the ZeroNorth API key.  If not provided,
    will use the value in the API_KEY variable, which can be supplied
    as an environment variable or be set inside the script.


Examples: $MY_NAME LIST UNMAPPED-TARGETS
          $MY_NAME LIST ALL (special previs to list ALL Appliations)
          $MY_NAME DELETE UNMAPPED-TARGETS
          $MY_NAME ADD UNMAPPED-TARGETS 100
          $MY_NAME ADD UNMAPPED-TARGETS 100 key_file
          $MY_NAME ADD UNMAPPED-TARGETS 100
" >&2
    exit 1
fi


# Read in the command.
COMMAND="$1"; shift
if [ "$COMMAND" != "LIST" ] && [ "$COMMAND" != "ADD" ] && [ "$COMMAND" != "DELETE" ] && [ "$COMMAND" != "UPDATE" ]; then
    zn_print_error "Command '$COMMAND' is not recognized."
    exit 1
fi
zn_print_info "Command is: '$COMMAND'"

if [ "$COMMAND" != "LIST" ] && [ "$COMMAND" != "DELETE" ] && [ ! "$2" ]; then
    zn_print_error "Please, specify both <place-holder app prefix> and <batch size> parameters."
    exit 1
fi

# Read in the place-holder App name prefix.
APP_PREFIX="$1"; shift
zn_print_info "Place-holder Application name prefix: '$APP_PREFIX'"

# Read in the place-holder App-to-Targets batch size.
if [ "$1" ]; then
    BATCH_SIZE="$1"; shift
    if [ $BATCH_SIZE -gt $MAX_BATCH_SIZE ]; then
        zn_print_fatal "Batch size $BATCH_SIZE in not valid. Max batch size is $MAX_BATCH_SIZE."
    else
        zn_print_info "Place-holder Application batch size: '$BATCH_SIZE'"
    fi
fi

# Read in the API key.
[ "$1" ] && API_KEY=$(cat "$1")
if [ ! "$API_KEY" ]
then
    zn_print_fatal "No API key provided! Exiting."
fi


########################################################################
# Function definitions
########################################################################

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Function to LIST existing place-holder Applications (prefix match).
# If the prefix is "ALL", then all Applications are listed.
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
function list_ph_apps {
    # Extract the full Applications list.
    result=$(zn_get_obj_list applications "?expand=false&limit=10000") \
        || zn_print_fatal "Unable to retrieve Applications list."

    pattern="$APP_PREFIX"
    [ "$pattern" == "ALL" ] && pattern='.*' # Special pattern to list all

    # Look for ones whose names match the prefix.
    ph_apps=$(jq -r '.[0][] | select(.data.name|test("^'"$pattern"'";"i")) | .id' <<< "$result")
    zn_print_debug "ph_apps='$ph_apps'"
    #echo "DEBUG: ph_apps='$ph_apps'" >&2

    if [ ! "$ph_apps" ]; then
        zn_print_info "No matching place-holder Applications found."
        return
    fi

    jq -r '
.[0][] |
select(.data.name|test("^'"$pattern"'";"i")) |
.id
+",\""+.data.name
+"\","+
(
  .data.targets[] |
  .id
  +",\""+.data.name+"\""  
)
' <<< "$result" | sort -t, -k2,2 -k4,4
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Function to DELETE existing place-holder Applications (prefix match)
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
function del_ph_apps {
    # Extract the full Applications list.
    result=$(zn_get_obj_list applications "?expand=false&limit=10000")
    if [ $? -gt 0 ]; then
        zn_print_error "Unable to retrieve Applications list."
        return 1
    fi

    # Look for ones whose names match the prefix.
    ph_apps=$(jq -r '.[0][] | select(.data.name|test("^'"$APP_PREFIX"'";"i")) | .id+"|"+.data.name' <<< "$result")
    zn_print_debug "ph_apps='$ph_apps'"

    if [ ! "$ph_apps" ]; then
        zn_print_error "No matching place-holder Applications to delete."
        return
    fi

    # !!! Iterate through the list and delete those Applications !!!
    # !!! Iterate through the list and delete those Applications !!!
    # !!! Iterate through the list and delete those Applications !!!
    while IFS="|" read ph_app_id ph_app_name
    do
        zn_print_info "Deleting existing place-holder Application '$ph_app_name' ($ph_app_id)..."
        result=$(zn_delete_obj_by_type_id applications $ph_app_id)
        if [ $? -gt 0 ]; then
            zn_print_error "Problem while deleting the Application."
            return 1
        fi
        zn_print_info "Delete successful."
    done <<< "$ph_apps"
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Function to identiy unmapped Targets.
#
# Output: the list of unmapped Target IDs
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
function get_unmapped_target_ids {

    # Extract the list of all Targets.
    result=$(zn_get_obj_list targets "?limit=10000")
    all_tgt_ids=$(jq -r '.[0][] | .id' <<< "$result" | sort -u)
    if [ ! "$all_tgt_ids" ]
    then
        zn_print_info "No Targets found."
        return
    fi
    zn_print_info "$(wc -l <<< "$all_tgt_ids") Targets in total."

    # Extract the list of Targets mapped to "real" Applications.
    # Extract the full Applications list, again.
    result=$(zn_get_obj_list applications "?expand=false&limit=10000") || \
        zn_print_fatal "Unable to retrieve Applications list."

    # Extract the list of the Targets that are already mapped to Applications
    # except for the ones that are mapped to the place-holder Appliation.
    mapped_tgt_ids=$(jq -r '.[0][] | .data.targets[].id' <<< "$result" | sort -u)
    if [ ! "$mapped_tgt_ids" ]
    then
        zn_print_info "No mapped Targets found. Proceeding."
    else
        zn_print_info "$(wc -l <<< "$mapped_tgt_ids") Targets are already mapped to Applications."
    fi

    # Diff the two list using temporary files fed into the diff program.
    echo "$all_tgt_ids"    > $TEMP_FILE_ALL
    echo "$mapped_tgt_ids" > $TEMP_FILE_MAP

    unmapped_tgt_ids=$(comm -23 $TEMP_FILE_ALL $TEMP_FILE_MAP)
    if [ ! "$unmapped_tgt_ids" ]
    then
        zn_print_info "No unmapped Targets found."
        return
    fi
    zn_print_info "$(wc -l <<< "$unmapped_tgt_ids") Targets are not yet mapped to Applications."

    echo "$unmapped_tgt_ids"
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Function to add one batch of Targets IDs to a place-holder Application
#
# Input:  Application Name
#         Target IDs list
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
function add_one_ph_app {
    app_name="$1"; shift
    tgt_ids="$1"; shift

    zn_print_info "Creating '$app_name' with $(wc -l <<< "$tgt_ids") Targets..."

    tgt_ids=$(sed 's/^/\"/; s/$/\"/' <<< "$tgt_ids") # Add quotes
    tgt_ids=$(jq -s '.' <<< "$tgt_ids")              # JSON array

    # Construct the payload.
    app_data="
{
  \"name\": \"${app_name}\",
  \"targetIds\":
    $tgt_ids,
  \"description\":\"This is a place-holder Application to track unmapped Targets.\"
}"
    zn_print_debug "app_data='$app_data'"

    # Create the new Application.
    result=$(zn_post_obj_by_type applications "$app_data")
    if [ $? -gt 0 ]; then
        zn_print_error "Problem. Please investigate and try again."
        return 1
    fi
    zn_print_info "Place-holder Application '$app_name' created."
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Function to ADD new place-holder Applications (done in batches)
#
# Output: the number of place-holder Applications created
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
function add_ph_apps {
    # Get the list of the unmapped Targets.
    unmapped_tgt_ids=$(get_unmapped_target_ids) || return 1
    if [ ! "$unmapped_tgt_ids" ]; then
        zn_print_info "Nothing to do."
        return
    fi

    # Each Application can only hold a limited number of Targets. Therefore,
    # we may need to create multiple place-holder Applications.
    tgts_batch=''
    tgts_count=0
    app_number=1
    while read tgt_id
    do
        if [ "$tgts_batch" ]; then
            tgts_batch="$tgts_batch
$tgt_id"
        else
            tgts_batch="$tgt_id"
        fi
        (( tgts_count = tgts_count + 1 ))
        
        if [ $tgts_count -ge $BATCH_SIZE ]; then
            add_one_ph_app "${APP_PREFIX}_${app_number}" "$tgts_batch"

            tgts_batch=''
            tgts_count=0
            (( app_number = app_number + 1 ))
        fi
    done <<< "$unmapped_tgt_ids"

    # The final batch of Targets
    [ "$tgts_batch" ] && add_one_ph_app "${APP_PREFIX}_${app_number}" "$tgts_batch"
}


########################################################################
# "MAIN"
########################################################################

# Find a suitable working directory
[ "${TEMP}" ] && TEMP_DIR="${TEMP}" || TEMP_DIR="/tmp"

# Prepare the temporary work file. Not always created/used.
TEMP_FILE_MAP="${TEMP_DIR}/zn_tgts_map.`date '+%s'`.tmp"
TEMP_FILE_ALL="${TEMP_DIR}/zn_tgts_all.`date '+%s'`.tmp"

# Look up the customer name. Also a good way to validate the API key.
cust_name=$(zn_customer_name) || zn_print_fatal "Error looking up customer name."
zn_print_info "Customer name is '$cust_name'."

# Process the COMMAND.
if   [ "$COMMAND" == "LIST" ]; then
    ph_apps=$(list_ph_apps)
    if [ "$ph_apps" ]; then
        echo "App ID,App Name,Target ID,Target Name"
        echo "$ph_apps"
    fi
elif [ "$COMMAND" == "ADD" ]; then
    add_ph_apps
elif [ "$COMMAND" == "DELETE" ]; then
    del_ph_apps
elif [ "$COMMAND" == "UPDATE" ]; then
    del_ph_apps || zn_print_fatal "Exiting."
    add_ph_apps
else
    zn_print_error "Command '$COMMAND' is not supported."
fi


########################################################################
# Done.
########################################################################
[ "${TEMP_FILE_ALL}" ] && [ -w ${TEMP_FILE_ALL} ] && rm "${TEMP_FILE_ALL}" && zn_print_info "Temp file '${TEMP_FILE_ALL}' removed."
[ "${TEMP_FILE_MAP}" ] && [ -w ${TEMP_FILE_MAP} ] && rm "${TEMP_FILE_MAP}" && zn_print_info "Temp file '${TEMP_FILE_MAP}' removed."

zn_print_info "Done."
