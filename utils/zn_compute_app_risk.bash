#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# A prototype script to compute application security risk by reading in
# an extract produced by zn_get_all_apps_targets_issues.bash. The output
# contains two sections for each Application:
#
# 1) Current risk
# 2) Risk trend by month
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
# of 1 calendar year.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."

MY_NAME=`basename $0`
DELIM='|'


########################################################################
# Tuning constants
########################################################################
DIV_FACTOR="100.0"
OWASP_FACTOR="1.5"


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Help info and read input params.
########################################################################
if [ ! "$1" ]
then
    echo "
A prototype script to compute application security risk by reading in
an extract produced by zn_get_all_apps_targets_issues.bash. The output
contains two sections for each Application:

1) Current risk
2) Risk trend by month


Usage: $MY_NAME <input_file> [<delimiter>]

where,

  input_file  - The file with the extract data. Specify '-' to feed the
                data via STDIN.

  delimiter   - The delimiter character to use for parsing the input
                file. The default is '|'. Note that this script does
                not know how to handle a true CSV file.


Examples: cat my_data_file | $MY_NAME -
          cat my_data_file | $MY_NAME - > my_output_file
          $MY_NAME my_data_file
          $MY_NAME my_data_file '|'
          $MY_NAME my_data_file '|' > my_output_file
" >&2
    exit 1
fi

IN_FILE="$1"; shift
if [ "$IN_FILE" == "-" ]
then
    print_msg "Input will be read via STDIN."
else
    rec_count=$(wc -l < "$IN_FILE")
    print_msg "Input data file is '$IN_FILE' and has $rec_count records."
fi

if [ "$1" ]; then
    DELIM="$1"
    print_msg "Delimiter character has been overriden to '$1'."
fi


########################################################################
# Prep.
########################################################################

# Find a suitable working directory
[ "${TEMP}" ] && TEMP_DIR="${TEMP}" || TEMP_DIR="/tmp"

# Prepare the temporary work file.
TEMP_FILE="${TEMP_DIR}/${MY_NAME}.`date '+%s'`.tmp"


########################################################################
# Preprocess the records, computing the basic risk score for each row.
# The resulting intermediate data is store in a temp file.
########################################################################
# This section expects the incoming file to have the following format:
# customer|appId|appName|tgtId|tgtName|tgtType|tgtCreated|tgtTags|AST|issueId|scanner|issueKey|issueName|issueSeverity|issueSeverityCode|issueStatus|ignoreFlag|issueDetectionDate|issueRemediationDate|issueAgeDays|A1|A2|A3|A4|A5|A6|A7|A8|A9|A10

function func_preprocess {
    rec_num=0
    print_msg "Examining record #:"

    # Iterate through the records in the file.
    cat "${IN_FILE}" | while IFS="$DELIM" read customer appId appName tgtId tgtName tgtType tgtCreated tgtTags AST issueId scanner issueKey issueName issueSeverity issueSeverityCode issueStatus ignoreFlag issueDetectionDate issueRemediationDate issueAgeDays owaspTop10
    do
        # Skip the header record.
        [ "$customer" == "customer" ] && continue

        (( rec_num++ ))
        echo -en "\r${rec_num}..." >&2

        # Init vars for this record.
        owaspFactor=''; issueScore=''

        # Compute only if the record has issue data.
        if [ "$issueId" ]; then
            # Set the OWASP Top-10 multiplier.
            if [ "$owaspTop10" == '|||||||||' ]; then
                owaspFactor="1.0"
            else
                owaspFactor=$OWASP_FACTOR
            fi

            # Parse the date fields, extracting just YYYY-MM.
            [ "$issueDetectionDate" ] && issueDetectionDate=$(sed 's/-[0-9][0-9] .*//' <<< "$issueDetectionDate")
            [ "$issueRemediationDate" ] && issueRemediationDate=$(sed 's/-[0-9][0-9] .*//' <<< "$issueRemediationDate")

            # Ensure the severity >= 0 (Some Info issues are "-1").
            [ "$issueSeverity" == "-1" ] && issueSeverity=0

            # Compute the issue-level risk score.
            issueScore=$(bc <<< "$issueSeverity * $issueAgeDays * $owaspFactor")
        fi

        echo "$customer|$appId|$appName|$issueSeverity|$issueStatus|$ignoreFlag|$issueDetectionDate|$issueRemediationDate|$issueAgeDays|$owaspFactor|$issueScore"
    done > ${TEMP_FILE}
    echo >&2

    # A quick tally on the temp file.
    rec_count=`wc -l < ${TEMP_FILE}`
    if [ $rec_count -le 0 ]; then
        print_msg "No eligible records in the input file. Goodbye."
        exit
    else
        print_msg "Selected $rec_count eligible records from the input file."
    fi
}


