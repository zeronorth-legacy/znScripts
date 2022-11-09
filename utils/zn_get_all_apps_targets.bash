#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# This script lists Applications, constinuent Targets, the remaining
# Targets that do not belong to any Applications, and optionally, the
# latest scan datetime for the Target.
#
# REQUIRES: curl, jq.
#
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
# 3) Set as the value to the variable API_KEY within this script.
#
# IMPORTANT: An API key generated using the above method has life span
# of 10 calendar years.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."

MY_NAME=`basename $0`
MY_DIR=`dirname $0`

# Pull in the ZN utlitlies library (expecteds in the same directory).
. `dirname $0`/zn_utils.bashrc


########################################################################
# Print the help info.
########################################################################
if [ ! "$1" ]
then
    echo "
This script lists Applications, constinuent Targets, the remaining
Targets that do not belong to any Applications, and optionally, the
latest scan datetime for the Target.


Usage: $MY_NAME [NO_HEADERS] ALL [LAST] [<key_file>]

  Example: $MY_NAME QIbGECkWRbKvhL40ZvsVWh
           $MY_NAME ALL key_file

where,

  NO_HEADERS  - If specified, does not print field heading. This is used
                by the amfam_get_all_wrapper.bash script, which prints
                the heading before this script is called.

  ALL         - Required parameter for safety.

  LAST        - If specified, will look up the latest successful scan date
                time for the Targets.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
" >&2
    exit 1
fi

if [ "$1" == "NO_HEADERS" ]; then
    NO_HEADERS=1
    shift
fi

APP_ID="$1"; shift
if [ "$APP_ID" != "ALL" ]
then
    zn_print_fatal "You must specify 'ALL' as the first parameter."
fi

if [ "$1" == "LAST" ]; then
    LAST=1
    shift
fi

[ "$1" ] && API_KEY=$(cat "$1")

if [ ! "$API_KEY" ]
then
    echo "No API key provided! Exiting."
    exit 1
fi


########################################################################
# Prep.
########################################################################

# Find a suitable working directory
[ "${TEMP}" ] && TEMP_DIR="${TEMP}" || TEMP_DIR="/tmp"

# Prepare the temporary work file. Not always created.used.
TEMP_FILE_APPS="${TEMP_DIR}/zn_inventory_apps.`date '+%s'`.tmp"
TEMP_FILE_TGTS="${TEMP_DIR}/zn_inventory_tgts.`date '+%s'`.tmp"
TEMP_FILE_JOIN="${TEMP_DIR}/zn_inventory_join.`date '+%s'`.tmp"


