#!/bin/zsh

# ============================================================================
# Script Information:
# 
# Author        : Stephen Laney
# Creation Date : 2023-10-16
# Last Modified : 2023-10-16
# 
# Purpose     : Check Jamf Smart Group computers for particular command status using Jamf API
# Usage       : Cron jobs or manual execution
# Contact     : Mac Admins Slack - slaney
# 
# Disclaimer  : This script is provided "as is", without warranty of any kind, express or implied. In no event will the 
#               author be held liable for any damages or consequences arising from the use of this script.
# ============================================================================


# ------------------------------------------------------------------------------------------------------------------
# Script Summary:
#
# This script interacts with the Jamf API to fetch information from a given Jamf Smart Group of computers and identifies 
# specific status messages within each computer's command history. It uses the Jamf Pro API for authentication and retrieving 
# computer information. The end goal is to generate lists of computer IDs that have encountered each specified status message.
#
# The script contains the following main functionalities:
#   - Authenticate to Jamf Pro API.
#   - Handle API Token renewal.
#   - Retrieve list of computers within a specified Smart Group.
#   - Iterate over each computer, fetching its history and checking for specified status texts.
#   - Generate a list of computer IDs for each specified status text.
#   - Print out all computer IDs having encountered each specific status text.
#
# Functions in the Script:
#   - DecryptCredentials: Decrypts a string using OpenSSL.
#   - GetJamfProAPIToken: Fetches a new API token.
#   - APITokenValidCheck: Checks if the API token is still valid.
#   - CheckAndRenewAPIToken: Checks the token validity and renews it if required.
#   - InvalidateToken: Invalidates the current token.
#
# To accommodate new status texts, modify the 'statusTexts' array by adding the new status text.
# ------------------------------------------------------------------------------------------------------------------

# 'statusTexts' is an array of status texts. These status messages will be searched for in each computer's history.
# Any computer with a history item whose status matches any of these texts will have its ID added to a list.
# For example, "The device token is not active for the specified topic." status might indicate that the computer
# has a problem with MDM communication. 
#
# Here is an example of statusTexts:
# statusTexts=("The device token is not active for the specified topic." "Another status message")

typeset -a statusTexts=("The device token is not active for the specified topic." "Push using revoked certificate." "Update to MDM profile contains different server URL." "The SCEP server")

# The 'jssApiPassword' variable should contain the password for your JAMF API user. 
# The 'apiUser' variable should contain the username for your JAMF API user.

# The following variables can be set to hardcode credentials for authentication when making API requests.

jssApiPassword=""
apiUser=""

# The 'smartGroupId' variable should contain the ID number of the JAMF smart group that you're checking.

smartGroupId=""


# Script Variables

curlOptions=(--silent --show-error --connect-timeout 60 --fail)

myJssBaseurl=$( /usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url )
myJssApiurl="${myJssBaseurl}api/v1/jamf-management-framework/redeploy/"
#
#
#
# FUNCTIONS
#
#
#

GetJamfProAPIToken() {

# This function uses Basic Authentication to get a new bearer token for API authentication.
echo "Getting Jamf API token"
authtoken=$(curl "${curlOptions[@]}" -k -u "${apiUser}:${jssApiPassword}" -X POST "${myJssBaseurl}/uapi/auth/tokens" -H "accept: application/json")
# Parse the token from the response using awk
jamfApiToken=$(echo "$authtoken" | awk -F '"' '{for(i=1;i<=NF;i++)if($i=="token")print $(i+2)}')

}

APITokenValidCheck() {

# Verify that API authentication is using a valid token by running an API command
# which displays the authorization details associated with the current API user. 
# The API call will only return the HTTP status code.
apiAuthenticationCheck=$(curl --write-out "%{http_code}" --silent --output /dev/null "${myJssBaseurl}/api/v1/auth" -X GET -H "Authorization: Bearer ${jamfApiToken}")
}

CheckAndRenewAPIToken() {

# If the api_authentication_check has a value of 200, that means that the current
# bearer token is valid and can be used to authenticate an API call.
APITokenValidCheck
if [[ ${apiAuthenticationCheck} == 200 ]]; then

# If the current bearer token is valid, it is used to connect to the keep-alive endpoint. This will
# trigger the issuing of a new bearer token and the invalidation of the previous one.
#
# The output is parsed for the bearer token and the bearer token is stored as a variable.
  authtoken=$(curl "${curlOptions[@]}" -H "Authorization: Bearer ${jamfApiToken}" -X POST "${myJssBaseurl}/api/v1/auth/keep-alive" -H "accept: application/json")
  # authtoken=$(/usr/bin/curl "${myJssBaseurl}/api/v1/auth/keep-alive" -silent -request POST -header "Authorization: Bearer ${jamfApiToken}")
  jamfApiToken=$(echo "$authtoken" | awk -F '"' '{for(i=1;i<=NF;i++)if($i=="token")print $(i+2)}')
else

# If the current bearer token is not valid, this will trigger the issuing of a new bearer token
# using Basic Authentication.
  echo "Getting new token"
   GetJamfProAPIToken
fi
}
InvalidateToken() {

# Verify that API authentication is using a valid token by running an API command
# which displays the authorization details associated with the current API user. 
# The API call will only return the HTTP status code.

APITokenValidCheck

# If the api_authentication_check has a value of 200, that means that the current
# bearer token is valid and can be used to authenticate an API call.

if [[ ${apiAuthenticationCheck} == 200 ]]; then

# If the current bearer token is valid, an API call is sent to invalidate the token.

      authtoken=$(/usr/bin/curl "${myJssBaseurl}/api/v1/auth/invalidate-token" -silent  -header "Authorization: Bearer ${jamfApiToken}" -X POST)
      
# Explicitly set value for the api_token variable to null.

      jamfApiToken=""

fi
}


