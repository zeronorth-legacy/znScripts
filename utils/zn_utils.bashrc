########################################################################
# (c) Copyright 2022, Harness, Inc., support@harness.io
#
# This file is a collection of Harness/ZeroNorth utility functions, etc.
# to be used in various zn_*.bash scripts.
#
# ZeroNorth scripts can "include" this file in the same directory as the
# caller script and then near the top of script:
#
# . `dirname $0`/zn_utils.bashrc || exit 1
#
# Requires: curl, jq, sed, tr
#
# Conventions:
# - Most "global" variable names are ALL CAPS and are prefixed "ZN_".
# - Most "local" variable names are lower case and are prefixed "zn_".
# - Most function names are prefixed with "zn_".
# - Functions will and should not use the "exit" statement, except for
#   the zn_die function, whose job is to cause script death.
#
########################################################################

########################################################################
# Constants
########################################################################
#
# General stuff
#
me=$(echo "$0" | sed 's/^-//')          # The sed is for Cygwin.
MY_NAME=`basename "$me"`                # Who am I?
DIR_NAME=`dirname "$me"`                # Where am I?


########################################################################
# Logging - log level is set only once at the beginning.
########################################################################
ZN_LL_D=0
ZN_LL_I=1
ZN_LL_W=2
ZN_LL_E=3
ZN_LL_F=4

[ ! "$ZN_LOG_LEVEL" ] && ZN_LOG_LEVEL="INFO"

if   [ "$ZN_LOG_LEVEL" == "INFO"  ]; then
    ZN_LL=$ZN_LL_I
elif [ "$ZN_LOG_LEVEL" == "DEBUG" ]; then
    ZN_LL=$ZN_LL_D
elif [ "$ZN_LOG_LEVEL" == "WARN"  ]; then
    ZN_LL=$ZN_LL_W
elif [ "$ZN_LOG_LEVEL" == "ERROR" ]; then
    ZN_LL=$ZN_LL_E
elif [ "$ZN_LOG_LEVEL" == "FATAL" ]; then
    ZN_LL=$ZN_LL_F
else
    echo "($MY_NAME: Log level '$ZN_LOG_LEVEL' is not valid--using default logging level.)" >&2
    ZN_LL=$ZN_LL_I
fi


########################################################################
# Diagnostic message functions. All diagnostic messages are written to
# STDERR. FUTURE - make these user configuration by setting log level.
########################################################################

#----------------------------------------------------------------------
# Function to print time-stamped messages
#----------------------------------------------------------------------
function zn_print_msg {
    lvl="$1"; shift
    msg="$1"; shift
    echo -e "`date +'%Y-%m-%d %T'`  $lvl  ${MY_NAME}:line ${BASH_LINENO[-2]}  $msg" >&2
}


#----------------------------------------------------------------------
# Function to conditionally print DEBUG messages
#----------------------------------------------------------------------
function zn_print_debug {
    [ $ZN_LL -le $ZN_LL_D ] && zn_print_msg DEBUG "$1"
}


#----------------------------------------------------------------------
# Function to conditionally print INFO messages (the most common)
#----------------------------------------------------------------------
function zn_print_info {
    [ $ZN_LL -le $ZN_LL_I ] && zn_print_msg INFO "$1"
}


#----------------------------------------------------------------------
# Function to conditionally print WARN messages
#----------------------------------------------------------------------
function zn_print_warn {
    [ $ZN_LL -le $ZN_LL_W ] && zn_print_msg WARNING "$1"
}


#----------------------------------------------------------------------
# Function to print ERROR messages
#----------------------------------------------------------------------
function zn_print_error {
    [ $ZN_LL -le $ZN_LL_E ] && zn_print_msg ERROR "$1"
}


#----------------------------------------------------------------------
# Function to print an ERROR message and cause the script exit 1 (die).
#----------------------------------------------------------------------
function zn_print_fatal {
    [ $ZN_LL -le $ZN_LL_F ] && zn_print_msg FATAL "$1"
    exit 1
}