########################################################################
# Using the intermediate data in the temp file, compute the risk score
# for each application. The output is basically the current risk score
# by application.
########################################################################
function func_compute_app_risk {
    print_msg "Computing app-level risk scores from intermediate results..."

    # Initialize some counters and vars.
    prev_app_id=''; customer_name=''; app_id=''; app_name=''; app_risk_score="0.0"

    # Print the column headings.
    echo "customer|appId|appName|appRiskScore"

    # Iterate through the preprocessed records, summing them up.
    while IFS='|' read customer appId appName issueSeverity issueStatus ignoreFlag issueDetectionDate issueRemediationDate issueAgeDays owaspFactor issueScore
    do
        # New app detected.
        if [ "$appId" != "$prev_app_id" ]; then
            # Print the result.
            if [ "$prev_app_id" ]; then
                app_risk_score=$(bc <<< "$app_risk_score / $DIV_FACTOR")
                echo "$customer_name|$app_id|$app_name|$app_risk_score"
            fi

            # Reset.
            app_risk_score="0.0"
            prev_app_id="$appId"
        fi

        # Set the ext vars for later use.
        customer_name="$customer"
        app_id="$appId"
        app_name="$appName"

        # Add to the app-level risk score
        [ "$issueSeverity" ] && [ "$issueStatus" != "Remediation" ] && [ "$ignoreFlag" != "true" ] && app_risk_score=$(bc <<< "$app_risk_score + $issueScore")
    done < ${TEMP_FILE}

    # Print the last app score.
    app_risk_score=$(bc <<< "$app_risk_score / $DIV_FACTOR")
    echo "$customer_name|$app_id|$app_name|$app_risk_score"
}

########################################################################
# Again, using the intermediate data in the temp file, compute the risk
# score increase by year-month for each application. This is just sum of
# the score for all issues detected in each month.
########################################################################
function func_compute_monthly_increase {
    print_msg "Computing app-level monthly raw score contributions..."
    print_msg "Examining qualifying record #:"

    # Initialize some counters and vars.
    rec_num=0
    prev_app_id=''; prev_year_month=''
    customer_name=''; app_id=''; app_name=''; issue_year_month=''; raw_score_increase="0.0"

    # Iterate through the preprocessed records, summing up only the "open" records.
    while IFS='|' read customer appId appName issueSeverity issueStatus ignoreFlag issueDetectionDate issueRemediationDate issueAgeDays owaspFactor issueScore
    do
        # Skip the records that do not contribute.
        [ "$ignoreFlag" == "true" ] && continue

        (( rec_num++ ))
        echo -en "\r${rec_num}..." >&2

        # Break detected.
        if [ "$issueDetectionDate" != "$prev_year_month" ] || [ "$appId" != "$prev_app_id" ]; then

            # Print the result, but only if not the very first time.
            if [ "$prev_app_id" ]; then
                echo "$customer_name|$app_id|$app_name|$issue_year_month|OPENED|$raw_score_increase"
            fi

            [ "$issueDetectionDate" != "$prev_year_month" ] && prev_year_month="$issueDetectionDate"
            [ "$appId" != "$prev_app_id" ] && prev_app_id="$appId"

            # Reset.
            raw_score_increase="0.0"
        fi

        # Set the ext vars for later use.
        customer_name="$customer"
        app_id="$appId"
        app_name="$appName"
        issue_year_month=$issueDetectionDate

        # Add to the app-level risk score
        [ "$issueScore" ] && raw_score_increase=$(bc <<< "$raw_score_increase + $issueScore")
    done <<< $(sort -t'|' -k '1,2' -k'6,6' ${TEMP_FILE})
    echo >&2

    # Print the last app score.
    echo "$customer_name|$app_id|$app_name|$issue_year_month|OPENED|$raw_score_increase"
}


