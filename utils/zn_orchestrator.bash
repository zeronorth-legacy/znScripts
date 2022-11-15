#!/bin/bash
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., support@zeronorth.io
#
# A convenience script to launch the ZeroNorth Integration Orchestrator
# Docker container in the background. STDOUT will default to the current
# TTY. Requires SUDO on most Linux platforms.
#
# Input: path to the env.local
#
# The env.local file is a small configuration file used by the ZeroNorth
# Integration Orchestrator container. It should contain the following
# information:
#
# CYBRIC_JWT=<CYBRIC API Token>
# CYBRIC_VERIFY_SSL=1 (optional, defaults to "1")
# DOCKER_HUB_USERNAME=<docker hub username>
# DOCKER_HUB_PASSWORD=<docker hub password>
# 
# When the Docker Hub creds are omitted, the necessary Docker images
# must have been pulled down to the local Docker repository in advance.
# The ZeroNorth Docker image for the Integration Orchestrator is not
# public and requires privileges granted by support@zeronorth.io.
#
# See the follwoing ZeroNorth KB article for more details:
#
#   https://support.zeronorth.io/hc/en-us/articles/360000955654
#
# Optionally, to perform onprem repo scans, the host must have a folder
# named /shared (at the root folder level), which must have permissions
# set to 777 (-rwxrwxrwx). In CYGWIN, this folder needs can be created
# on demand, by means of a user prompt to allow the Docker Desktop to
# to create/mount this volume as needed.
########################################################################
# What this script does:
# 1) Check to ensure that the specified env_file is valid.
# 2) Check the OS platform. Windows platforms are not supported.
# 3) Check the Docker environment: Docker client, Docker server
# 4) Check egress access to Docker Hub and ZeroNorth API. See the CONSTANTS
#    section of this script for the remote endpoints.
# 5) Check for local mount points that may be needed (e.g. /shared,
#    which is needed for repo and artifact scans).
# 6) Check to see if another Integration Orchestrator is running. This
#    may be OK if the other instance(s) is(are) running against another
#    account.
# 7) Try to pull the latest copy of the Docker image. Failure may be OK
#    if there is an image locally already.
# 8) Launch the ZeroNorth Integration Orchestrator.
#
# This script uses curl to check egress access in step 4. If running in
# an environment that requires egress via a proxy server that injects an
# interim TLS/SSL cert, the curl test may succeed, but the ZeroNorth
# Docker container may still have trouble with egress. In such a case,
# it will be necessary to completely white list egress access to the
# endpoints list in the "CONSTANTS" section seen below.
########################################################################
myname="`basename $0`"

########################################################################
# CONSTANTS
########################################################################
ZN_API_URL="https://api.zeronorth.io/v1"
DOC_FORMAT="application/json"
HEADER_CONTENT_TYPE="Content-Type: ${DOC_FORMAT}"
HEADER_ACCEPT="Accept: ${DOC_FORMAT}"

DOCKER_URL="https://registry-1.docker.io"
DOCKER_IMG="zeronorth/integration-orchestrator"
DOCKER_TAG=":latest"

SHARE_DIR="/shared"


########################################################################
# Functions to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}

function print_warn {
    echo "`date +'%Y-%m-%d %T'`  WARNING  $1"
}

function print_err {
    echo "`date +'%Y-%m-%d %T'`  ERROR  $1" >&2
}


########################################################################
# Read and validate input params.
########################################################################
if [ ! "$1" ]; then
   echo "