#----------------------------------------------------------------------
# For backward compatibility
#----------------------------------------------------------------------
function print_msg {
    zn_print_msg MSG "$1"
}


#----------------------------------------------------------------------
# Could be used to cause the executing script to exit with status 1.
#----------------------------------------------------------------------
function zn_die {
    zn_print_fatal "Exiting."
}


#----------------------------------------------------------------------
# Function to URL-encode the specified string.
#----------------------------------------------------------------------
function zn_url_encode {
    sed 's/:/%3A/g; s/\//%2f/g; s/ /%20/g' <<< "$1"
}


########################################################################
# API/REST/Web basics
########################################################################
# Headers
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"

# Default environment
if [ ! "$ZN_ENVIRONMENT" ]; then
    ZN_ENVIRONMENT="PROD"
    zn_print_debug "Using default environment '$ZN_ENVIRONMENT'."
    URL_ROOT="https://api.zeronorth.io"
else
    # User to override.
    if   [[ ${ZN_ENVIRONMENT,,} == 'prod' ]] || [[ ${ZN_ENVIRONMENT,,} == 'production'  ]]; then
        URL_ROOT="https://api.zeronorth.io"
    elif [[ ${ZN_ENVIRONMENT,,} == 'dev'  ]] || [[ ${ZN_ENVIRONMENT,,} == 'development' ]]; then
        URL_ROOT="https://api.zeronorth.dev"
    else
        zn_print_fatal "'$ZN_ENVIRONMENT' is not a valid ZeroNorth environment."
    fi    
    zn_print_info "Using environment '$ZN_ENVIRONMENT'."
fi

# For the future...
[ ! "$ZN_API_VERSION" ] && ZN_API_VERSION="v1"

ZN_API_URL="$URL_ROOT/$ZN_API_VERSION"
zn_print_debug "ZeroNorth API URL base: $ZN_API_URL"


########################################################################
# Generic ZeroNorth API REST call functions.
########################################################################

#-----------------------------------------------------------------------
# Function to make a cURL call to the ZeroNorth REST service. Includes
# logic to check the response/result for errors, which varies depending
# on the endpoint being called.
#
# INPUT:  Method - the call method (GET/POST/DELETE/PUT)
#         URI    - The formatted endpoint URI, with params (no base).
#         data   - Optionally, the JSON payload.
# OUTPUT: The result in JSON, or empty if error.
#
# Errors: This function will try its best to examine the response/result
#         for errors.
#-----------------------------------------------------------------------
function zn_api_call {
    api_data=''

    # Read input params.
    api_method="$1"; shift
    api_uri="$1"; shift
    [[ "$api_uri" =~ ^/ ]] && api_uri=$(sed 's/^\///' <<< "$api_uri")
    [ "$1" ] && api_data="$1"; shift

    # Construct the API URL
    api_url="$ZN_API_URL/$api_uri"

    zn_print_debug "api_method = '$api_method'"
    zn_print_debug "api_url = '$api_url'"
    zn_print_debug "api_data = '$api_data'"

    # The curl call to the API.
    if [ "$api_method" == "POST" ] || [ "$api_method" == "PUT" ]; then
        [ ! "$api_data" ] && api_data='{}'
        result=$(curl -s -X "$api_method" --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "Authorization:${API_KEY}" --data "$api_data" "${api_url}")
    else
        result=$(curl -s -X "$api_method" --header "${HEADER_ACCEPT}" --header "Authorization:${API_KEY}" "${api_url}")
    fi

    zn_print_debug "API result\n$result"

    # Check response code.
    if [[ "$result" =~ '"statusCode":' ]]; then
        response=$(jq '.statusCode' <<< "$result")
        if [ $response -gt 299 ]; then
            zn_print_error "API ${api_method} call to '$api_url' failed:\n${result}"
            return 1
        fi
    fi

    echo "$result"
}


