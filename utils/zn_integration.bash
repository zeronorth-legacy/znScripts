#!/bin/bash
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# A convenience script to run the ZeroNorth Integration Docker container
# to perform orchestrated scans of local application artifacts. To use
# this script for data loads, specify an empty folder (e.g. /tmp/dummy)
# as the app path. Handles both SaaS and On-prem Policies.
#
# This script is provided as an example. The user is free to modify the
# script. This script comes with absolutely no warranties.
#
# Inputs (positional parameters):
# - policy id
# - code/build path
# - api-key file path (optional, see below for other options)
#
# Requires:
# - SUDO on most Linux platforms
# - curl
#
########################################################################
#
# What this script does:
# 1) Check the OS platform. Windows platforms are not supported.
# 2) Check the Docker environment: Docker client, Docker server
# 3) Check egress access to Docker Hub and ZeroNorth API. See the CONSTANTS
#    section of this script for the remote endpoints.
# 4) Looks up the specified Policy by ID to ensure that it exists. If
#    the Policy is an onprem scan, this script will adjust the Docker
#    parameters accordingly.
# 5) Try to pull the latest copy of the Docker image. Failure may be OK
#    if there is an image locally already.
# 6) Run the ZeroNorth Integration container.
#
########################################################################
#
# Before using this script, obtain your API key using the instructions
# outlined in the following KB article:
#
#   https://support.zeronorth.io/hc/en-us/articles/115003679033
#
# The API key can then be used in one of the following ways:
# 1) Stored in secure file and then referenced at run time. Use this
#    option if you are running this script via SUDO.
# 2) Set as the value to the environment variable API_KEY.
# 3) Set as the value to the variable API_KEY within this script.
#
# IMPORTANT: An API key generated using the above method has life span
# of 10 calendar years.
#
########################################################################
# Uncomment the line below if you are using option 3 from above.
#API_KEY="....."

########################################################################
# CONSTANTS
########################################################################
ENV=io		# can be "io" or "dev", customers should use "io"

DOCKER_URL="https://registry-1.docker.io"
DOCKER_IMG="zeronorth/integration"
DOCKER_TAG=":latest"

API_URL="https://api.zeronorth.${ENV}/v1"
UPLOAD_URL="https://uploads.zeronorth.${ENV}"

DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"
HEADER_AUTH="Authorization:"

[ "${TEMP}" ] && TEMP_DIR="${TEMP}" || TEMP_DIR="/tmp"


########################################################################
# Functions to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  INFO: $1"
}

function print_warn {
    echo "`date +'%Y-%m-%d %T'`  WARNING: $1"
}

function print_err {
    echo "`date +'%Y-%m-%d %T'`  ERROR: $1" >&2
}


########################################################################
# Read and validate input params.
########################################################################
if [ ! "$2" ]
then
    echo "
Usage: `basename $0` [NOEXEC] <policy ID> <app path> [<key file>]

