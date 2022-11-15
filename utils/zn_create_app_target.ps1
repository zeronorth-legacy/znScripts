########################################################################
# (c) Copyright 2020, ZeroNorth, Inc., support@zeronorth.io
#
# A PowerShell Script to look-up or to create the specified Application
# and then add the specified Target to it if not already a member of the
# Application. All other details about the Application are left as is.
#
# Requires PowerShell 5.0 or later.
#
########################################################################
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
if ( $args[2] -eq $null )
{
   echo "
Script to look-up or to create the specified Application and then add
the specified Target to it if not already a member of the Application.
All other details about the Application are left as is.


Usage: $myname <app_name> <tgt_name> <ZeroNorth API key>

  Example: $myname MyApp MyTarget eyJ...


where,

  <app_name>  - The name of the Application you want to create or use.

  <tgt_name>  - The name of the Target you want to add to the specified
                Applications.

  <API key>   - The ZeroNorth API key. NOTE: A ZeroNorth API can be long.
"
   exit 1
}

$APP_NAME = $args[0]
print_msg "Application Name: '$APP_NAME'"

$TGT_NAME = $args[1]
print_msg "Target Name: '$TGT_NAME'"

# Read in the ZeroNorth API key.
$API_KEY = $args[2]
$length = $API_KEY.length
print_msg "Read in API Key: $length bytes."


########################################################################
# Web constants
########################################################################
Add-Type -AssemblyName System.Web

$URL_ROOT = "https://api.zeronorth.io/v1"
$HEADERS = @{
   "Content-Type" = "application/json"
   "Accept" = "application/json"
   "Authorization" = "$API_KEY"
}


########################################################################
# The below code does the following:
#
# 1) Look up the Target ID based on the specified Target Name.
# 2) Look up or create the Application with Target
# 3) Update existing Application with Target
#
# If the above steps are successful, the script exits with status of 0
# printing the resulting Application Name and ID.
########################################################################

########################################################################
# 1) Look up the Target ID based on the specified Target Name.
########################################################################
#
# First, check to see if a Target by same name exists
#
# URL encode TGT_NAME
$tgt_name = $([System.Web.HTTPUtility]::UrlEncode("$TGT_NAME"))

# Look up the Target name.
try
{
   $result = $(Invoke-RestMethod -method GET -headers $HEADERS -uri "$URL_ROOT/targets?name=$tgt_name")
}
catch
{
   print_msg "ERROR:"
   echo "$_.Exception.Response"
   exit 1
}

# How many matching Targets?
if ( $result.data.count -gt 2 )
{
   # More than one, so a problem.
   print_msg "Found multiple matches for the Target Name '${TGT_NAME}'!!! Exiting."
   exit 1
}
# Exactly 1 match?
elseif ( $result.data.name -eq $TGT_NAME )
{
   $tgt_id = ([String]($result.id)).trim()
   print_msg "Target '$TGT_NAME' found with ID '$tgt_id'."
}
# Target not found, die.
else
{
   print_msg "Target '$TGT_NAME' does not exist!!! Exiting."
   exit 1
}


########################################################################
# 2) Look up or create the Application with Target.
########################################################################
#
# First, check to see if an Application by same name exists
#
# URL encode APP_NAME
$app_name = $([System.Web.HTTPUtility]::UrlEncode("$APP_NAME"))

# Look up the Application name.
try
{
   $result = $(Invoke-RestMethod -method GET -headers $HEADERS -uri "$URL_ROOT/applications?expand=true&name=$app_name")
}
catch
{
   print_msg "ERROR:"
   echo "$_.Exception.Response"
   exit 1
}

