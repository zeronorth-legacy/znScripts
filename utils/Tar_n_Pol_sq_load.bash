#!/bin/bash
########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1" >&2
}
verbose=""

# Usage: `basename $0` -k API_KEY_FILE -K API_KEY -T TARGET_NAME -i INTEGRATION_ID  -t INTEGRATION_TYPE -p POLICY_TYPE -P POLICY_NAME -S SCENARIO_ID -s SCENARIO_TYPE -q SQ_PROJECT_NAME -Q SQ_PROJECT_KEY -d DATA_FILE -O OPCO_TAG -A APP_NAME_TAG -E ENV_TAG

## Set required arguments to null
API_KEY_FILE=""
API_KEY=""
TARGET_NAME=""
INTEGRATION_TYPE="artifact"
INTEGRATION_ID=""
POLICY_TYPE="dataLoad"
POLICY_NAME=""
SCENARIO_ID=""
DATA_FILE=""

## Optional Arguments, required for SonarQube dataLoad policy
SCENARIO_TYPE="sonarqube"
SQ_PROJECT_NAME=""
SQ_PROJECT_KEY=""

## Set Target Tag Default Values
OPCO_TAG="TG"
APP_NAME_TAG="AppUknown"
ENV_TAG="EnvUnknown"
### Optional Description to created policies
POLICY_DESCRIPTION=""

# Read in options and values
while getopts ":k:K:T:i:I:p:P:S:s:q:Q:d:O:E:A:v" opt; do
    case ${opt} in
        k )
            API_KEY_FILE="$OPTARG"
            ;;
        K )
            API_KEY="$OPTARG"
            ;;
        T )
            TARGET_NAME="$OPTARG"
            ;;
        i )
            INTEGRATION_TYPE="$OPTARG"
            ;;
        I )
            INTEGRATION_ID="$OPTARG"
            ;;
        p )
            POLICY_TYPE="$OPTARG"
            ;;
        P)
            POLICY_NAME="$OPTARG"
            ;;
        S )
            SCENARIO_ID="$OPTARG"
            ;;
        s )
            SCENARIO_TYPE="$OPTARG"
            ;;
        q )
            SQ_PROJECT_NAME="$OPTARG"
            ;;
        Q )
            SQ_PROJECT_KEY="$OPTARG"
            ;;
        d )
            DATA_FILE="$OPTARG"
            ;;
        O)
            OPCO_TAG="$OPTARG"
            ;;
        E)
            APP_NAME_TAG="$OPTARG"
            ;;
        A)
            ENV_TAG="$OPTARG"
            ;;
        v)
            verbose="TRUE"
            ;;
        \? )
            echo "Invalid option: $OPTARG" 1>&2
            exit 1
            ;;
        : )
            echo "Invalid option: $OPTARG requires an argument" 1>&2
            exit 1
            ;;
    esac
done
# If no options passed print usage details
if [ $OPTIND -eq 1 ]; then 
    echo "usage:"
    echo "assign required arguments in script or at script invocation"
    echo "      required arguments: -k API_KEY_FILE"
    echo "                          -K API_KEY"
    echo "                          -T TARGET_NAME"
    echo "                          -i INTEGRATION_TYPE"
    echo "                          -I INTEGRATION_ID"
    echo "                          -p POLICY_TYPE"
    echo "                          -P POLICY_NAME"
    echo "                          -S SCENARIO_ID"
    echo "                          -d DATA_FILE"
    echo "      optional arguments: -O OPCO_TAG"
    echo "                          -E ENV_TAG"
    echo "                          -A APP_NAME_TAG"
    echo "                          -s SCENARIO_TYPE (required for SonarQube)"
    echo "                          -q SQ_PROJECT_NAME (required for SonarQube)"
    echo "                          -Q SQ_PROJECT_KEY (required for SonarQube)"
    echo "                          -v verbose (set -xv)"
    exit
fi
shift $((OPTIND -1))

if [ -n "${verbose}" ]; then
    set -xv
fi

