#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to translate Snyk SAST results file in SARIF format to the
# ZeroNorth JSONv2 format.
#
# Requires: jq
# Resource: create 3 temporary files, which are deleted automatically
#           upon successful completion, but remains if error.
#
########################################################################
MY_NAME=`basename $0`
MY_DIR=`dirname $0`


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg {
    echo "`date +'%Y-%m-%d %T'`  $MY_NAME  $1" >&2
}


########################################################################
# Print the help info.
########################################################################
if [ ! "$1" ]
then
    echo "
Script to translate Snyk SAST results file in SARIF format to the ZeroNorth
JSONv2 format. Requires jq.


Usage: $MY_NAME <input file>

where,

  <input file>  - The path to the input JSON file. The input JSON file must be
                  a Snyk SAST output file in SARIF format containing results of
                  only one scan.


Examples:

  $MY_NAME my_snyk_sarif.json
" >&2
    exit 1
fi

# Read in the Target ID.
IN_FILE="$1"; shift
if [ ! -f "$IN_FILE" ]; then
    print_msg "ERROR: file '$IN_FILE' cannot be found. Exiting."
    exit 1
fi
print_msg "Input file is '$IN_FILE'."


########################################################################
# Prep.
########################################################################

# Find a suitable working directory
[ "${TEMP}" ] && TEMP_DIR="${TEMP}" || TEMP_DIR="/tmp"

# Prepare the temporary work files.
TEMP_RULES_FILE="${TEMP_DIR}/zn_sarif_rules.`date '+%s'`.tmp"
TEMP_RESULTS_FILE="${TEMP_DIR}/zn_sarif_results.`date '+%s'`.tmp"
TEMP_JOINED_FILE="${TEMP_DIR}/zn_sarif_joined.`date '+%s'`.tmp"


########################################################################
# 1) Extract the rules[] section.
########################################################################
jq '.runs[0].tool.driver.rules' "$IN_FILE" | sed 's/\"id\"/\"ruleId\"/g' > "$TEMP_RULES_FILE"

if [ $? -gt 0 ]; then
    print_msg "ERROR while extracting the rules[] section from the input file. Exiting."
    exit 1
fi


########################################################################
# 2) Extract the results[] section.
########################################################################
jq '.runs[0].results' "$IN_FILE" > "$TEMP_RESULTS_FILE"

if [ $? -gt 0 ]; then
    print_msg "ERROR while extracting the results[] section from the input file. Exiting."
    exit 1
fi


########################################################################
# 3) Merge the rules and the results files.
########################################################################
#
# The joins.jq script below is courtesy of
#  https://stackoverflow.com/questions/49037956/how-to-merge-arrays-from-two-files-into-one-array-with-jq
#
jq -s '
# joins.jq Version 1 (12-12-2017)

def distinct(s):
  reduce s as $x ({}; .[$x | (type[0:1] + tostring)] = $x)
  |.[];

def joins(s1; s2; filter1; filter2; p1; p2):
  def it: type[0:1] + tostring;
  def ix(s;f):
    reduce s as $x ({};  ($x|f) as $y | if $y == null then . else .[$y|it] += [$x] end);
  # combine two dictionaries using the cartesian product of distinct elements
  def merge:
    .[0] as $d1 | .[1] as $d2
    | ($d1|keys_unsorted[]) as $k
    | if $d2[$k] then distinct($d1[$k][]|p1) as $a | distinct($d2[$k][]|p2) as $b | [$a,$b]
      else empty end;

   [ix(s1; filter1), ix(s2; filter2)] | merge;

def joins(s1; s2; filter1; filter2):
  joins(s1; s2; filter1; filter2; .; .) | add ;

# Input: an array of two arrays of objects
# Output: a stream of the joined objects
def joins(filter1; filter2):
  joins(.[0][]; .[1][]; filter1; filter2);

# Input: an array of arrays of objects.
# Output: a stream of the joined objects where f defines the join criterion.
def joins(f):
  # j/0 is defined so TCO is applicable
  def j:
    if length < 2 then .[][]
    else [[ joins(.[0][]; .[1][]; f; f)]] + .[2:] | j
    end;
   j ;

[joins(.ruleId)]
' "$TEMP_RULES_FILE" "$TEMP_RESULTS_FILE" > "$TEMP_JOINED_FILE"

if [ $? -gt 0 ]; then
    print_msg "ERROR while merging the rules[] and the results[] sections. Exiting."
    exit 1
fi


########################################################################
# 4) Translate the merged file to JSONv2.
########################################################################
jq '
{
  "meta": {
    "key": [ "ruleId" ],
    "author": "support@zeronorth.io"
  },
  "issues": [
    .[] |
    {
      "scanTool": "Snyk SAST",
      "ruleId": .ruleId,
      "issueName": .shortDescription.text,
      "issueDescription": .message.markdown,
      "fileName": .locations[0].physicalLocation.artifactLocation.uri,
      "lineNumber": (.locations[0].physicalLocation.region.startLine|tostring),
      "remediationSteps": .help.markdown,
      "severity": (if   ."level"=="error"    then
                     8
                   elif ."level"=="warning"  then
                     6
                   elif ."level"=="note"     then
                     3
                   else
                     1
                   end),
      "referenceIdentifiers": [
        .properties.cwe[] |
        {
          "type": "cwe",
          "id": (.|split("-")|.[1])
        }
      ]
    }
  ]
}' "$TEMP_JOINED_FILE"

if [ $? -gt 0 ]; then
    print_msg "ERROR while translating to JSONv2. Exiting."
    exit 1
fi


########################################################################
# Clean up the temporary files.
########################################################################
[ "${TEMP_RULES_FILE}" ] && [ -w ${TEMP_RULES_FILE} ] && rm "${TEMP_RULES_FILE}" && print_msg "Temp file '${TEMP_RULES_FILE}' removed."
[ "${TEMP_RESULTS_FILE}" ] && [ -w ${TEMP_RESULTS_FILE} ] && rm "${TEMP_RESULTS_FILE}" && print_msg "Temp file '${TEMP_RESULTS_FILE}' removed."
[ "${TEMP_JOINED_FILE}" ] && [ -w ${TEMP_JOINED_FILE} ] && rm "${TEMP_JOINED_FILE}" && print_msg "Temp file '${TEMP_JOINED_FILE}' removed."


########################################################################
# The End
########################################################################
print_msg "DONE."