########################################################################
# Again, using the intermediate data in the temp file, compute the risk
# score decrease by year-month for each application. This is just sum of
# the score for all issues closed in each month.
########################################################################
function func_compute_monthly_decrease {
    print_msg "Computing app-level monthly raw score deductions..."
    print_msg "Examining qualifying record #:"

    # Initialize some counters and vars.
    rec_num=0
    prev_app_id=''; prev_year_month=''
    customer_name=''; app_id=''; app_name=''; issue_year_month=''; raw_score_decrease="0.0"

    # Iterate through the preprocessed records, summing up only the "open" records.
    while IFS='|' read customer appId appName issueSeverity issueStatus ignoreFlag issueDetectionDate issueRemediationDate issueAgeDays owaspFactor issueScore
    do
        # Skip the records that do not contribute.
        if [ "$issueStatus" != "Remediation" ] || [ "$ignoreFlag" == "true" ]; then
            continue
        fi

        (( rec_num++ ))
        echo -en "\r${rec_num}..." >&2

        # Break detected.
        if [ "$issueRemediationDate" != "$prev_year_month" ] || [ "$appId" != "$prev_app_id" ]; then

            # Print the result, but only if not the very first time.
            if [ "$prev_app_id" ]; then
                echo "$customer_name|$app_id|$app_name|$issue_year_month|CLOSED|$raw_score_decrease"
            fi

            [ "$issueRemediationDate" != "$prev_year_month" ] && prev_year_month="$issueRemediationDate"
            [ "$appId" != "$prev_app_id" ] && prev_app_id="$appId"

            # Reset.
            raw_score_decrease="0.0"
        fi

        # Set the ext vars for later use.
        customer_name="$customer"
        app_id="$appId"
        app_name="$appName"
        issue_year_month=$issueRemediationDate

        # Add to the app-level risk score
        [ "$issueScore" ] && raw_score_decrease=$(bc <<< "$raw_score_decrease + $issueScore")
    done <<< $(sort -t'|' -k '1,2' -k'7,7' ${TEMP_FILE})
    echo >&2

    # Print the last app score.
    echo "$customer_name|$app_id|$app_name|$issue_year_month|CLOSED|$raw_score_decrease"
}


########################################################################
# Function to compute the monthly trend of the risk score using the pre-
# computed monthly OPENED (increase) and CLOSED (decrease) scores.
#
# Input:  List of OPENED monthly raw scores.
#         List of CLOSED monthly raw scores.
# Oupput: List of monthly trend scores.
########################################################################
function func_compute_monthly_trend {
    opened="$1"; shift
    closed="$1"; shift

    print_msg "Computing app-level monthly raw score trend..."

    # Sort the two inputs.
    scores=$(echo -e "${opened}\n${closed}" | sort)

    # Initialize some counters and vars.
    prev_app_id=''; prev_year_month=''
    customer_name=''; app_id=''; app_name=''; year_month=''; score="0.0"
    raw_score_sum="0.0"

    # Print the column headings.
    echo "customer|appId|appName|yearMonth|riskScore"

    # Read the records and break process on appId and year-month.
    while IFS="|" read customer appId appName yearMonth openClose rawScore
    do
        # Skip records that do not have issue/score data
        [ ! "$yearMonth" ] && continue

        # Break detected.
        if [ "$yearMonth" != "$prev_year_month" ] || [ "$appId" != "$prev_app_id" ]; then

            # Print the result, but only if not the very first time.
            if [ "$prev_app_id" ]; then
                score=$(bc <<< "$raw_score_sum / $DIV_FACTOR")
                echo "$customer_name|$app_id|$app_name|$year_month|$score"
            fi

            [ "$yearMonth" != "$prev_year_month" ] && prev_year_month="$yearMonth"
            if [ "$appId" != "$prev_app_id" ]; then
                prev_app_id="$appId"
                raw_score_sum="0.0"
            fi
        fi

        # Set the ext vars for later use.
        customer_name="$customer"
        app_id="$appId"
        app_name="$appName"
        year_month="$yearMonth"

        # Add to or subtract from the app-level raw score
        if   [ "$openClose" == "OPENED" ]; then
            raw_score_sum=$(bc <<< "$raw_score_sum + $rawScore")
        elif [ "$openClose" == "CLOSED" ]; then
            raw_score_sum=$(bc <<< "$raw_score_sum - $rawScore")
        else
            print_msg "ERROR: unreconized score type '$openClose'. Exiting."
            exit 1
        fi
    done <<< "$scores"

    # Print the last app score.
    score=$(bc <<< "$raw_score_sum / $DIV_FACTOR")
    echo "$customer_name|$app_id|$app_name|$year_month|$score"
}


########################################################################
# M A I N
########################################################################
# Do the preprocessing.
func_preprocess

# Get the main scores.
func_compute_app_risk

# Get the intermediate monthly scores.
raw_score_increase=$(func_compute_monthly_increase)
# echo "DEBUG: raw_score_increase:
# $raw_score_increase" >&2 # DEBUG

raw_score_decrease=$(func_compute_monthly_decrease)
# echo "DEBUG: raw_score_decrease:
# $raw_score_decrease" >&2 # DEBUG

# Merge the two intermediate results for monthly trend by app.
func_compute_monthly_trend "$raw_score_increase" "$raw_score_decrease"

########################################################################
# Done.
########################################################################
[ "${TEMP_FILE}" ] && [ -w ${TEMP_FILE} ] && rm "${TEMP_FILE}" && print_msg "Temp file '${TEMP_FILE}' removed."
print_msg "Done."
