#!/bin/bash
########################################################################
# (c) Copyright 2022, Harness, Inc., support@harness.io
#
# Script to extract a Qualys VM scan XML report suitable for uploading
# to the ZeroNorth platform. The resulting report should be of the type
# "ASSET_DATA_REPORT", which is one of the types that ZeroNorth takes.
#
# IMPORTANT: Qualys API credentials must be made available via these ENV
# variables:
#
#   QUAL_USER - the Qualys user name
#   QUAL_PASSWORD - the Qualys password
#
# For example, the caller must:
#
#   export QUAL_USER='joe@my.com'
#   export QUAL_PASSWORD='passwd1234'
#
# Requires: curl, sed
#           xq (https://github.com/kislyuk/yq), which requires python3
########################################################################
MY_NAME=`basename $0`


########################################################################
# Basic Constants
########################################################################
SLEEP_SECS=3
MAX_ERRORS=5
MAX_WAIT_MINS=15
(( MAX_CHK_COUNT = MAX_WAIT_MINS * 60 / SLEEP_SECS ))


########################################################################
# Basic functions
########################################################################

#----------------------------------------------------------------------
# Functions to print time-stamped messages
#----------------------------------------------------------------------
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME:${BASH_LINENO[0]}  $1" >&2
}


#----------------------------------------------------------------------
# Function to URL-encode the specified string.
#----------------------------------------------------------------------
function url_encode {
    sed 's/:/%3A/g; s/\//%2f/g; s/ /%20/g' <<< "$1"
}


#----------------------------------------------------------------------
# Function to exit the script with exit status 1 (error).
#----------------------------------------------------------------------
function func_die {
    print_msg "Exiting due to an error."
    exit 1
}


########################################################################
# Read and validate input params.
########################################################################
if [ ! "$4" ]
then
    echo "
Script to extract a Qualys VM scan XML report suitable for uploading
to the ZeroNorth platform. The resulting report should be of the type
'ASSET_DATA_REPORT', which is one of the types that ZeroNorth takes.

IMPORTANT: Qualys API credentials must be made available via ENV variables:

  QUAL_USER - the Qualys user name
  QUAL_PASSWORD - the Qualys password

  For example, the caller must:

  export QUAL_USER='joe@my.com'
  export QUAL_PASSWORD='passwd1234'