where,

  NOEXEC      If specified as the first parameter, the script will print
              out the Docker command it will execute, but actually run
              the Docker command. A dry-run, essentially. This feature is
              useful to learn what ZeroNorth Docker command is composed.

  <policy ID> ID of the ZeroNorthh scan Policy, which you can obtain from
              the UI (https://fabric.zeronorth.io)

  <app path>  The fully qualified path to the folder that contains the 
              application code/build to be scanned. If the Policy is for
              a data load, then this path can be anything (e.g. "dummy").

  <key file>  Optionally, the path to the file that contains the API Key.
              If omitted, will use the value in the API_KEY variable,
              which can be supplied as an environment variable or be set
              inside the script. If you are executing this script via
              SUDO, use must the key file method.
" >&2
   exit 1
else
    if [ "$1" == "NOEXEC" ]
    then
        NOEXEC=1
        shift
        print_msg "Running in 'noexec' mode. No scan will be run."
    else
        NOEXEC=''
    fi

    POLICY_ID="$1"; shift
    print_msg "Policy ID: '${POLICY_ID}'"
    APP_PATH="$1"; shift
    print_msg "App path: '${APP_PATH}'"
fi

#
# API Key
#
# Was the name of the file passed in as a parameter?
[ "$1" ] && API_KEY=$(cat "$1")

# Is it in a file?
[ -f "${API_KEY}" ] && [ -r "${API_KEY}" ] && API_KEY=$(cat "${API_KEY}")

# Still don't have an API_KEY value, problem.
if [ ! "$API_KEY" ]
then
    print_err "No API key provided! Exiting."
    exit 1
fi


########################################################################
# 1) Check the OS. This script supports Linux/Unix, MacOS, and CYGWIN.
########################################################################
print_msg "Checking OS..."

u=$(uname)

if [ "$u" == "Linux" ]; then
    print_msg "Running on Linux."
    # Additionally, if running on Linux, warn if not running as root.
    if [ "`id -un`" != "root" ]; then
        print_warn "Not running as root. If you encounter permission errors, try 'sudo $0 $*'."
    fi
elif [ "$u" == "Darwin" ]; then
    print_msg "Running on MacOS."
elif [[ "$u" =~ ^CYGWIN ]]; then
    print_msg "Running on CYGWIN."
    # For CYGWIN, APP_PATH needs to be edited...
    APP_PATH=$(echo "$APP_PATH" | sed 's/^\/cygdrive//')
    print_msg "APP_PATH edited as '$APP_PATH'."
else
    print_err "Unsupported OS '$u'! Exiting."
    exit 1
fi


########################################################################
# 2) Check for presence of Docker.
########################################################################
print_msg "Checking Docker environment..."

# Is there Docker client?
if [ ! -x "`which docker`" ]; then
    print_err "Docker not found or not in PATH! Exiting."
    exit 1
fi

# Is there Docker server?
result=$(docker -v)
if [ $? -gt 0 ]; then
    print_err "Docker not running or not installed! Exiting."
    exit 1
fi

print_msg "Docker environment seems good."


########################################################################
# 3) Check egress access to resources like Docker Hub and ZeroNorth API.
########################################################################
# Check for ZeroNorth API access
print_msg "Checking access to $API_URL..."
result=$(curl -S $API_URL 2>/dev/null)
if [ $? -gt 0 ]; then
    print_err "Can't connect to the ZeroNorth API at $API_URL! Exiting."
    exit 1
fi
print_msg "Verified access to $API_URL."

# Check for ZeroNorth API access
print_msg "Checking access to $UPLOAD_URL..."
result=$(curl -S $UPLOAD_URL 2>/dev/null)
if [ $? -gt 0 ]; then
    print_err "Can't connect to the ZeroNorth API at $UPLOAD_URL! Exiting."
    exit 1
fi
print_msg "Verified access to $UPLOAD_URL."

# Check for Docker Hub access
print_msg "Checking access to $DOCKER_URL..."
result=$(curl -S $DOCKER_URL 2>/dev/null)
if [ $? -gt 0 ]; then
    print_err "Can't connect to Docker Hub at $DOCKER_URL! Exiting."
    exit 1
fi
print_msg "Verified access to $DOCKER_URL."


########################################################################
# 4) Look up the Policy by ID to verify it exists.
########################################################################
#
# Look up the Policy by the ID.
#
result=$(curl -s -X GET --header "${HEADER_ACCEPT}" --header "${HEADER_AUTH} ${API_KEY}" "${API_URL}/policies/${POLICY_ID}")

# Extract the resulting policy ID
pol_id=$(echo ${result} | sed 's/^{\"id\":\"//' | sed 's/\".*$//')

if [ "${POLICY_ID}" == "${pol_id}" ]; then
    print_msg "Policy with ID '${POLICY_ID}' found."
else
    print_msg "No matching policy found! Exiting."
    exit 1
fi

# Is it an onprem Policy?
onprem=""
esite=$(echo ${result} | sed 's/^.*\"site\":\"//' | sed 's/\".*$//')
[ "$esite" == "onprem" ] && onprem="onprem"
psite=$(echo ${result} | sed 's/^.*\"policySite\":\"//' | sed 's/\".*$//')
[ "$psite" != '{' ] && [ "$psite" == "onprem" ] && onprem="onprem"
[ "$psite" != '{' ] && [ "$psite" == "cybric" ] && onprem=""
#echo "$onprem"

if [ "$onprem" == "onprem" ]; then
    print_msg "Looks like an onprem scan."
else
    onprem=''
fi


########################################################################
# 5) Try to pull the latest image. If this fails, it might still be OK
# if the image is already on the local Docker environment.
########################################################################
print_msg "Pulling latest available '${DOCKER_IMG}${DOCKER_TAG}'..."
docker pull "${DOCKER_IMG}${DOCKER_TAG}"
[ $? -gt 0 ] && print_warn "Unable to pull ${DOCKER_IMG}${DOCKER_TAG}.
I hope you have a local copy. I might run into problems otherwise."

# Room for improvement - If the Policy is an onprem scan, then we could
# try to pull the necessary runner automatically. The name of the runner
# can be determined from the product configuration details, which is
# available in the Policy details extracted during the Policy lookup.

########################################################################
# 6) Finally, run the Docker container.
# We don't run it as sudo. We leave that to the caller of this script.
########################################################################
print_msg "Running Docker container '${DOCKER_IMG}${DOCKER_TAG}'..."

# Conditionally construct the onprem parameters.
onprem_params=''
[ "$onprem" ] && onprem_params="-v /var/run/docker.sock:/var/run/docker.sock -e WORKSPACE=${APP_PATH} -e DEBUG=1"

# Construct the full params, including the onprem params if applicable.
params="${onprem_params} -v ${APP_PATH}:/code -v ${TEMP_DIR}:/results -e POLICY_ID=${POLICY_ID} -e SONAR_JAVA_BINARY_DIR='.' -e SONAR_JAVA_LIBRARY_DIR='.'"
[ "${ENV}" == "dev" ] && params="-e CYBRIC_ENVIRONMENT=development $params"

if [ "$NOEXEC" ]
then
    print_msg "========== ZeroNorth Integration container command is: =========="
    echo
    echo "docker run $params -e CYBRIC_API_KEY=<API_KEY_here> ${DOCKER_IMG}${DOCKER_TAG} python cybric.py"
    echo
else
    print_msg "========== ZeroNorth Integration container output below =========="
    echo
    docker run $params -e CYBRIC_API_KEY=${API_KEY} ${DOCKER_IMG}${DOCKER_TAG} python cybric.py
fi

# We don't do anything else here so that the exit status from the docker
# run command is provided as the exit status for this script.