echo $API_KEY_VARIABLE
# Check if required options and arguments were provided
if [ -z "$API_KEY_FILE" ] && [ -z "$API_KEY" ]; then 
    print_msg "ZN API Key not provided. Exiting."; exit 1
    elif [ -z "$TARGET_NAME" ]; then
        print_msg "Target Name not provided. Exiting."; exit 1
    elif [ -z "$INTEGRATION_ID" ]; then
        print_msg "Integration ID not provided. Exiting."; exit 1
    elif [ -z "$INTEGRATION_TYPE" ]; then
        print_msg "Integration Type not provided. Exiting."; exit 1
    elif [ -z "$POLICY_TYPE" ]; then
        print_msg "Policy Type not provided. Exiting."; exit 1
    elif [ -z "$POLICY_NAME" ]; then
        print_msg "Policy Name not provided. Exiting."; exit 1
    elif [ -z "$SCENARIO_ID" ]; then
        print_msg "Scenario ID not provided. Exiting."; exit 1
    elif [ -z "$DATA_FILE" ]; then
        print_msg "Data File not provided. Exiting."; exit 1
fi

if [ -n "$API_KEY_FILE" ]; then
    print_msg "ZeroNorth Key File: '${API_KEY_FILE}'"
fi

print_msg "Target Name: '${TARGET_NAME}'"
print_msg "Integration Type: '${INTEGRATION_TYPE}'"
print_msg "Integration ID: '${INTEGRATION_ID}'"
print_msg "Policy Type: '${POLICY_TYPE}'"
print_msg "Policy Name: '${POLICY_NAME}'"
print_msg "Scenario ID: '${SCENARIO_ID}'"
print_msg "Data file: '${DATA_FILE}'"
print_msg "OpCo: '${OPCO_TAG}'"
print_msg "App Name: '${APP_NAME_TAG}'"
print_msg "Env Tag: '${ENV_TAG}'"

# if scenario type if sonarqube check for SQ_PROJECT_NAME and SQ_PROJECT_KEY
if [ "$SCENARIO_TYPE" == "sonarqube" ]; then
    print_msg "SCENARIO_TYPE: '${SCENARIO_TYPE}'"
    if [ -n "$SQ_PROJECT_NAME" ]; then
        print_msg "SQ_PROJECT_NAME: '${SQ_PROJECT_NAME}'"
    else
        print_msg "SQ_PROJECT_NAME not provided. Exiting"
        exit 1
    fi

    if [ -n "$SQ_PROJECT_KEY" ]; then
        print_msg "SQ_PROJECT_KEY: '${SQ_PROJECT_KEY}'"
    else
        print_msg "SQ_PROJECT_KEY not provided. Exiting"
        exit 1
    fi
fi

# Set Target Tags using default or user provided values
TARGET_TAGS="\"${OPCO_TAG}\",\"${APP_NAME_TAG}\",\"${ENV_TAG}\""

## If manual upload check data file
if [ "$POLICY_TYPE" == "manualUpload" ]; then
    print_msg "Checking Data file..."
    if [ -f "$DATA_FILE" ]; then
        print_msg "Data file exists."
    else
        print_msg "Data file does not exist. Exiting."; exit 1
    fi
fi

## Check if API token is valid
print_msg "Checking ZN API key..."
if [ -n "$API_KEY_FILE" ]; then
    if [ -f "$API_KEY_FILE" ]; then 
        API_KEY=$(cat "$API_KEY_FILE")
        # Check if zn api key is readable
        if [ $? != 0 ]; then 
            print_msg "Can't read key file! Exiting."
            exit 1
        fi
        print_msg "ZN API key exists."
    else
        print_msg "ZN API Key file does not exist. Exiting."
        exit 1
    fi
elif [ -n "$API_KEY" ]; then
    print_msg "Reading ZN API key from variable"
fi


########################################################################
# Constants
########################################################################
## API Calls
URL_ROOT="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type:${DOC_FORMAT}"
HEADER_ACCEPT="Accept:${DOC_FORMAT}"
HEADER_AUTH="Authorization:${API_KEY}"

# Check if API key isn't expired/is valid
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/accounts/me")
statusCode=$(echo ${result} | jq -r 'select(.statusCode != null) | .statusCode')
if [ -n "$statusCode" ]; then
    response_err=$(echo ${result} | jq -r 'select(.statusCode != null) | .error')
    err_message=$(echo ${result} | jq -r 'select(.statusCode != null) | .message')
    print_msg "Received response error ${statusCode} ${response_err}"
    print_msg "Error message: ${err_message}"
    exit 1
