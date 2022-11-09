#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., support@zeronorth.io
#
# Script to refresh all local zeronorth container images.
#
# This script assumes that the user has a docker user name that has been
# granted the necessary pivileges to pull the zeronorth docker images,
# and that the user has done "docker login" locally as needed. Contact
# support@zeronorth.io for access to the zeronorth docker images.
########################################################################

########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $1"
}


########################################################################
# List the local zeronorth docker images and refresh each via a pull.
########################################################################
result=$(docker image ls -a | egrep '^zeronorth/' | grep -vw '<none>')
count=$(echo "$result" | wc -l | xargs)

echo '========================================================='
print_msg "Found $count zeronorth Docker images locally."

if [ "$count" -gt 0 ]; then
    echo "$result" | while read i_name i_tag i_id i_misc
    do
        echo '---------------------------------------------------------'
        print_msg "Refreshing image '${i_name}:${i_tag}'..."
        docker pull ${i_name}:${i_tag}
    done
    echo '========================================================='
else
    print_msg "No images to refresh."
fi


########################################################################
# Examine the list of Docker images to see if the refreshing resulted in
# stale images, those with the tag "<none>".
########################################################################
result=$(docker image ls -a | egrep '^zeronorth/' | grep -w '<none>')
count=$(echo "$result" | egrep -v '^$' | wc -l | xargs)

if [ "$count" -gt 0 ]; then
    print_msg "Found $count stale zeronorth Docker images:"

    echo "IMAGE ID     IMAGE NAME:TAG"
    echo "$result" | while read i_name i_tag i_id i_misc
    do
        echo "${i_id} ${i_name}:${i_tag}"
    done
    print_msg "Remove these manually, or use zn_docker_clean.bash."
    echo '========================================================='
fi


########################################################################
# DONE
########################################################################
print_msg "DONE."