#-----------------------------------------------------------------------
# Function to perform a REST GET API call. Includes logic to check the
# response/result for errors, which is highly variable depending on the
# endpoint being called.
#
# INPUT:  URI - The fully formatted endpoint URI with params (no base).
# OUTPUT: The result in JSON, or empty if error.
#-----------------------------------------------------------------------
function zn_api_get {
    # Read input params.
    api_uri="$1"; shift

    # The call to the API.
    zn_api_call GET "$api_uri"
}


#-----------------------------------------------------------------------
# Function to perform a REST POST API call. Includes logic to check the
# response/result for errors, which is highly variable depending on the
# endpoint being called.
#
# INPUT:  URI       - The formatted endpoint URI with params.
#         data      - Optionally, the JSON payload for the POST call.
#                     While not all ZN POST operations require this, the
#                     REST POST operation requires it anyway. So if this
#                     parameter is not provided, this function will pass
#                     in an empty payload.
# OUTPUT: The result in JSON, or empty if error.
#-----------------------------------------------------------------------
function zn_api_post {
    api_data='{}'                       # The default empty payload

    # Read input params.
    api_uri="$1"; shift
    [ "$1" ] && api_data="$1"; shift

    # The call to the API.
    zn_api_call POST "$api_uri" "$api_data"
}


#-----------------------------------------------------------------------
# Function to perform a REST PUT API call. Includes logic to check the
# response/result for errors, which is highly variable depending on the
# endpoint being called.
#
# INPUT:  URI       - The formatted endpoint URI with params.
#         data      - The JSON payload for the PUT call.
# OUTPUT: The result in JSON, or empty if error.
#-----------------------------------------------------------------------
function zn_api_put {
    # Read input params.
    api_uri="$1"; shift
    api_data="$1"; shift

    # The call to the API.
    zn_api_call PUT "$api_uri" "$api_data"
}


#-----------------------------------------------------------------------
#
# WARNING - THIS FUNCTION DELETES YOUR VALUABLE ZERONORTH OBJECTS. USE
# WITH CAUTION. THE CALLER IS REPONSBIBLE FOR PROVIDING CORRECT PARAMS!
#
# Function to perform a REST DELETE API call. Includes logic to check
# the response/result for errors, which is highly variable depending on
# the endpoint being called.
#
# INPUT:  URI - The formatted endpoint URI with params.
# OUTPUT: The result in JSON, or empty if error.
#-----------------------------------------------------------------------
function zn_api_delete {
    # Read input params.
    api_uri="$1"; shift

    # The call to the API.
    zn_api_call DELETE "$api_uri"
}


########################################################################
# Wrappers functions for ZeroNorth API REST calls.
########################################################################

#-----------------------------------------------------------------------
# Function to retrieve a list of objects from those API endpoings that
# allow objects lookup, sometimes with query params.
#
# INPUT:  Object type - Basically, the name of the API endpoint to use.
#                       For example, to update an Application, specify
#                       "applications".
#         Query param - Optional query param(s) as a single string. The
#                       caller is responsible for correctly formatting
#                       the query params.
# OUTPUT: The result in JSON.
#-----------------------------------------------------------------------
function zn_get_obj_list {
    query_params=''

    # Read input params.
    obj_type="$1"; shift
    [ "$1" ] && query_params="$1"; shift

    # Use the related function to make the API call.
    zn_api_get "${obj_type}${query_params}"
}


