#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., support@zeronorth.io
#
# Script to clean up "Excited" zeronorth docker containers and defunct
# images.
#
# NOTE: Sometimes, a container can get "Created", but remains in that
#       state. This is rare, but if you see them, you can also use the
#       docker container rm -f <container id> command to clean them up.
########################################################################

########################################################################
# First, clean up the spent containers.
########################################################################
echo "================================================================"
result=$(docker container ls -a | egrep -w '(zeronorth|python cybric.py)' | grep -w 'Exited')

if [ "$result" ]; then
    echo "The current list of spent 'zeronorth' containers is:"
    echo "----------------------------------------------------------------"
    echo "$result"
    echo "----------------------------------------------------------------"
    echo "Cleaning containers..."
    echo "$result" | cut -d ' ' -f 1 | xargs docker container rm -f
    echo "Finished cleaning containers."
else
    echo "No containers to clean up."
fi


########################################################################
# Next, clean up the defunct images.
########################################################################
echo "================================================================"
result=$(docker image ls -a | grep -w 'zeronorth' | grep -w '<none>')

if [ "$result" ]; then
    echo "The current list of defunct 'zeronorth' images is:"
    echo "----------------------------------------------------------------"
    echo "$result"
    echo "----------------------------------------------------------------"
    echo "$result" | while read i_name i_status i_id i_misc
    do
        echo "Cleaning image with ID '${i_id}'..."
        docker image rm -f "${i_id}"
    done
    echo "Finished cleaning images."
else
    echo "No images to clean up."
fi

echo "================================================================"
echo "Done."
