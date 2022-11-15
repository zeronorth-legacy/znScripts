#!/bin/bash
#set -xv
########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to inventory all Policies for a particular Product ID.
#
# Requires curl, jq, zn_utils.bashrc
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
#
# IMPORTANT: An API key generated using the above method has life span
# of 10 calendar years.
#
########################################################################
. `dirname $0`/zn_utils.bashrc


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if [ ! "$1" ]
then
    echo "
Script to inventory all Policies for a particular Product ID.


Usage: `basename $0` <product ID|ALL> [<key_file>]

where,

  <product ID>   - The ID of the product whose activated Scenario you want
                   to list. Specify 'ALL' to list all Scenarios.

  <key_file>     - Optionally, the file with the ZeroNorth API key. If not
                   provided, will use the value in the API_KEY environment
                   variable.


  Example: $MY_NAME JFhoWL02QrmXG8C3ERKlZh
           $MY_NAME JFhoWL02QrmXG8C3ERKlZh key_file
" >&2
    exit 1
fi


# Read in the Product ID / 'ALL'.
PROD_ID="$1"; shift
if [ "$PROD_ID" == "ALL" ]; then
    zn_print_info "All Scenarios will be listed."
else
    zn_print_info "Product ID: $PROD_ID"
fi

# Read in the API token.
[ "$1" ] && API_KEY=$(cat "$1")
if [ ! "$API_KEY" ]; then
    echo "No API key provided! Exiting."
    exit 1
fi


########################################################################
# Who is the customer?
########################################################################
cust_name=$(zn_customer_name) || exit 1


########################################################################
# Extract the list of Scenarios.
########################################################################
# Extract the Scenarios for the specified Product ID or for ALL.
params="?limit=1000"
[ "$PROD_ID" != "ALL" ] && params="${params}&productId=${PROD_ID}"
result=$(zn_get_obj_list scenarios "$params") || exit 1

# Extract the Scenarios list.
scns=$(jq -r '.[0][]
| "'"$cust_name"'"
+","+.id
+","+.data.product.name
+","+.data.productConfiguration.name
+","+.data.name
+","+(.meta.created | split(".") | .[0] | sub("T"; " ") )
' <<< "$result")

# Nothing to do.
if [ ! "$scns" ]; then
    zn_print_info "No matching Scenarios. Exiting."
    exit
fi

########################################################################
# Print the column headings.
########################################################################
echo "Customer,ScenarioID,Product,ProductConfig,ScenarioName,ScenarioCreated(UTC),PolicyID,PolicyName,PolicyType,PolicyCreated(UTC)"
#echo "$scns"


########################################################################
# List the Policies for each of the Scenarios. For each Policy, print
# some basic details.
########################################################################
while IFS="," read cust scn_id prod prod_cfg scn_name created
do
    # Look up the Policies for each scn_id
    params="?limit=4000"
    params="${params}&scenarioId=${scn_id}"
    result=$(zn_get_obj_list policies "$params") || exit 1

    # Extract the Policies list.
    pols=$(jq -r '.[0][]
| .id
+",\""+(.data.name | gsub("\"";"\"\""))
+"\","+.data.policyType
+","+(.meta.created | split(".") | .[0] | sub("T"; " ") )
' <<< "$result")

    # Print the output
    if [ ! "$pols" ]; then
        echo "$cust,$scn_id,$prod,$prod_cfg,$scn_name,$created"
    else
        while read pol
        do
            echo "$cust,$scn_id,$prod,$prod_cfg,$scn_name,$created,$pol"
        done <<< "$pols"
    fi

done <<< "$scns"


########################################################################
# Done.
########################################################################
zn_print_info "Done."