Usage:

    [sudo] $myname [NOEXEC] [AUTO_CLEAN] <env file>

  where,

  NOEXEC, if provided as the first parameter will cause this script to print
  the Docker command it will run, but not actually start the Docker container,
  a dry-run, in other words.

  AUTO_CLEAN, if provided as an optiona parameter, will cause this script to
  to into a loop, after launching the Integration Orchestrator, periodically
  cleaning out the contents of the $SHARE_DIR folder if one is found. temporary
  folder under $SHARE_DIR older than 1 day are cleaned out every hour.

  <env file> is, a small configuration file used by the ZeroNorth Integration
  Orchestrator container. It should contain the following information:

  CYBRIC_JWT=<CYBRIC API Token>
  CYBRIC_VERIFY_SSL=1 (optional, defaults to "1")
  DOCKER_HUB_USERNAME=<docker hub username>
  DOCKER_HUB_PASSWORD=<docker hub password>

  The use of 'sudo' to run this script will depend on your Docker environment.
  In most Unix/linux-based systems, it will be necessary unless you are using
  an account that is a member of the 'Docker' group. On a Mac, this is usually
  not needed. On Windows, if not using an account that belongs to the docker
  user group, then this script needs to be run as administrator.
" >&2
   exit 1
fi

if [ "$1" == "NOEXEC" ]
then
    NOEXEC=1
    shift
    print_msg "Running in 'noexec' mode. No Docker container will be run."
else
    NOEXEC=''
fi

if [ "$1" == "AUTO_CLEAN" ]
then
    AUTO_CLEAN=1
    shift
    print_msg "'AUTO_CLEAN' option selected. Will perform hourly purge of content older than 1 day in '$SHARE_DIR'."
else
    AUTO_CLEAN=''
fi

ENV_FILE="$1"

if [ ! -r "$ENV_FILE" ]; then
    print_err "Env file '$ENV_FILE' does not exist or is not readable!

Refer to the follwoing ZeroNorth KB article for instructions:

    https://support.zeronorth.io/hc/en-us/articles/360000955654

Exiting."
    exit 1
fi


########################################################################
# Check the OS. This script supports Linux/Unix, MacOS, and CYGWIN.
########################################################################
print_msg "Checking OS..."

u=$(uname)
cygwin=""

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
    cygwin=1
    # For CYGWIN, ENV_FILE path needs to be edited...
    ENV_FILE=$(echo "$ENV_FILE" | sed 's/^\/cygdrive//')
    print_msg "ENV_FILE edited as '$ENV_FILE'."
    [ $AUTO_CLEAN ] && print_warn "AUTO_CLEAN option will be ignored."
else
    print_err "Unsupported OS '$u'. Exiting."
    exit 1
fi


########################################################################
# Check for presence of Docker.
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
# Check egress access to resources like Docker Hub and ZeroNorth API.
########################################################################
# Check for ZeroNorth API access
print_msg "Checking access to $ZN_API_URL..."
result=$(curl -S $ZN_API_URL 2>/dev/null)
if [ $? -gt 0 ]; then
    print_err "Can't connect to the ZeroNorth API at $ZN_API_URL! Exiting."
    exit 1
fi
print_msg "Verified access to $ZN_API_URL."

# Check for Docker Hub access
print_msg "Checking access to $DOCKER_URL..."
result=$(curl -S $DOCKER_URL 2>/dev/null)
if [ $? -gt 0 ]; then
    print_err "Can't connect to Docker Hub at $DOCKER_URL! Exiting."
    exit 1
fi
print_msg "Verified access to $DOCKER_URL."


########################################################################
# Check for presence of and writability into /shared.
########################################################################

if [ ! "$cygwin" ]; then
    print_msg "Checking for the recommended directory '$SHARE_DIR'..."

    # Is the directory there?
    if [ -x "$SHARE_DIR" ] && [ -w "$SHARE_DIR" ]; then
        print_msg "Recommended directory '$SHARE_DIR' verified."
    else
        print_warn "The recommended directory '$SHARE_DIR' does not exist or is not correctly defined. This will prevent the Integration Orchestrator from facilitating certain types of scans such as on-prem repo or artifact scans."
        # Unset SHARE_DIR so that we don't try to use it later.
        SHARE_DIR=""
        [ $AUTO_CLEAN ] && print_warn "AUTO_CLEAN option will be ignored."
    fi
fi

