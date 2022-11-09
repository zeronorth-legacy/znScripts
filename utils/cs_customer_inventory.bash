########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#      !!!!! THIS SCRIPT IS FOR ZERONORTH INTERNAL USE ONLY !!!!!
#
# A script to count activated objects in a customer account.
#
# Requires: curl, jq, sed, tr
#
########################################################################
MIN_TOKEN_LEN=1900
MAX_TOKEN_LEN=3000

# Pull in the ZN utlitlies library (expecteds in the same directory).
. `dirname $0`/zn_utils.bashrc

# This script cannot be run in "batch" mode.
[ ! "$TERM" ] && zn_print_fatal "You must run this script from a terminal."


########################################################################
# Help.
########################################################################
if [ ! "$1" ]; then
    echo "
A script to count activated objects in a customer account.


Usage: $MY_NAME [NO_HEADERS] <ALL> [<key_file>]


where,

  NO_HEADERS    - If specified, does not print field heading. This is used
                  by the amfam_get_all_wrapper.bash script, which prints
                  the heading before this script is called.

  ALL           - Required for safety.

  <key_file>    - Optionally, the file with the ZeroNorth API key. If not
                  provided, will use the value in the API_KEY variable,
                  which can be supplied as an environment variable or be
                  set inside the script.


  Examples:

    $MY_NAME ALL
    $MY_NAME ALL key_file
" >&2
    exit 1
fi


########################################################################
# Read in the command line parameters.
########################################################################
if [ "$1" == "NO_HEADERS" ]; then
    NO_HEADERS=1
    shift
fi

APP_ID="$1"; shift
if [ $APP_ID != "ALL" ]
then
    zn_print_fatal "You must specify 'ALL' as the first parameter. Exiting."
fi

[ "$1" ] && API_KEY=$(cat "$1")

if [ ! "$API_KEY" ]
then
    zn_print_fatal "No API key provided! Exiting."
fi


########################################################################
# Validate some more!
########################################################################
#
# Look up the customer account name.
#
cust_name=$(zn_customer_name) || zn_die
zn_print_info "Customer: '$cust_name'."


########################################################################
# Look up the objects and count them.
########################################################################
result=$(zn_get_obj_list applications "?limit=1") || zn_die
num_apps=$(jq -r '.[1].totalCount' <<< "$result")
echo "DEBUG: num_apps = '$num_apps'" >&2

result=$(zn_get_obj_list environments "?limit=1") || zn_die
num_envs=$(jq -r '.[1].totalCount' <<< "$result")
echo "DEBUG: num_envs = '$num_envs'" >&2

result=$(zn_get_obj_list policies "?limit=1") || zn_die
num_pols=$(jq -r '.[1].totalCount' <<< "$result")
echo "DEBUG: num_pols = '$num_pols'" >&2

result=$(zn_get_obj_list scenarios "?limit=1000") || zn_die
#num_prods=$(jq -r '.[0][].data.product.name' <<< "$result" | sort -u | wc -l)
#echo "DEBUG: num_prods = '$num_prods'" >&2

# For Scenarios, let's look deeper.
num_prods_oss=$(jq -r '.[0][] |
  select(
          .data.product.name == "aqua-trivy"
        or
          .data.product.name == "bandit"
        or
          .data.product.name == "brakeman"
        or
          .data.product.name == "burp"
        or
          .data.product.name == "docker-content-trust"
        or
          .data.product.name == "docker-image-scan"
        or
          .data.product.name == "nikto"
        or
          .data.product.name == "nmap"
        or
          .data.product.name == "openvas"
        or
          .data.product.name == "owasp"
        or
          .data.product.name == "zap"
        ) |
        .data.product.name
' <<< "$result" | sort -u | wc -l)
echo "DEBUG: num_prods_oss = '$num_prods_oss'" >&2

num_prods_comm=$(jq -r '.[0][] |
  select(
          .data.product.name == "app-scan"
        or
          .data.product.name == "aqua"
        or
          .data.product.name == "blackduckhub"
        or
          .data.product.name == "checkmarx"
        or
          .data.product.name == "coverity"
        or
          .data.product.name == "data-theorem"
        or
          .data.product.name == "external"
        or
          .data.product.name == "fortify"
        or
          .data.product.name == "fortifyondemand"
        or
          .data.product.name == "nessus"
        or
          .data.product.name == "nexusiq"
        or
          .data.product.name == "qualys"
        or
          .data.product.name == "redlock"
        or
          .data.product.name == "shiftleft"
        or
          .data.product.name == "snyk"
        or
          .data.product.name == "tenableio"
        or
          .data.product.name == "twistlock"
        or
          .data.product.name == "veracode"
        or
          .data.product.name == "whitesource"
        ) |
        .data.product.name
' <<< "$result" | sort -u | wc -l)
echo "DEBUG: num_prods_comm = '$num_prods_comm'" >&2

result=$(zn_get_obj_list targets "?limit=1") || zn_die
num_tgts=$(jq -r '.[1].totalCount' <<< "$result")
echo "DEBUG: num_tgts = '$num_tgts'" >&2

#result=$(zn_get_obj_list jobs "?limit=10000&since=2021-06-01&until=2021-07-01") || zn_die
#num_jobs=$(jq -r '.[1].count' <<< "$result")
#echo "DEBUG: num_jobs in 2021-June = '$num_jobs'" >&2


########################################################################
# Output the results as CSV
########################################################################
[ $NO_HEADERS ] || echo "Customer,OSS Products,Commercial Products,Applications,Targets,Policies"
echo $cust_name,$num_prods_oss,$num_prods_comm,$num_apps,$num_tgts,$num_pols


########################################################################
# The end.
########################################################################
zn_print_info "Done."