Requires: curl, sed
          xq (https://github.com/kislyuk/yq), which requires python3


Usage: $MY_NAME <Qualys API URL root> <scan_title> <tag,tag,...> <report_template> [<lookback_days>]

where,

  <Qualys API URL root> E.g. 'https://qualysapi.qg3.apps.qualys.com'

                     Note that your Qualys service may be hosted by a different
                     Qualys server instance than the above example. Follow the
                     steps at https://www.qualys.com/platform-identification/
                     to find out which instance you are on.

  <scan_title>       The Qualys scan name. It's called the scan title.

  <tag,tag,...>      The Qualys asset tag(s) to include in the the report. Only
                     the assets with the matching tag will be included in the
                     report.

                     NOTE: The caller must ensure that the scan_title specified
                     and the tags specified correspond to each other. Scan
                     titles are associated with scan schedules and scans, while
                     tags are associated with scan schedules and reports.

  <report_template>  The Qualys report template name.

  <lookback_days>    Optional. If specified, will check for the existence of a
                     'Finished' scan in the lookback_days.

                     This script will not verify that any scans found are the
                     ones that you will want to include in the report.


Examples:

  $MY_NAME https://qualysapi.qg3.apps.qualys.com my_qual_scan tag1 my_qual_vm_report_template
  $MY_NAME https://qualysapi.qg3.apps.qualys.com my_qual_scan 'tag1,tag2' my_qual_vm_report_template 1
" >&2
   exit 1
fi

# Get the API URL base.
QUAL_URL_BASE="$1"; shift
# Trim the trailing '/' if it's there.
QUAL_URL_BASE=$(sed 's/\/$//' <<< "$QUAL_URL_BASE")
print_msg "Qualys server URL root: '$QUAL_URL_BASE'"

# Get the Qualys user name.
if [ ! "$QUAL_USER" ]; then
    print_msg "ERROR: Please, set the Qualys user name into the environment variable 'QUAL_USER'."
    func_die
fi
print_msg "Qualys user: '$QUAL_USER'"

# Get the Qualys password.
if [ ! "$QUAL_PASSWORD" ]; then
    print_msg "ERROR: Please, set the Qualys password into the environment variable 'QUAL_PASSWORD'."
    func_die
fi
print_msg "Qualys password: *****"

# Get the scan title.
QUAL_SCAN_TITLE="$1"; shift
print_msg "Scan title: '$QUAL_SCAN_TITLE'"

# Get the asset tag(s).
QUAL_TAG="$1"; shift
print_msg "Qualys asset tag: '$QUAL_TAG'"

# Get the report template.
QUAL_RPT_TEMPLATE="$1"; shift
print_msg "Report template: '$QUAL_RPT_TEMPLATE'"

# Get the lookback days.
QUAL_SCAN_LOOKBACK=''
if [ "$1" ]; then
    QUAL_SCAN_LOOKBACK="$1"
    if ! [[ "$QUAL_SCAN_LOOKBACK" =~ ^[0-9]+$ ]] || [ $QUAL_SCAN_LOOKBACK -le 0 ]; then
        print_msg "ERROR: '$QUAL_SCAN_LOOKBACK' is invalid. Specify an integer greater than 0."
        func_die
    fi
    print_msg "Scans lookback: $QUAL_SCAN_LOOKBACK day(s)."
fi


########################################################################
# Constants for use in Qualys API calls.
########################################################################
QUAL_HEADER="X-Requested-With: $MY_NAME"
QUAL_SCAN_STATUS="Finished"
QUAL_AUTH="$QUAL_USER:$QUAL_PASSWORD"

# Throughout this script, we will use this 'result' variable to store
# curl call response data. This way, we are not passing around copies
# of potentially large amount of data.
result=''


########################################################################
# Functions specific to working with the Qualys API
########################################################################

#-----------------------------------------------------------------------
# Function to examine 'result' for error response from Qualys.
# Assumes that the response content to examine will be '$result'.
# This function seems to work best with endpoints under /api/2.0/...
# but not with /msp/...
#-----------------------------------------------------------------------
function func_chk_qual_err {
    [ "$result" ] || return 0

    err_code=$(echo "$result" | grep '<CODE>.*</CODE>' | sed 's/^ *//; s/<CODE>//; s/<\/CODE>//')

    if [ "$err_code" ]; then
        err_text=$(echo "$result" | grep '<TEXT>.*</TEXT>' | sed 's/^ *//; s/<TEXT>//; s/<\/TEXT>//')

        print_msg "ERROR:
== Error from Qualys ===================================================
$err_text
========================================================================"
        return 1
    fi

    return 0
}


########################################################################
# Search for the report template by name and obtain the template ID.
# Since this is the first thing we are doing, it's also a good way to
# validate the credentials.
########################################################################

# Get the list of all report templates.
result=$(echo "user $QUAL_AUTH" | curl -s -X GET -K -  -H "$QUAL_HEADER" "${QUAL_URL_BASE}/msp/report_template_list.php")

# Can't use the func_chk_qual_err function here, because the enpoints
# under /msp appear to be non-standard. So, we do a brute-force check.
if ! [[ "$result" =~ REPORT_TEMPLATE_LIST ]]; then
    print_msg "ERROR:
== Error from Qualys ===================================================
$result
========================================================================"
    func_die
fi

# Obtain the ID of the matching report template.
tid=$(xq -r '.REPORT_TEMPLATE_LIST.REPORT_TEMPLATE[]|select(.TITLE=="'"$QUAL_RPT_TEMPLATE"'")|.ID' <<< "$result")

if [ ! "$tid" ]; then
    print_msg "ERROR: Unable to locate the report template '$QUAL_RPT_TEMPLATE'."
    func_die
fi
print_msg "Report template '$QUAL_RPT_TEMPLATE' found with ID ${tid}."


########################################################################
# If requested, check to see that there is are Finished scan within the
# specified lookback days.
########################################################################
if [ "$QUAL_SCAN_LOOKBACK" ]; then

    # Compute the start date-time based on the lookback days.
    now=$(date '+%s')
    (( ss = now - ( 24 * 3600 * $QUAL_SCAN_LOOKBACK ) ))
    since=$(date -u --date="@$ss" '+%Y-%m-%dT%H:%M:00Z')

    print_msg "Looking for '$QUAL_SCAN_STATUS' '$QUAL_SCAN_TITLE' scan(s) since ${since}..."
    result=$(echo "user $QUAL_AUTH" | curl -s -X GET -K - -H "$QUAL_HEADER" "${QUAL_URL_BASE}/api/2.0/fo/scan/?action=list&state=$QUAL_SCAN_STATUS&launched_after_datetime=$since")
    func_chk_qual_err || func_die

    # See if the specified scan has any finished scans.
    scan_count=$(grep -c 'CDATA\['"$QUAL_SCAN_TITLE"'\]' <<< "$result")
    if [ $scan_count -le 0 ]; then
        print_msg "No qualifying scans. Nothing to do. Bye."
        exit
    fi

    print_msg "Found $scan_count $QUAL_SCAN_STATUS scans."
fi


########################################################################
# Launch the report, obtaining the report ID.
########################################################################
print_msg "Launching a new report..."

result=$(echo "user $QUAL_AUTH" | curl -s -X POST -K - -H "$QUAL_HEADER" "${QUAL_URL_BASE}/api/2.0/fo/report/" -d "action=launch&template_id=${tid}&output_format=xml&use_tags=1&tag_set_by=name&tag_set_include=${QUAL_TAG}")
func_chk_qual_err || func_die

# Extract the report ID.
rpt_id=$(xq -r '.SIMPLE_RETURN.RESPONSE.ITEM_LIST.ITEM | select(.KEY=="ID") | .VALUE' <<< "$result")

if [ ! "$rpt_id" ]; then
    print_msg "ERROR: Due to some error, I don't see a report ID."
    func_die
fi

print_msg "Report launched with ID $rpt_id."


########################################################################
# Go into a loop checking for the report status.
########################################################################
chk_count=0
err_count=0

while :
do
    # Don't wait forever for the report.
    (( chk_count++ ))
    if [ $chk_count -gt $MAX_CHK_COUNT ]; then
        print_msg "ERROR: Waited maximum of $MAX_WAIT_MINS minutes for the report. Giving up."
        func_die
    fi

    print_msg "Waiting for report $rpt_id..."
    sleep $SLEEP_SECS

    # Check for the report ID status.
    result=$(echo "user $QUAL_AUTH" | curl -s -X GET -K - -H "$QUAL_HEADER" "${QUAL_URL_BASE}/api/2.0/fo/report/?action=list&id=$rpt_id")
    func_chk_qual_err

    # Retry logic...since a report could take a while. The most likely
    # reason to retry is for network glitches, etc.
    if [ $? -gt 0 ]; then
        (( err_count++ ))
        if [ $err_count -ge $MAX_ERRORS ]; then
            print_msg "ERROR: Maximum $MAX_ERRORS retries reached."
            func_die
        fi
        print_msg "WARNING: Qualys error encountered. Will retry."
        continue
    else
        err_count=0
    fi

    # Check that we got a response for the correct rpt_id.
    rid=$(xq -r '.REPORT_LIST_OUTPUT.RESPONSE.REPORT_LIST.REPORT.ID' <<< "$result")
    rstatus=$(xq -r '.REPORT_LIST_OUTPUT.RESPONSE.REPORT_LIST.REPORT.STATUS.STATE' <<< "$result")

    if [ ! "$rid" ]; then
        print_msg "ERROR: Can't find report with ID '$rpt_id'."
        func_die
    fi
    print_msg "Report $rpt_id is in status '$rstatus'."

    # Decide what to do.
    if   [ "$rstatus" == "Running" ] || [ "$rstatus" == "Submitted" ]; then
        continue
    elif [ "$rstatus" == "Finished" ]; then
        break
    else
        print_msg "ERROR: Received report status '$rstatus'."
        func_die
    fi
done

# If we fall through to here, the report is ready. We will pick it up in
# the next section of the code.


########################################################################
# Extract the report
########################################################################
print_msg "Extracting the report..."
echo "user $QUAL_AUTH" | curl -s -X GET -K - -H "$QUAL_HEADER" "${QUAL_URL_BASE}/api/2.0/fo/report/?action=fetch&id=$rpt_id" || func_die
#
# Here, it's difficult to capture an error since curl returns a success
# in most cases anyway. We'd have to examine the response of the curl
# call, but that could be very large.
#
########################################################################
# Done.
########################################################################
print_msg "Done."