#-----------------------------------------------------------------------
# Function to retrieve a ZeroNorth object by ID.
#
# INPUT:  Object type - Basically, the name of the API endpoint to use.
#                       For example, to look up an Application, specify
#                       "applications".
#         Object ID   - The ID of the object to look up.
# OUTPUT: The JSON response.
#-----------------------------------------------------------------------
function zn_get_object {
    # Read input params.
    obj_type="$1"; shift
    obj_id="$1"; shift

    zn_print_debug "Looking up an instance of $obj_type with the ID $obj_id..."

    # Look up the object.
    result=$(zn_api_get "${obj_type}/$obj_id")
    [ "$?" -gt 0 ] && return 1

    # Acknowlege the find.
    obj_name=$(jq -r '.data.name' <<< "$result")
    zn_print_debug "Found '$obj_name' matching the ID '$obj_id'."

    echo "$result"
}


#-----------------------------------------------------------------------
# Function to obtain the details of a ZeroNorth object by ID.
#
# INPUT:  Object type - Basically, the name of the API endpoint to use.
#                       For example, to look up an Application, specify
#                       "applications".
#         Object ID   - The ID of the object to look up.
# OUTPUT: The data section of the Object's details.
#-----------------------------------------------------------------------
function zn_get_object_data {
    # Read input params.
    obj_type="$1"; shift
    obj_id="$1"; shift

    # Look up the object.
    result=$(zn_get_object "$obj_type" "$obj_id")
    [ ! "$result" ] && return 1

    # Output just the data section.
    jq '.data' <<< "$result"
}


#-----------------------------------------------------------------------
# Function to look up a ZeroNorth object by name. This function is for
# API endpoints that allow a name search and returns a list of possible
# matches, such as Environments, Applications, Targets, Policies, etc.
#
# INPUT:  Object type - Basically, the name of the API endpoint to use.
#                       For example, to look up an Application, specify
#                       "applications".
#         Object name - The name of the object to lookup. Do not URL-
#                       encode the name. I will take care of it.
#
# OUTPUT: Object ID, if unique match found.
#
# NOTE:   The Name search is case insensitive.
#-----------------------------------------------------------------------
function zn_get_by_name {
    obj_id=''

    # Read input params.
    obj_type="$1"; shift
    obj_name="$1"; shift

    # URL-encode for web safety.
    encode_obj_name=$(zn_url_encode "$obj_name")

    # Get all possible matches.
    result=$(zn_get_obj_list "$obj_type" "?name=${encode_obj_name}")
    [ ! "$result" ] && return 1

    # How many possible matches?
    obj_count=$(jq -r '.[1].count' <<< "$result")
    zn_print_debug "Initial matches count: $obj_count"

    # Found 1 or more...need to look closer.
    if [ $obj_count -gt 0 ]; then
        # Let's look for a full, but case-insensitive match.
        obj_id=$(jq -r '.[0][]|select((.data.name|ascii_downcase)==("'"${obj_name}"'"|ascii_downcase))|.id' <<< "$result")
        if   [ ! "$obj_id" ]; then
            obj_count=0
        else
            obj_count=$(wc -l <<< "$obj_id")
        fi
    fi

    zn_print_debug "Final matches count: $obj_count"

    # Exactly 1, we can use it!
    if [ $obj_count -eq 1 ]; then
        zn_print_info "Found '$obj_name', ID: $obj_id"
        echo "$obj_id"
        return

    # Didn't find any.
    elif [ $obj_count -eq 0 ]; then
        zn_print_info "Did not find '$obj_name'."

    # We still got multiple matches. No good.
    elif [ $obj_count -gt 1 ]; then
        zn_print_error "Found multiple matches for the Name '$obj_name'!"
        return 1

    # We should not end up here.
    else
        zn_print_error "Unpexpected result."
        return 1

    fi
}


#-----------------------------------------------------------------------
# A wrapper function to perform a REST POST API call whereby the object
# ID is specified as a dedicated parameter.
#
# INPUT:  Object type - Basically, the name of the API endpoint to use.
#                       For example, to update an Application, specify
#                       "applications".
#         data        - The JSON payload for the PUT call.
# OUTPUT: The result in JSON, or empty if error.
#-----------------------------------------------------------------------
function zn_post_obj_by_type {
    # Read input params.
    obj_type="$1"; shift
    obj_data="$1"; shift

    zn_print_debug "Attempting to create an instance of $obj_type..."
    zn_print_debug "The payload is:\n$obj_data"

    # Use the related function to make the API call.
    zn_api_post "$obj_type" "$obj_data"
}