# How many matching Applications?
if ( $result.data.count -gt 2 )
{
   # More than one, so a problem.
   print_msg "Found multiple matches for the Application Name '${APP_NAME}'!!! Exiting."
   exit 1
}
# Exactly 1 match?
elseif ( $result.data.name -eq $APP_NAME )
{
   $app_id = ([String]($result.id)).trim()
   print_msg "Application '$APP_NAME' found with ID '$app_id'."
}
# Application not found, so create it.
else
{
   print_msg "Creating Application '${APP_NAME}'..."

   # Prepare the JSON payload.
   $payload = @{
      name = $APP_NAME
      description = ''
      targetIds = @($tgt_id)
   }
   $json = $payload | ConvertTo-Json

   # Do it.
   try
   {
      $result = $(Invoke-RestMethod -method POST -headers $HEADERS -uri "$URL_ROOT/applications" -body $json)
   }
   catch
   {
      print_msg "ERROR:"
      echo "$_.Exception.Response"
      exit 1
   }

   # Extract the Application ID from the response.
   $app_id = $result.id
   print_msg "Application '$APP_NAME' created with ID '$app_id'."
}


########################################################################
# 3) Update existing Application with the new Target.
########################################################################

# Get the Application details using the app_id.
try
{
   $result = $(Invoke-RestMethod -method GET -headers $HEADERS -uri "$URL_ROOT/applications/${app_id}?expand=false")
}
catch
{
   print_msg "ERROR:"
   echo "$_.Exception.Response"
   exit 1
}

# Extract the list of the Target IDs.
$tgt_list = @($result.data.targets.id)

# Check if tgt_id is already included.
if ( $tgt_list.contains($tgt_id) )
{
   print_msg "Target '$TGT_NAME' is already a member of Appliation '${APP_NAME}'. We are good!!!"
   exit
}

# Update the list of the Target IDs.
$tgt_list += $tgt_id

# Prepare the base payload for updating the Appliation.
$payload = @{
   name = $APP_NAME
   description = ''
   targetIds = @($tgt_list)
}

#
# Does the application have OWASP Risk Estiamte? We need to preserve it.
#

# Risk estimate type
print_msg "Checking if '$APP_NAME' has risk impact calculated..."
$risk_type=$result.data.typeOfRiskEstimate

# technical
if ( "$risk_type" -eq "technical" )
{
   print_msg "'$APP_NAME' is using '$risk_type' risk impact assessment."

   # Obtain the risk details.
   $integrityLoss=$result.data.technicalImpact.integrityLoss
   $confidentialityLoss=$result.data.technicalImpact.confidentialityLoss
   $availabilityLoss=$result.data.technicalImpact.availabilityLoss
   $accountabilityLoss=$result.data.technicalImpact.accountabilityLoss

   # Add the risk details to the payload.
   $payload += @{
      typeOfRiskEstimate = $risk_type
      technicalImpact = @{
         confidentialityLoss = $confidentialityLoss
         integrityLoss = $integrityLoss
         availabilityLoss = $availabilityLoss
         accountabilityLoss = $accountabilityLoss
      }
   }
}
# business
elseif ( "$risk_type" -eq "business" )
{
   print_msg "'$APP_NAME' is using '$risk_type' risk impact assessment."

   # Obtain the risk details.
   $financialDamage=$result.data.businessImpact.financialDamage
   $privacyViolation=$result.data.businessImpact.privacyViolation
   $nonCompliance=$result.data.businessImpact.nonCompliance
   $reputationDamage=$result.data.businessImpact.reputationDamage

   # Add the risk details to the payload.

   $payload += @{
      typeOfRiskEstimate = $risk_type
      businessImpact = @{
         financialDamage = $financialDamage
         reputationDamage = $reputationDamage
         nonCompliance = $nonCompliance
         privacyViolation = $privacyViolation
      }
   }
}
# None
else
{
   print_msg "Application '$APP_NAME' does not have risk impact calculated."
}

# Replace the application.
$json = $payload | ConvertTo-Json

try
{
   $result = $(Invoke-RestMethod -method PUT -headers $HEADERS -uri "$URL_ROOT/applications/${app_id}" -body $json)
}
catch
{
   print_msg "ERROR:"
   echo "$_.Exception.Response"
   exit 1
}

# All went well.
print_msg "Application '${APP_NAME}' updated with Target '${TGT_NAME}'."


########################################################################
# The End
########################################################################
print_msg "Done."
