#!/bin/bash
########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2018-Dec, support@zeronorth.io
# 
# A simple script to extract the app_id and the latest build_id
# of an application by the specified name.
#
# Inputs:
# - Application name in Veracode
# - path to the file that contains the credentials. The file must have
#   content just like this:
#
#   <api_user>:<api_user_password/key>
#
#   Just that one line.
#
# Output: Prints a single line consisting of the app_id and the build_id
#         separated by white space. If no matching app is found, prints
#         nothing. If no build is found, prints just the app_id.
########################################################################

########################################################################
# Constants
########################################################################
V_URL="https://analysiscenter.veracode.com/api/5.0"


########################################################################
# 0) Read the input
########################################################################
if [ ! "$2" ]
then
    echo "
Usage: `basename $0` <app name> <creds file>

  Example: `basename $0` 'MyApplication' MyCredsFile

where,
  <app name>   - The name of the app in Veracode. Case sensitive. This
                 script will do an exact match, not a prefix match. It
                 may be necessary to enclose the app name in double or
                 single quotes if the name contains special characters.

  <creds file> - Path to the file that contains the Veracode credentials.
                 The file must have exactly one line that look like:

                 <api_user>:<api_user_password/key>
" >&2
    exit 1
else
    APP_NAME="$1"; shift
    CREDS=$(cat "${1}"); shift
fi


#set -xv
########################################################################
# 1) Obtain the app_id
########################################################################
app_id=$(curl -s -u "$CREDS" ${V_URL}/getapplist.do | grep '"'"$APP_NAME"'"' | sed 's/^.*app_id=\"//' | sed 's/\".*$//')

########################################################################
# 2) Obtain the latest build_id
########################################################################
build_id=$(curl -s -u "$CREDS" ${V_URL}/getbuildlist.do -F "app_id=${app_id}" | grep '<build build_id=' | tail -1 | sed 's/^.*<build build_id=\"//' | sed 's/\".*$//')

########################################################################
# Print the results
########################################################################
echo $app_id $build_id
