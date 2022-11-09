########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# A PowerShell script to upload a scanner output file to a ZeroNorth
# Policy. Assumes that the file being uploaded is produced by a product
# that ZeroNorth has existing integration with.
#
# Requires PowerShell 5.0 or later if using it to upload Fortify FPR
# files, because this script uses the cmdlet expand-archive to extract
# the audit.fvdl file from the Fortify FPR archive. Alternatively,
# provide the audit.fvdl file to this script to bypass that step.
#
# Before using this script, sign-in to https://fabric.zeronorth.io to
# prepare a shell Policy that will accept the issues:
#
# 1) Go to znADM -> Scenarios. Locate and activate a Scenario for the
#    appropriate Product to match the JSON/XML document.
#
# 2) Go to znADM -> Integrations -> Add Integration. Create a shell
#    Integration of type "Custom" and set Initiate Scan From to "MANUAL".
#
# 3) Go to znOPS -> Targets -> Add Target. Using the Integration from
#    step 2, create a shell Target.
#
# 4) Go to znOPS -> Policies -> Add Policy. Create a shell policy using
#    the items from the above steps.
#
# Related information in ZeroNorth KB at:
#
#    https://support.zeronorth.io/hc/en-us/articles/115001945114
#
########################################################################
#
# Before using this script, obtain your API key using the instructions
# outlined in the following KB article:
#
#   https://support.zeronorth.io/hc/en-us/articles/115003679033
#
# The API key should then be stored in secure file, referenable from
# this script. The file should only contain the API key string and no
# other content (no variable names, no quotes, no NEWLINE, etc.)
#
# IMPORTANT: An API key generated using the above method has life span
# of 10 calendar years.
#
########################################################################
$myname = $MyInvocation.MyCommand.Name


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg  ($msg)
{
    write-host "$(get-date -format 'yyyy-MM-dd HH:mm:ss')  $msg"
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if ( $args[1] -eq $null )
{
   echo "
Usage: $myname <policy ID> <data file> [<key_file>]

  Example: $myname QIbGECkWRbKvhL40ZvsVWh MyDataFile MyKeyFile

where,
  <policy ID> - The ID of the Policy you want to load the data to.

  <data file> - The path to the scanner output data file. The data file
                must be of output format from a scanner that ZeroNorth has
                existing integration with. Typically, data file is XML
                or JSON in format.

  <key_file>  - Optionally, the file with the ZeroNorth API key. If not
                provided, will use the value in the API_KEY variable,
                which can be supplied as an environment variable or be
                set inside the script.
"
   exit 1
}

# Read in the Policy ID.
$POLICY_ID=$args[0]
print_msg "Policy ID: '$POLICY_ID'"

# Read in the data file path.
$ISSUES_FILE=$args[1]
if (! (test-path $ISSUES_FILE))
{
   print_msg "ERROR: Cannot find file '$ISSUES_FILE'! Exiting."
   exit 1
}
else
{
   print_msg "Data file: '$ISSUES_FILE'"
}
$ISSUES_FILE_NAME=$(split-path -leaf $ISSUES_FILE)
$DATA_FILE=$ISSUES_FILE # this may get overriden in some cases

# Optionally, read in the API key file.
if ( $args[2] )
{
   $KEY_FILE=$args[2]
   if (! (test-path $KEY_FILE))
   {
      print_msg "ERROR: Cannot find file '$KEY_FILE'! Exiting."
      exit 1
   }
   print_msg "Key file: '$KEY_FILE'"
   $API_KEY=$(cat $KEY_FILE)
}

$length=$API_KEY.length
print_msg "Read in API Key: $length bytes."

if ( $length -lt 2000 )
{
   print_msg "ERROR: No API or API key too shrot ($length bytes). Exiting."
   exit 1
}


########################################################################
# Constants
########################################################################
$URL_ROOT="https://api.zeronorth.io/v1"
$HEADERS = @{
   "Content-Type" = "application/json"
   "Accept" = "application/json"
   "Authorization" = "$API_KEY"
}


########################################################################
# The below code does the following:
#
# F) Preprocess a Fortify FPR file, by extracting the audit.fvdl file.
# 0) Look up the Policy ID and ensure it exists.
# 1) "Run" the Policy specified via the POLICY_ID variable. This returns
#    the resulting job_id.
# 2) Posts the issues to the job_id from above.
# 3) "Resume" the job to allow ZeroNorth to process the posted issues.
# 4) Loop, checking for the job status every 3 seconds.
#
# After the above steps, you can see the results in the ZeroNorth UI.
########################################################################


########################################################################
# Prep.
########################################################################

# Prepare a temporary directory under the user's temp directory.
# Not always created/used.
$TEMP_DIR=$(join-path $env:TEMP "zn_upload.$(get-random).temp")
print_msg "Will use '$TEMP_DIR' as the working directory."


########################################################################
# F) If the data file is a Foritfy FPR, expand the FPR archive in order
#    to obtain the audit.fvdl file we need.
########################################################################
if ( $ISSUES_FILE -match ".*\.fpr$" ) # case insensitive match here
{
   $FNAME='audit.fvdl'

   print_msg "Looks like a Fortify FPR file. It will be expanded to extract '$FNAME'."
   mkdir $TEMP_DIR

   $ISSUES_COPY=$(join-path $TEMP_DIR "$ISSUES_FILE_NAME.zip")

   print_msg "Copying as a .zip file..."
   copy $ISSUES_FILE $ISSUES_COPY

   print_msg "Exapanding '$ISSUES_FILE_NAME'..."

   try
   {
      expand-archive -Path $ISSUES_COPY -destinationPath $TEMP_DIR
   }
   catch
   {
      print_msg "Error while expanding '$ISSUES_FILE_NAME'! Exiting."
      exit 1
   }

   print_msg "Expanded '$ISSUES_FILE_NAME' to '$TEMP_DIR'."
   $DATA_FILE=$(join-path $TEMP_DIR $FNAME)
}


########################################################################
# 0) Look up the Policy by ID to verify it exists.
########################################################################
#
# First, check to see if a Policy by same name exists
#
try
{
   $result=$(Invoke-RestMethod -method GET -headers $HEADERS -uri "$URL_ROOT/policies/$POLICY_ID")
}
catch
{
   print_msg "ERROR:"
   echo "$_.Exception.Response"
   exit 1
}

# Extract the resulting policy ID
$pol_id=$result.id 

if ( $pol_id -eq $POLICY_ID )
{
   print_msg "Policy with ID '$POLICY_ID' found."
}
else
{
   print_msg "No matching policy found!!! Exiting."
   exit 1
}

# Check the Policy type.
$pol_type=$result.data.policyType
if ( $pol_type -ne "manualUpload" )
{
   print_msg "WARNING: Policy is not a 'manualUpload' type. This could lead to problems."
}


########################################################################
# 1) Run the specified Policy. This creates a Job that will be in the
#    "PENDING" status, which means the job is waiting for issues to be
#    uploaded.
########################################################################
print_msg "Invoking Policy..."
try
{
   $result=$(Invoke-RestMethod -method POST -headers $HEADERS -uri "$URL_ROOT/policies/$POLICY_ID/run")
}
catch
{
   print_msg "ERROR:"
   echo "$_.Exception.Response"
   exit 1
}

# Extract the Job ID from the response. It's needed it in the next step.
$job_id=$result.jobId

if ( $job_id -eq $null )
{
   print_msg "Error launching job!!! Exiting."
   exit 1
}

print_msg "Got Job ID: '$job_id'."


########################################################################
# 2) Post the issues
########################################################################
print_msg "Uploading the file..."

# Below courtesy of https://stackoverflow.com/questions/22491129/how-to-send-multipart-form-data-with-powershell-invoke-restmethod

#
# The next few lines of screwy code is necessary because the ReadAllText
# method of [System.IO.File] doesn't seem to interpret "." as expected.
#
$DATA_FILE_NAME=$(split-path -leaf $DATA_FILE)
$DATA_FILE_PATH=$(split-path $DATA_FILE)

if ( $DATA_FILE_PATH -eq "" )
{
   $DATA_FILE_PATH = '.'
}
$DATA_FILE_PATH=convert-path $DATA_FILE_PATH
$DATA_FILE=$(join-path $DATA_FILE_PATH $DATA_FILE_NAME )
#echo "DEBUG: data file is '$DATA_FILE'"
#
# End of screwy code...for now.
#
$fileBin = [System.IO.File]::ReadAlltext($DATA_FILE)
$boundary = [System.Guid]::NewGuid().ToString()
$LF = "`r`n"
$bodyLines = ("--$boundary",
   "Content-Disposition: form-data; name=`"file`"; filename=`"$DATA_FILE_NAME`"",
   "Content-Type: application/octet-stream$LF",
   $fileBin, "--$boundary--$LF"
) -join $LF

try
{
   Invoke-RestMethod -method POST -headers $HEADERS -uri "${URL_ROOT}/onprem/issues/${job_id}" -contenttype "multipart/form-data; boundary=`"$boundary`"" -body $bodyLines
}
catch
{
   print_msg "ERROR:"
   echo "$_.Exception.Response"
   exit 1
}


########################################################################
# 3) Resume the job to let it finish.
########################################################################
print_msg "Hang on..."
sleep 3

print_msg "Resuming Job to finish the process..."
try
{
   Invoke-RestMethod -method POST -headers $HEADERS -uri "$URL_ROOT/jobs/$job_id/resume"
}
catch
{
   print_msg "ERROR:"
   echo "$_.Exception.Response"
   exit 1
}


########################################################################
# 4) Loop, checking for the job status every 3 seconds.
########################################################################
while ( 1 )
{
   try
   {
      $result=$(Invoke-RestMethod -method GET -headers $HEADERS -uri "$URL_ROOT/jobs/$job_id")
   }
   catch
   {
      print_msg "ERROR:"
      echo "$_.Exception.Response"
      exit 1
   }
   
   $job_status=$result.data.status

   if ( $job_status -eq "RUNNING" )
      { print_msg "Job '${job_id}' still running..." }
   elseif ( $job_status -eq "PENDING" )
      { print_msg "Job '${job_id}' still in PENDING state..." }
   else
      {
          print_msg "Job '${job_id}' done with status '$job_status'."
          break
      }

   sleep 3
}


########################################################################
# The End
########################################################################
if ( test-path $TEMP_DIR )
{
   rm -recurse -force $TEMP_DIR
   print_msg "Temporary working directory '$TEMP_DIR' removed."
}