fi

########################################################################
# The below code does the following:
#
# 1a) Look up the Target based on the specified Target Name.
# 1b) Create the Target if it doesn't exist using the specified Target Name
#     and specified integration id/type
########################################################################
#
# 1a), check to see if a Target by same name exists
#
# URL encode TARGET_NAME
encode_TARGET_NAME=$(echo ${TARGET_NAME} | sed 's|:|%3A|g' | sed 's|/|%2f|g' | sed 's| |%20|g')
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/targets?name=${encode_TARGET_NAME}")
# How many matching targets?
tgt_count=$(echo ${result} | jq -r '.| .[1].count')

# 1 or more matches...need to look closer.
if [ $tgt_count -gt 0 ]; then
    # Let's look for exact match.
    tgt_id=$(echo "$result" | jq -r '.[0][]|select((.data.name|ascii_downcase)==("'${TARGET_NAME}'"|ascii_downcase))|.id')
    if   [ ! "$tgt_id" ]; then
        tgt_count=0
    else
        tgt_count=$(wc -l <<< "$tgt_id")
    fi
fi

# is we're still more than 1, no bueno, die
if [ $tgt_count -gt 1 ]; then
    print_msg "Found multiple matches for the Target Name '${TARGET_NAME}'!!! Exiting."; exit 1