#
#
#
# MAIN SCRIPT
#
#
#

GetJamfProAPIToken
################
# Beaer Token setup
################


# If jssApiPassword or apiUser is not set, prompt the user for these values
if [[ -z "${jssApiPassword// }" ]]; then
  echo "Please enter the jssApiPassword:"
  read jssApiPassword
fi

if [[ -z "${apiUser// }" ]]; then
  echo "Please enter the apiUser:"
  read apiUser
fi

if [[ -z "${smartGroupId// }" ]]; then
  echo "Please enter the smartGroupId:"
  read smartGroupId
fi


authtoken=$(curl "${curlOptions[@]}" -k -u "${apiUser}:${jssApiPassword}" -X POST "${myJssBaseurl}/uapi/auth/tokens" -H "accept: application/json")
# Parse the token from the response using awk
jamfApiToken=$(echo "$authtoken" | awk -F '"' '{for(i=1;i<=NF;i++)if($i=="token")print $(i+2)}')


# An associative array to hold the IDs of computers with each status from statusTexts
typeset -A computersWithStatus
for statusMessage in "${statusTexts[@]}"; do
  computersWithStatus[$statusMessage]=""
done

# Make a request to the API endpoint that will return information about our smart group
smartGroupResponse=$(curl "${curlOptions[@]}" -k -H "Authorization: Bearer ${jamfApiToken}" -X GET "${myJssBaseurl}/JSSResource/computergroups/id/${smartGroupId}")

# Save the response in a temporary xml file
echo "${smartGroupResponse}" > temp.xml

# Parse the XML with xmllint to grab the computer ids and store them in a variable
computerIds=$(xmllint --xpath '//*[local-name()="computer_group"]/*[local-name()="computers"]/*[local-name()="computer"]/*[local-name()="id"]/text()' temp.xml 2>/dev/null)

# Display first 20 elements of the array

rm temp.xml
# The specified status text to search for

# An array to hold the IDs of computers with MDM issues
declare -a mdmIssueComputers=()


# Convert computerIds to an array
computerIds_ARR=()
for id in ${(ps:\n:)computerIds}; do
  computerIds_ARR+=("$id")
done

echo "Searching for all computers in Smart Group ID: $smartGroupId"

count=0

# Iterate over each computer ID
for computerId in "${computerIds_ARR[@]}"; do
  count=$((count + 1))
  # Make an API request to fetch the history of the given computer
  computerHistoryResponse=$(curl ${curlOptions} -k -H "Authorization: Bearer ${jamfApiToken}" -X GET "${myJssBaseurl}/JSSResource/computerhistory/id/${computerId}")
  echo -n "Searching ID: $computerId"
  curlExitStatus=$?
  
  if [[ ${curlExitStatus} -eq 22 ]]; then
    echo "Computer not found for ID: ${computerId}, HTTP 401 error encountered."
    continue
  fi

  # Save the response in a temporary xml file
  echo "${computerHistoryResponse}" > temp.xml
  
  # Check each status text
  for statusText in "${statusTexts[@]}"; do
  # Grab the command statuses
  commandStatuses=$(xmllint --xpath '//computer_history/commands/failed/command/status/text()' temp.xml 2>/dev/null)
  
  # If this status text was found in the command statuses
  if [[ ${commandStatuses} == *${statusText}* ]]; then
      echo -n " - Found status: $statusText"
      
      # Add this computer ID to the correct array in our associative array
      computersWithStatus[$statusText]+="$computerId "
  fi
  done
    # Remove the temporary xml file
  rm temp.xml
  echo ""

  # if 100 records have been searched renew API Token
  if ((count % 100 == 0)); then
    echo "\\nChecking API token\\n"
    CheckAndRenewAPIToken
  fi

done

# Print out the list of IDs for each status for final confirmation
for statusMessage in "${statusTexts[@]}"; do
  echo "\\n-------\\n-------\\nList of computer IDs with issue '${statusMessage}':"
  echo ${computersWithStatus[$statusMessage]}
  echo "\\nURLs:"
  for computerId in ${(ps: :)computersWithStatus[$statusMessage]}
    do
        echo "${myJssBaseurl}computers.html?id=${computerId}&o=r"
  done
  echo ""
done
InvalidateToken