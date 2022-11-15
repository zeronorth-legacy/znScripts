########################################################################
# (c) Copyright 2019, ZeroNorth, Inc., 2019-Dec, support@zeronorth.io
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
# Read in the parameters.
########################################################################
if ( $args[2] -eq $null )
{
   echo "
Usage: $myname <policy name> <data file> <API key> [NO_WAIT]

  Example: $myname My-Fav-Policy My-Data-File aKhwelkclkwelj....

where,
  <policy name> - The name of the Policy you want to load the data to.

  <data file>   - The path to the scanner output data file. The data file must
                  be of format from a scanner that ZeroNorth has an existing
                  integration with. Typically, a data file is XML or JSON in
                  format.

  <API key>     - The ZeroNorth API key. NOTE: A ZeroNorth API is very long.

  NO_WAIT       - OPTIONAL. If specified, the script will not wait for the
                  completion of the post-processing of the uploaded file.
"
   exit 1
}

# Read in the Policy name.
$POL_NAME=$args[0]
print_msg "Policy: '$POL_NAME'"

# Read in the data file path/name.
$ISSUES_FILE=$args[1]
print_msg "Data file: '$ISSUES_FILE'"
$ISSUES_FILE_NAME=$(split-path -leaf $ISSUES_FILE)
$DATA_FILE=$ISSUES_FILE # this may get overriden in some cases

# Read in the ZeroNorth API key.
$API_KEY=$args[2]
print_msg "Read in API Key."

# If specified, read in the "NO_WAIT" option.
if ( $args[3] -ne $null )
{
   if ( $args[3] -eq "NO_WAIT" )
   {
      $NO_WAIT=[Boolean]"True"
      print_msg "'NO_WAIT' specified. Will not wait for post-processing to complete."
   }
   else
   {
      $word=$args[3]
      print_msg "I do not understand '$word'. Did you mean to specify 'NO_WAIT'?"
      exit 1
   }
}


########################################################################
# Constants
########################################################################
$URL_ROOT="https://api.zeronorth.io/v1"
$HEADERS = @{
   "Accept" = "application/json"
   "Authorization" = "$API_KEY"
}

# The below is not always used.
$TEMP_DIR=$(join-path $env:TEMP "zn_upload.$(get-random).temp")


########################################################################
# The below code does the following:
#
# F) If a Fortify FPR file, extract the audit.fvdl file.
# 0) Look up the Policy name and ensure it exists. Obtain its ID.
# 1) "Run" the specified Policy. This returns the resulting job_id.
# 2) Posts the issues to the job_id from the above step.
# 3) "Resume" the job to allow ZeroNorth to process the posted issues.
# 4) OPTIONALLY, loop, checking for the job status every 3 seconds.
#
# After the above steps, you can see the results in the ZeroNorth UI.
########################################################################

########################################################################
# F) If the data file is a Foritfy FPR, expand the FPR archive in order
#    to obtain the audit.fvdl file we need.
########################################################################
if ( $ISSUES_FILE -match ".*\.fpr$" ) # case insensitive match here
{
   $FNAME='audit.fvdl'
   print_msg "Looks like a Fortify FPR file. It will be expanded to extract the '$FNAME' file."

   print_msg "Will use '$TEMP_DIR' as the working directory."
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
# 0) Look up the Policy by NAME to verify it exists. Obtain its ID.
########################################################################
# Make the Policy name web safe.
$pol_name=$([System.Web.HTTPUtility]::UrlEncode("$POL_NAME"))

# Look up the Policy name.
$result=$(Invoke-RestMethod -method GET -headers $HEADERS -uri "$URL_ROOT/policies?name=$pol_name")

# Examine the Policy name to confirm match.
if ( $result.data.name -ne $POL_NAME )
{
   print_msg "No matching policy found!!! Exiting."
   exit 1
}

# We now need the Policy ID for the next step.
$pol_id=([String]($result.id)).trim()

# Acknowledge.
print_msg "Matching Policy found with ID '$pol_id'."


########################################################################
# 1) Run the specified Policy. This creates a Job that will be in the
#    "PENDING" status, which means the job is waiting for issues to be
#    uploaded.
########################################################################
print_msg "Invoking Policy..."
$result=$(Invoke-RestMethod -method POST -headers $HEADERS -uri "$URL_ROOT/policies/$pol_id/run")

# Extract the Job ID from the response. It's needed it in the next step.
$job_id=$result.jobId

if ( $job_id -eq $null )
{
   print_msg "Error launching job!!! Exiting."
   exit 1
}

print_msg "Got Job ID: '$job_id'."


########################################################################
# 2) Post the issues.
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

Invoke-RestMethod -method POST -headers $HEADERS -uri "${URL_ROOT}/onprem/issues/${job_id}" -contenttype "multipart/form-data; boundary=`"$boundary`"" -body $bodyLines


########################################################################
# 3) Resume the job to let it finish (the post-processing).
########################################################################
print_msg "Hang on..."
sleep 3

print_msg "Resuming Job to finish the process..."
$result=$(Invoke-RestMethod -method POST -headers $HEADERS -uri "$URL_ROOT/jobs/$job_id/resume")


########################################################################
# 4) OPTIONALLY, loop, checking for the job status every 3 seconds.
########################################################################
while ( ! $NO_WAIT )
{
   $result=$(Invoke-RestMethod -method GET -headers $HEADERS -uri "$URL_ROOT/jobs/$job_id")
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