# exactly 1, we can use it
elif [ $tgt_count -eq 1 ]; then
    tgt_id=$(echo ${result} | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Target '${TARGET_NAME}' found with ID '${tgt_id}'."
#
# 1b) if target doesn't exist we create one
#
else
    print_msg "Creating a target with name '${TARGET_NAME}'..."
    tar_params="{\"name\": \"${TARGET_NAME}\",\"environmentId\": \"${INTEGRATION_ID}\",\"environmentType\": \"${INTEGRATION_TYPE}\",\"tags\":[${TARGET_TAGS}],\"parameters\": {}}"
    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "${tar_params}" "${URL_ROOT}/targets")
    #
    # Extract the target ID from the response--needed for the next step.
    #
    tgt_id=$(echo ${result} | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Target '${TARGET_NAME}' created with ID '${tgt_id}'."
fi

# Check if target was created
if [ $tgt_id == "{" ]; then
    print_msg "Target look-up/creation failed!!! Exiting."; exit 1
fi

########################################################################
# The below code does the following:
# 2a) Look up the Policy based on the specified Policy Name.
# 2b) Create the Policy based on the specified Scenario ID and
#     the specified Policy Name.
########################################################################
#
# 2a) Check to see if a Policy by same name exists
#
# URL encode POLICY_NAME
encode_POLICY_NAME=$(echo ${POLICY_NAME} | sed 's|:|%3A|g' | sed 's|/|%2f|g' | sed 's| |%20|g')
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/?name=${encode_POLICY_NAME}")

# How many matching policies?
pol_count=$(echo ${result} | sed 's/^.*\"count\"://' | sed 's/\,.*$//')
# more than 1, die
if [ $pol_count -gt 1 ]; then
    print_msg "Found multiple matches for the Policy Name '${POLICY_NAME}'!!! Exiting."; exit 1
# exactly 1, we can use it
elif [ $pol_count -eq 1 ]; then
    pol_id=$(echo ${result} | sed 's/,\"customerId\":.*$//' | sed 's/^.*\"id\":\"//' | sed 's/\".*$//')
    print_msg "Policy '${POLICY_NAME}' found with ID '${pol_id}'."

# 2b) if the policy doesn't exist we create one
else
    print_msg "Creating a policy with name '${POLICY_NAME}'..."

    if [ "$POLICY_TYPE" == "manualUpload" ]; then
        pol_parms="{\"name\": \"${POLICY_NAME}\",\"environmentId\": \"${INTEGRATION_ID}\",\"environmentType\": \"${INTEGRATION_TYPE}\",\"targets\": [{\"id\": \"${tgt_id}\"}],\"policyType\": \"${POLICY_TYPE}\",\"policySite\": \"manual\",\"scenarioIds\": [\"${SCENARIO_ID}\"],\"description\": \"${POLICY_DESCRIPTION}\"}"
    elif [ "$POLICY_TYPE" == "dataLoad" ] && [ "$SCENARIO_TYPE" == "sonarqube" ]; then
        custom_parm="{"projectName": \"${SQ_PROJECT_NAME}\"},"projectKey": \"${SQ_PROJECT_KEY}\",\"sonarqubeApplicationLookupType\": \"byKey\"}"
        pol_parms="{\"name\": \"${POLICY_NAME}\",\"environmentId\": \"${INTEGRATION_ID}\",\"environmentType\": \"${INTEGRATION_TYPE}\",\"targets\": [{\"id\": \"${tgt_id}\"}],\"policyType\": \"${POLICY_TYPE}\",\"scenarioIds\": [\"${SCENARIO_ID}\"],\"description\": \"${POLICY_DESCRIPTION}\",\"permanentRunOptions\":${custom_parm}}"
    else
        print_msg "Error: This script does not support creating this type of Policy."
        print_msg "Exiting!"; exit 1
    fi

    result=$(curl -s -X POST --header "${HEADER_CONTENT_TYPE}" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" -d "${pol_parms}" "${URL_ROOT}/policies")

    #
    # Extract the policy ID from the response--and print it as output.
    #
    pol_id=$(echo ${result} | sed 's/^{\"id\":\"//' | sed 's/\".*$//')
    print_msg "Policy '${POLICY_NAME}' created with ID '${pol_id}'."
    
    # Check if policy was created
    if [ $pol_id == "{" ]; then
        print_msg "Policy look-up/creation failed!!! Exiting."; exit 1
    fi

fi

POLICY_ID="${pol_id}"

########################################################################
# The below code does the following:
# 3a) Run Policy
# 3b) Post issues to ZeroNorth
# 3c) Resume the job to let it finish.
# 3d) Loop, checking for the job status every 3 seconds.
########################################################################
print_msg "Running policy ${POLICY_NAME}:${POLICY_ID}"

########################################################################
# 3a) Run the specified Policy. This creates a Job that will be in the
#    "PENDING" status, which means the job is waiting for issues to be
#    uploaded.
########################################################################
result=$(curl -s -X POST --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/policies/${POLICY_ID}/run")

# Extract the Job ID from the response. It's needed it in the next step.
job_id=$(echo ${result} | sed 's/^.*jobId\":\"//' | sed 's/\".*$//')


if [ "$POLICY_TYPE" == "dataLoad" ]; then
    print_msg "Started DataLoad Job ID: '${job_id}'."
    print_msg "Done."; exit
fi

print_msg "Job ID: '${job_id}'."
########################################################################
# 3b) Post issues to ZeroNorth
########################################################################
print_msg "Uploading the result file..."
#result=$(curl -X POST --header "Content-Type: multipart/form-data" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" --form "file=@${DATA_FILE}" "${URL_ROOT}/common/2/issues/${job_id}")
result=$(curl -X POST --header "Content-Type: multipart/form-data" --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" --form "file=@${DATA_FILE}" "${URL_ROOT}/onprem/issues/${job_id}")
# echo "${result}"

########################################################################
# 3c) Resume the job to let it finish.
########################################################################
print_msg "Resuming Job to finish the process..."
sleep 3
result=$(curl -X POST --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${job_id}/resume")

########################################################################
# 3d) Loop, checking for the job status every 3 seconds.
########################################################################
while :
do
   result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH}" "${URL_ROOT}/jobs/${job_id}")
   JOB_STATUS=$(echo ${result} | sed 's/^.*\"status\":\"//' | sed 's/\".*$//')

   if [ "${JOB_STATUS}" == "RUNNING" ]; then
      print_msg "Job '${job_id}' still running..."
   elif [ "${JOB_STATUS}" == "PENDING" ]; then
      print_msg "Job '${job_id}' still in PENDING state..."
   else
      break
   fi
   sleep 3
done

########################################################################
# The End
########################################################################
print_msg "Done."

if [ -n "${verbose}" ]; then
    set +xv
fi