########################################################################
# Is there an Integration Orchestrator already running? We can only have
# one per ZeroNorth customer account.
########################################################################
result=$(docker ps | grep "$DOCKER_IMG" | wc -l)

if [ $result -gt 0 ]; then
    if [ $result -eq 1 ]; then
        print_warn "There is another Integration Orchestrator running already."
    else
        print_warn "There are other Integration Orchestrators running already."
    fi
fi


########################################################################
# Try to pull the latest image just to be sure. If this fails, it might
# still be OK if the image is already on the local Docker environment.
########################################################################
print_msg "Pulling latest available '${DOCKER_IMG}${DOCKER_TAG}'..."
docker pull "${DOCKER_IMG}${DOCKER_TAG}"
[ $? -gt 0 ] && print_warn "Unable to pull ${DOCKER_IMG}${DOCKER_TAG}.
Do you need to do 'docker login'? I might run into problems otherwise."


########################################################################
# Finally, run the Docker container.
# We don't run it as sudo. We leave that to the caller of this script.
#
# The bindmount for "/shared" is needed ONLY if using the I-O do perform
# onprem repo (e.g. GitHub, Bitbucket) scans.
########################################################################
print_msg "Launching Docker container '${DOCKER_IMG}${DOCKER_TAG}'..."

# Conditionally construct the parameters.
params="-v /var/run/docker.sock:/var/run/docker.sock --env-file "$ENV_FILE" "${DOCKER_IMG}${DOCKER_TAG}" /app/run.sh"
[ "$SHARE_DIR" ] && params="-v /shared:/shared $params"

if [ "$NOEXEC" ]
then
    print_msg "========== ZeroNorth Integration orchestrator command is: =========="
    echo
    echo "docker run $params &"
    echo
    exit
else
    print_msg "========== ZeroNorth Integration orchestrator output below =========="
    echo
    docker run $params &
fi


########################################################################
# Did it work?
########################################################################
if [ $? -gt 0 ]; then
    print_err "Problem launching Docker container ${DOCKER_IMG}${DOCKER_TAG}!"
    exit 1
fi

# Get the container ID. No container ID could also mean a problem.
# BUG: The following code could run into RACE conditions.
sleep 10
result=$(docker ps | grep "${DOCKER_IMG}${DOCKER_TAG}" | head -1 | cut -d ' ' -f 1)

# Still don't see the container ID, a problem.
if [ ! "$result" ]; then
    print_err "Problem launching Docker container ${DOCKER_IMG}${DOCKER_TAG}!"
    exit 1
fi

print_msg "Docker container successfully launched with container id [$result]."


########################################################################
# Optionally, go into a loop to clean /shared if asked. This loop will
# exit when it detects that there are no more Integration Orchestrators
# running.
#
# BUG: because the sleep loop is 1 hour, if the I-O is stopped by the
#      user and then restarted by another instance of this script, you
#      could end up with more than one copy of this script running the
#      below looping logic.
########################################################################
while [ $SHARE_DIR ] && [ $AUTO_CLEAN ]; do
    print_msg "AUTO_CLEAN: Looking for 1-day old (or older) content to clean out of '$SHARE_DIR'..."

    folders=$(find $SHARE_DIR/* -not -path $SHARE_DIR/customer_artifacts -d 0 -mtime 1)

    if [ "$folders" ]; then
        print_msg "AUTO_CLEAN: Found content to clean:"; echo "$folders"
        echo "$folders" | xargs rm -rf
    else
        print_msg "AUTO_CLEAN: Nothing to clean."
    fi
 
    print_msg "AUTO_CLEAN: Going into sleep for one hour..."
    sleep 3600

    # Check to see if the I-O is still running. Break out of the loop if not.
    result=$(docker ps | grep "${DOCKER_IMG}${DOCKER_TAG}" | head -1 | cut -d ' ' -f 1)
    if [ ! "$result" ]; then
        print_msg "AUTO_CLEAN: ${DOCKER_IMG}${DOCKER_TAG} not running anymore. Exiting."
        break
    fi
done
