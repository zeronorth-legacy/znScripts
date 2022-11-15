########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# Script to extract a Checkmarx SAST scan results XML report for the
# specified project name. Extracts the latest \"Finished\" scan report
# in XML format.
#
# Requires PowerShell 5.0 or later.
########################################################################
$myname = $MyInvocation.MyCommand.Name


########################################################################
# Function to print time-stamped messages
########################################################################
function print_msg ($msg)
{
    write-host "$(get-date -format 'yyyy-MM-dd HH:mm:ss')  $myname  $msg"
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if ( $args[4] -eq $null )
{
   echo "
Script to extract a Checkmarx SAST scan results XML report for the specified
project name. Extracts the latest ""Finished"" scan report. If successful, the
resulting XML content is written to STDOUT.


Usage: $MYNAME <CX API URL root> <CX user> <password> <project> <out file>

where,

  <CX API URL root> E.g. ""https://cx.my.com/cxrestapi""

  <CX user>         The username of the Checkmarx user. This user should
                    have sufficient privileges to view results and create
                    reports.

  <password>        The password for the username.

  <project>         The Checkmarx project name.

  <out file>        The path to the output file. The output will be an XML
                    document. If the file path contains SPACE characters,
                    be sure to quote the path properly.


Examples:

  $MYNAME https://cx.my.com/cxrestapi joe pass1234 my-cx-project cx_report.xml
"
   exit 1
}

$CX_URL_BASE=$args[0]
print_msg "Checkmarx server URL root: '$CX_URL_BASE'"

$CX_USER=$args[1]
print_msg "Username: '$CX_USER'"
$user=$([uri]::EscapeDataString("$CX_USER"))

$CX_PASSWORD=$args[2]
print_msg "Password: (hidden)"
$pwd=$([uri]::EscapeDataString("$CX_PASSWORD"))

$CX_PROJECT=$args[3]
print_msg "Project: '$CX_PROJECT'"

$OUT_FILE=$args[4]
print_msg "Output file: '$OUT_FILE'"


########################################################################
# Constants
########################################################################
#
# Web
#
Add-Type -AssemblyName System.Web

#
# Checkmarx
#
$CX_CLIENT_ID="resource_owner_client"
# see private version for legacy cx client secret
$CX_CLIENT_SECRET="<REDACTED>"


########################################################################
# 1) Authenticate to obtain the token.
########################################################################
# Set the headers needed for the authentication call.
$H1 = @{
   "Content-Type" = "application/x-www-form-urlencoded"
   "Accept" = "application/json"
}

# Compose the POST data for authentication.
$post_data="username=${user}&password=${pwd}&grant_type=password&scope=sast_rest_api&client_id=${CX_CLIENT_ID}&client_secret=${CX_CLIENT_SECRET}"

try
{
   $result=$(Invoke-RestMethod -method POST -headers $H1 -body $post_data -uri "$CX_URL_BASE/auth/identity/connect/token")
}
catch
{
   print_msg "ERROR  authentication failure:"
   echo "$_"
   exit 1
}

# Extract the token (looks like a JWT).
$token=$result.access_token


########################################################################
# The headers to use for the remainder of the calls
########################################################################
$HEADERS = @{
   "Content-Type" = "application/json"
   "Accept" = "application/json"
   "Authorization" = "Bearer $token"
}


########################################################################
# 2) List the project.
########################################################################
try
{
   $result=$(Invoke-RestMethod -method GET -headers $HEADERS -uri "$CX_URL_BASE/projects")
}
catch
{
   print_msg "ERROR  API call failure:"
   echo "$_"
   exit 1
}

# Obtain the project ID and the name.
$proj_id=$($result | where -property name -value $CX_PROJECT -EQ).id
$proj_nm=$($result | where -property name -value $CX_PROJECT -EQ).name

if ( (! $proj_id) -or ($proj_id -eq "null") -or ($proj_nm -ne $CX_PROJECT) )
{
   print_msg "ERROR  unable to locate project '$CX_PROJECT'."
   exit 1
}
print_msg "Project '$CX_PROJECT' found with ID $proj_id."


########################################################################
# 3) Get the latest Finished scan ID of the project.
########################################################################
try
{
   $result=$(Invoke-RestMethod -method GET -headers $HEADERS -uri "$CX_URL_BASE/sast/scans?projectId=${proj_id}&last=1&scanStatus=Finished")
}
catch
{
   print_msg "ERROR  API call failure:"
   echo "$_"
   exit 1
}

# Obtain the scan ID (if any).
$sid=($result[0]).id

if ( (! $sid) -or ($sid -eq "null") )
{
   print_msg "ERROR  unable to find finished scans for '$CX_PROJECT'."
   exit 1
}
print_msg "Found scan ID $sid."


########################################################################
# Register a new XML report.
########################################################################
# Construct the payload to request an XML report.
$post_data = @{
   reportType = "XML"
   scanId = "$sid"
}

try
{
   $result=$(Invoke-RestMethod -method POST -headers $HEADERS -body $(convertto-json $post_data) -uri "$CX_URL_BASE/reports/sastscan")
}
catch
{
   print_msg "ERROR  API call failure:"
   echo "$_"
   exit 1
}

# Examine the response for the next step details.
$rid=$result.reportId

if ( (! $rid) -or ($rid -eq "null") )
{
   print_msg "ERROR  failed registering a new report."
   exit 1
}
print_msg "Got report ID $rid."


########################################################################
# Go into 5 second loop checking for the report status.
########################################################################
while (1)
{
   start-sleep 5
   
   # Check report status.
   try
   {
      $result=$(Invoke-RestMethod -method GET -headers $HEADERS -uri "$CX_URL_BASE/reports/sastscan/$rid/status")
   }
   catch
   {
      print_msg "ERROR  API call failure:"
      echo "$_"
      exit 1
   }

   # Obtain the report status code.
   $rstatus=$result.status.id

   # 1 = In Process
   if ( $rstatus -eq 1 )
   {
      print_msg "Report still in process..."
      continue
   }

   # 2 = Created (done)
   elseif ( $rstatus -eq 2 )
   {
      # Extract the report.
      $ruri=$result.link.uri
      $rctype=$result.contentType

      # Headers for report XML extraction
      $RHEADERS = @{
         "Accept" = "$rctype; charset=utf-8"
         "Accept-Charset" = "utf-8"
         "Authorization" = "Bearer $token"
      }

      # Extract the report.
      try
      {
         Invoke-RestMethod -method GET -headers $RHEADERS -uri "${CX_URL_BASE}$ruri" | foreach-object {$_ -replace "\xEF\xBB\xBF", ""} | set-content -encoding utf8 $OUT_FILE
      }
      catch
      {
         print_msg "ERROR  API call failure:"
         echo "$_"
         exit 1
      }
      break
   }

   # 3 = Failed
   elseif ( $rstatus -eq 3 )
   {
      print_msg "ERROR  Report generation failed."
      exit 1
   }

   # This should not happen.
   else
   {
       print_msg "ERROR  received unknown report status code '$rstatus'."
       exit 1
   }
}


########################################################################
# Done.
########################################################################
print_msg "Done."