########################################################################
# F) Function to look up the last scan date for a Target.
#
# Input: Target ID
# Output: List of Policies (pol_id|pol_nm|pol_create_dt)
########################################################################
function func_get_last_scan_date {
    fn_tgt_id="$1"

    # Look up the Policies by Target ID.
    result=$(zn_get_obj_list policies "?targetId=${fn_tgt_id}&limit=100")
    fn_pids=$(jq -r '.[0][] | .id' <<< "$result")
    [ "$fn_pids" ] || return

    # Iterate through the policy IDs to find the most recent job date/time.
    fn_job_dt=""
    while read fn_pid
    do
        # Get the list of the jobs for the Policy, looks back 20 jobs (API default).
        result=$(zn_get_obj_list jobs "?policyId=${fn_pid}")

        # Extract the datetime of most recent FINISHED job.
        p_job_dt=$(jq -r '
[
  .[0][] |
   select(.data.status=="FINISHED")
] |
if (length > 0) then
  (
    sort_by(.meta.created) |
    last |
    .meta.created |
    split(".") |
    .[0] |
    sub("T";" ")
  )
else
  empty
end
' <<< "$result")

        # Conditionally set the new max.
        [[ "$p_job_dt" > "$fn_job_dt" ]] && fn_job_dt="$p_job_dt"
    done <<< "$fn_pids"

    echo "$fn_job_dt"
}


########################################################################
# Look up the customer name.
########################################################################
cust_name=$(zn_customer_name)
zn_print_info "Customer Organization = '$cust_name'"


########################################################################
# Extract the list of Applications and their Targets.
########################################################################
# Extract the Applications list.
result=$(zn_get_obj_list applications "?expand=false&limit=1000")
apps=$(jq -r '.[0][] | .id+"|"+.data.name+"|"+(.meta.created|split(".")|.[0]|sub("T";" ")|sub("Z";""))' <<< "$result")

if [ ! "$apps" ]; then
    zn_print_info "No Applications found. Exiting."
    exit
fi
zn_print_info "Found $(echo "$apps" | wc -l) Applications."

# Iterate through each Application.
while IFS="|" read app_id app_nm app_dt
do
    # Get the list of Targets for each Application.
    result=$(zn_get_obj_list "applications/${app_id}" "?expand=false")
    tgts=$(jq -r '.data.targets[] | .id+"|"+.data.name+"|"+.data.environmentType+"|"+(.meta.created|split(".")|.[0]|sub("T";" ")|sub("Z";""))+"|"+.data.environmentId' <<< "$result")

    [ ! "$tgts" ] && continue

    # Iterate through the Targets.
    echo "$tgts" | while IFS="|" read tgt_id tgt_nm tgt_type tgt_dt env_id
    do
        # Print the Apps/Targets data.
        echo "$cust_name,$app_id,$app_nm,$app_dt,$tgt_id,$tgt_nm,$tgt_type,$tgt_dt,$env_id"
    done
done <<< "$apps" | sort -t',' -k5 > $TEMP_FILE_APPS


########################################################################
# Extract the list of all Targets.
########################################################################
result=$(zn_get_obj_list targets "?limit=3000")
tgts=$(jq -r '.[0][] | .id+"|"+.data.name+"|"+.data.environmentType+"|"+(.meta.created|split(".")|.[0]|sub("T";" ")|sub("Z";""))+"|"+.data.environmentId' <<< "$result")

if [ ! "$tgts" ]; then
    zn_print_info "No Targets found. Exiting."
    exit
fi
zn_print_info "Found $(echo "$tgts" | wc -l) Targets."
zn_print_info "This could take a while..."

# Iterate through the Targets.
echo "$tgts" | while IFS="|" read tgt_id tgt_nm tgt_type tgt_dt env_id
do
    # Print the App/Target-level data.
    echo "$cust_name,,,,$tgt_id,$tgt_nm,$tgt_type,$tgt_dt,$env_id"
done | sort -t',' -k5 > $TEMP_FILE_TGTS

zn_print_debug "Individual temp files are '$TEMP_FILE_APPS' and '$TEMP_FILE_TGTS'."


########################################################################
# Join the two temporary files to produce the full list.
########################################################################

# Join and sort the two file, writing to an intermediate results file.
join -t',' -j5 -a2 $TEMP_FILE_APPS $TEMP_FILE_TGTS | cut -d',' -f1,2,3,4,5,6,7,8,9 | sort > $TEMP_FILE_JOIN

zn_print_debug "The joined temp file is '$TEMP_FILE_JOIN'."


########################################################################
# Print the column headings.
########################################################################
if [ ! "$NO_HEADERS" ]; then
    if [ ! "$LAST" ]; then
        echo "Organization,TargetID,TargetName,TargetType,AppID,AppName,IntegrationId,IntegrationName,IntegrationType,"
    else
        echo "Organization,TargetID,TargetName,TargetType,AppID,AppName,IntegrationId,IntegrationName,IntegrationType,LastScanDate(UTC)"
    fi
fi


########################################################################
# Read the intermediate results back in, looking up the Integration name
# and also conditionally looking up the lastest successful scan datetime
# and then printing the output.
########################################################################
while IFS="," read tgt_id cust_nm app_id app_nm app_dt tgt_nm tgt_type tgt_dt env_id
do
    # Look up the Integration name (not visible in Target output).
    result=$(zn_get_object_data environments $env_id)
    env_nm=$(jq -r '.name' <<< "$result")
    env_type=$(jq -r '.type' <<< "$result")

    # Optionally, look up the most recent FINISHED policy date.
    if [ "$LAST" ]; then
        # Look up the Policies.
        last_scan_dt=$(func_get_last_scan_date $tgt_id)

        while IFS="|" read pol_id pol_nm pol_dt
        do
            # Print the App/Targets/Policies data.
            echo "$cust_nm,$tgt_id,$tgt_nm,$tgt_type,$app_id,$app_nm,$env_id,$env_nm,$env_type,$last_scan_dt"
        done <<< "$pols"
    else
        # Print the App/Targets data.
        echo "$cust_nm,$tgt_id,$tgt_nm,$tgt_type,$app_id,$app_nm,$env_id,$env_nm,$env_type,"
    fi

done < $TEMP_FILE_JOIN


########################################################################
# Done.
########################################################################
[ "${TEMP_FILE_APPS}" ] && [ -w ${TEMP_FILE_APPS} ] && rm "${TEMP_FILE_APPS}" && zn_print_info "Temp file '${TEMP_FILE_APPS}' removed."
[ "${TEMP_FILE_TGTS}" ] && [ -w ${TEMP_FILE_TGTS} ] && rm "${TEMP_FILE_TGTS}" && zn_print_info "Temp file '${TEMP_FILE_TGTS}' removed."
[ "${TEMP_FILE_JOIN}" ] && [ -w ${TEMP_FILE_JOIN} ] && rm "${TEMP_FILE_JOIN}" && zn_print_info "Temp file '${TEMP_FILE_JOIN}' removed."
zn_print_info "Done."