#-----------------------------------------------------------------------
# A wrapper function to perform a REST PUT API call whereby the object
# ID is specified as a dedicated parameter.
#
# INPUT:  Object type - Basically, the name of the API endpoint to use.
#                       For example, to update an Application, specify
#                       "applications".
#         Object ID   - The ZeroNorth object ID to update with the PUT.
#         data        - The JSON payload for the PUT call.
# OUTPUT: The result in JSON, or empty if error.
#-----------------------------------------------------------------------
function zn_put_obj_by_type_id {
    # Read input params.
    obj_type="$1"; shift
    obj_id="$1"; shift
    obj_data="$1"; shift

    zn_print_debug "Attempting to update an instance of $obj_type with the ID $obj_id..."
    zn_print_debug "The payload is:\n$obj_data"

    # Use the related function to make the API call.
    zn_api_put "${obj_type}/${obj_id}" "$obj_data"
}


#-----------------------------------------------------------------------
#
# WARNING - THIS FUNCTION DELETES YOUR VALUABLE ZERONORTH OBJECTS. USE
# WITH CAUTION. THE CALLER IS REPONSBIBLE FOR CORRECT AND SAFE USE!!!
#
# A wrapper function to perform a REST DELETE API call whereby the
# object ID is specified as a dedicated parameter.
#
# INPUT:  Object type - Basically, the name of the API endpoint to use.
#                       For example, to update an Application, specify
#                       "applications".
#         Object ID   - The ZeroNorth object ID to update with the PUT.
# OUTPUT: The result in JSON, or empty if error.
#-----------------------------------------------------------------------
function zn_delete_obj_by_type_id {
    # Read input params.
    obj_type="$1"; shift
    obj_id="$1"; shift

    zn_print_debug "Attempting to delete an instance of $obj_type with the ID $obj_id..."

    # Use the related function to make the API call.
    zn_api_delete "${obj_type}/${obj_id}"
}


########################################################################
# Functions for CS/Field use cases
########################################################################

#-----------------------------------------------------------------------
# Look up the current account info "me" using the currently set API_KEY.
#
# INPUT:  None.
# Output: The full JSON response about "me".
#-----------------------------------------------------------------------
function zn_customer_data {
    zn_api_call GET "accounts/me"
}


#-----------------------------------------------------------------------
# Look up the current customer name.
#
# INPUT:  None.
# Output: The customer account name
#-----------------------------------------------------------------------
function zn_customer_name {
    result=$(zn_customer_data)

    if [ $? -gt 0 ]; then
        zn_print_error "Customer name look up failed."
        return 1
    fi

    cust_name=$(jq -r '.customer.data.name' <<< "$result")

    if [ ! "$cust_name" ]; then
        zn_print_error "Unable to extract customer name."
        return 1
    fi

    echo "$cust_name"
}


#-----------------------------------------------------------------------
# Look up the my name.
#
# INPUT:  None.
# Output: My login name
#-----------------------------------------------------------------------
function zn_who_am_i {
    result=$(zn_customer_data)

    if [ $? -gt 0 ]; then
        zn_print_error "Name look up failed."
        return 1
    fi

    my_name=$(jq -r '.name' <<< "$result")

    if [ ! "$my_name" ]; then
        zn_print_error "Unable to extract my name."
        return 1
    fi

    echo "$my_name"
}



