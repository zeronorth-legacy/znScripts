########################################################################
# (c) Copyright 2021, ZeroNorth, Inc., support@zeronorth.io
#
# A PowerShell script to run the Policy specified by the name. If more
# than one matching Policy is found, then this script exit with error.
# The same when no matching Policy is found.
#
# LIMITATIONS:
# - Policy name lookup uses case-insensitie suffix matching.
#
# Requires PowerShell 5.0 or later.
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
    write-host "$(get-date -format 'yyyy-MM-dd HH:mm:ss')  $myname  $msg"
}


########################################################################
# For this example, the issues records are loaded from an input file
# spepcified via the first positional parameter. Check to make sure it
# was specified.
########################################################################
if ( $args[1] -eq $null )
{
   write-host -nonewline -separator '' "
A PowerShell script to run the Policy specified by the name. If more
than one matching Policy is found, then this script exit with error.
The same when no matching Policy is found.

LIMITATIONS:
- Policy name lookup uses case-insensitie suffix matching.


Usage: $myname <policy name> [WAIT] <API key>

where,

  <policy name> - The name of the Policy to run. If more than one match
                  is found by the specified name, the script will error.
                  If no matchis found, the script will error.

  WAIT          - An optional parameter, if specified, will wait for the
                  Policy to finish and then product an exit status based
                  on the final status of the Policy. If the Policy finishes
                  fine, ""FINISHED"", then the exit status ("'$?'") will be true,
                  else False.

  <API key>     - The ZeroNorth API key. NOTE: A ZeroNorth API is very long.


  Examples: $myname MyFavPolicy aKhwelkclkwelj....
            $myname MyFavPolicy WAIT aKhwelkclkwelj....

"
   exit 1
}


# Read in the Policy name.
$POL_NAME=$args[0]; $dummy,$args=$args
print_msg "Policy: '$POL_NAME'"

# Read in the next param.
if ( $args[0] -eq "WAIT" )
{
   $WAIT=1; $dummy,$args=$args
   print_msg "Wait for Policy selected."
} else { $WAIT=0 }

# Read in the ZeroNorth API key.
# BUG: here, we assume the API token is the rest the args array, because
# of the way we shift through them. If we remove this final param, then
# the "WAIT" option above must use the same technique.
$API_KEY=$args
$length=$API_KEY.length
if ( $length -lt 2000 )
{
   print_msg "API key seems too short at $length bytes. Exiting."
   exit 1
}
print_msg "Read in API Key: $length bytes."


########################################################################
# Web constants
########################################################################
Add-Type -AssemblyName System.Web

$URL_ROOT="https://api.zeronorth.io/v1"
$HEADERS = @{
   "Content-Type" = "application/json"
   "Accept" = "application/json"
   "Authorization" = "$API_KEY"
}


########################################################################
# The below code does the following:
#
# 0) Look up the Policy and ensure it exists.
# 1) "Run" the Policy specified via the POL_NAME variable. This returns
#    the resulting job_id.
#
# After the above steps, you can see the results in the ZeroNorth UI.
########################################################################

########################################################################
# 0) Look up the Policy to verify it exists. Note that Policy look up by
#    name uses case-insensitive suffix match. Use a good naming standard
#    to avoid ambiguities within your ZeroNorth account.
########################################################################
# Make the Policy name web safe.
$pol_name_encoded=$([uri]::EscapeDataString($POL_NAME))

# Look up the Policy name.
try
{
   $result=$(Invoke-RestMethod -method GET -headers $HEADERS -uri "$URL_ROOT/policies?name=$pol_name_encoded")
}
catch
{
   print_msg "ERROR:"
   echo "$_.Exception.Response"
   exit 1
}

# Check to see how many matches. The ZeroNorth API does a case-insensitive
# suffix matches when looking up by name, so use a good naming convention.
if ( ($result[1])."count" -gt 1 )
{
   print_msg "ERROR: redundant or ambigous name matches:"
   print_msg $result[0].data.name
   print_msg "Exiting."
   exit 1
}

# Double check the single Policy to confirm name match.
if ( $result[0][0].data.name -ne $POL_NAME )
{
   print_msg "No matching policy found!!! Exiting."
   exit 1
}

# We now need the Policy ID for the next step.
$pol_id=([String]($result[0][0].id)).trim()

# Acknowledge.
print_msg "Matching Policy found with ID '$pol_id'."


########################################################################
# 1) Run the specified Policy, but don't wait for it.
########################################################################
print_msg "Invoking Policy..."
try
{
   $result=$(Invoke-RestMethod -method POST -headers $HEADERS -uri "$URL_ROOT/policies/$pol_id/run")
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
print_msg "Policy invoked and got Job ID: '$job_id'."


########################################################################
# Optionally, wait for the job to finish.
########################################################################
$job_status=""
while ( $WAIT -eq 1 )
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

   sleep 5
}

if ( $job_status -eq "FAILED" )
{
   exit 1
}


########################################################################
# The End
########################################################################
print_msg "Done."