#-----------------------------------------------------------------------
# Retrieve job history for a Policy ID.
#
# INPUT:  Policy ID      - The Policy ID.
#         Since/Lookback - This must be one of:
#                          * Since - YYYY-MM-DD format "since" date.
#                          * Lookback - the number of days to look back.
#         Status         - Optionally, the job status to filter for.
#                          e.g. FAILED, RUNNING, etc.
# OUTPUT: The result as a CSV list, sorted by job created date.
#
# Errors: This function will try its best to examine the response/result
#         for errors.
#-----------------------------------------------------------------------
function zn_policy_jobs_list {
    status_filter=''

    # Read input params.
    pol_id="$1"; shift
    since="$1"; shift
    [ "$1" ] && status_filter="$1"; shift

    zn_print_debug "Policy ID: '$pol_id'"
    zn_print_debug "Since: '$since'"
    zn_print_debug "status_filter: '$status_filter'"

    # Input validations - Since
    if [[ "$since" =~ ^[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]$ ]]; then
        zn_print_info "Will look starting $since."
    elif [ -n "$since" ] && [ $since -eq $since ]; then
        msg="Will look back $since day"; [ $since -gt 1 ] && msg="${msg}s"; msg="${msg}."
        zn_print_info "$msg"
        # We need to compute the "since" date from the lookback value.
        now=$(date '+%s')
        (( ss = now - ( 86400 * $since ) ))
        since=$(date --date="@$ss" '+%Y-%m-%d')
        zn_print_debug "The computed since date is '$since'."
    else
        zn_print_error "'$since' is not valid value for the since/lookback parameter. It must be in the form of YYYY-MM-DD or number of days to look back."
        return 1
    fi

    # Input validation - Status filter
    if [ "$status_filter" ] && [[ ! "$status_filter" =~ ^[A-Z]*$ ]]; then
        zn_print_error "'$status_filter' is not a valid job status."
        return 1
    fi

    # Input validations - Policy ID, look it up.
    result=$(zn_get_object policies $pol_id)
    if [ $? -gt 0 ]; then
        zn_print_error "Policy lookup failed."
        return 1
    fi

    # Look up the jobs.
    result=$(zn_get_obj_list jobs "?policyId=${pol_id}&since=${since}&limit=3000")
    if [ $? -gt 0 ]; then
        zn_print_error "Jobs look up failed."
        return 1
    fi

    # Were there any jobs?
    jobs_num=$(jq -r '.[1].count' <<< "$result")
    if [ $jobs_num -eq 0 ]; then
        zn_print_info "No jobs found."
        return
    fi

    # The TOTAL number of jobs for the Policy in the given date range.
    msg="Found total of $jobs_num job"; [ $jobs_num -gt 1 ] && msg="${msg}s"; msg="${msg}."
    zn_print_debug "$msg"

    echo "date,jobId,status,start,end,dur.(mins)"
    jobs_list=$(jq -r '
      .[0] | sort_by(.meta.created) | .[] |
      ((.meta.created|split("T"))|.[0])
      +","+.id
      +","+.data.status
      +","+((.meta.created|split("."))|.[0]|sub("T";" "))
      +","+((.meta.lastModified|split("."))|.[0]|sub("T";" "))
      +","+(
             (
               (
                 (.meta.lastModified|split(".")|.[0]+"Z"|fromdate)
                -(.meta.created|split(".")|.[0]+"Z"|fromdate)
               )
               /60
             )|tostring
           )
' <<< "$result")

    zn_print_debug "Jobs list before any filters:\n$jobs_list"

    # Optionally filter the results by the job status filter.
    [ "$status_filter" ] && jobs_list=$(grep -w "$status_filter" <<< "$jobs_list")

    zn_print_debug "Jobs list after any filters:\n$jobs_list"

    if [ ! "$jobs_list" ]; then
        zn_print_info "No qualifying jobs."
        return
    fi
    
    jobs_num=$(wc -l <<< "$jobs_list")
    msg="Found $jobs_num qualifying job"; [ $jobs_num -gt 1 ] && msg="${msg}s"; msg="${msg}."
    zn_print_debug "$msg"
    echo "$jobs_list"
}
