#!/bin/bash

# ============================================================================
# Script Information:
# 
# Author        : Stephen Laney
# Creation Date : 2023-07-11
# Last Modified : 2023-09-18
# 
# Purpose     : Adds a macOS local user alias based on information pulled from asset inventory system
# Usage       : Deployed via Jamf pulling asset information from external source
# Contact     : Mac Admins Slack - slaney
# 
# Disclaimer  : This script is provided "as is", without warranty of any kind, express or implied. In no event will the 
#               author be held liable for any damages or consequences arising from the use of this script.
# ============================================================================

#
# This script was designed to pull information from an external asset management system
#     I would advise that you work with an API tool or the API of your asset management  
#     system so that you can pull the user information that you will use to created the 
#     needed alias
#
# The following variable should be set as the url that will be curled for the username
#     information from the external asset management system:
$externalAssetManagement_URL=""
# Example $externalAssetManagement_URL: "https://apim.externalAssetManagement.com/asset?action=get_asset_asset-information&identifier=$deviceSerialNumber"
# 
# If deployed with Jamf be sure to include the base64 encrypted string, salt and 
#     passphrase of the external asset management token as the first 3 parameters

# Include the DecryptCredentials() function
function DecryptCredentials() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -md md5 -d -a -A -S "${2}" -k "${3}"
}

externalAssetManagement_Token=$(DecryptCredentials "$4" "$5" "$6")

# Script Variables
# Get the serial number of the Mac and put in a variable
deviceSerialNumber=$(ioreg -l | grep "IOPlatformSerialNumber" | awk -F' ' '{print $4}' | tr -d '"')
CurlOptions="--silent --show-error --connect-timeout 60 --fail"

externalAssetManagement_API_Querey="curl -XGET $CurlOptions -H 'API-TOKEN: $externalAssetManagement_Token' '$externalAssetManagement_URL'"
externalAssetManagement_ResponseJSON=$(eval "$externalAssetManagement_API_Querey" || (echo "Error: Failed to execute cURL request"; exit 1))

if [[ -z "$externalAssetManagement_ResponseJSON" ]]; then
    exit 1
fi

#
# This script was originally designed to pull JSON and convert it to XML to pull the assigned
#     username from the external asset management records.  Could need adjustments based on
#     the usecase of and output of the adotion of this script

externalAssetManagement_ResponseXML=$(echo "$externalAssetManagement_ResponseJSON" | /usr/bin/plutil -convert xml1 -o -  -- -)

xpathExpression="//dict/key[text()='response']/following-sibling::string[1]/text()"
innerJSON=$( echo $externalAssetManagement_ResponseXML | /usr/bin/xpath -e "${xpathExpression}" 2>/dev/null | sed -e 's/<[^>]*>//g')

# Convert inner JSON to XML
innerXML=$(echo "$innerJSON" | /usr/bin/plutil -convert xml1 -o -  -- -)

# Extract assignedUser_displayName value
xpathDisplayName="//dict/key[text()='assignedUser_displayName']/following-sibling::string[1]/text()"
displayName=$(echo $innerXML | /usr/bin/xpath -e "${xpathDisplayName}" 2>/dev/null | sed -e 's/<[^>]*>//g')

# Extract the first name from displayName
firstName=$(echo "$displayName" | cut -d' ' -f1)

echo "Assigned User First Name: $firstName"

# Get the current user's username
currentUsername=$(logname)

# Store existing aliases, skipping "RecordName:" part
aliasesLine=$(dscl . -read /Users/$currentUsername RecordName | sed -e 's/RecordName: //')
IFS=$' ' read -ra existingAliases <<< "${aliasesLine}"

echo "Existing Aliases:"
for alias in "${existingAliases[@]}"; do
    echo "$alias"
done

# Check if the alias is already set
aliasExists=$(echo "$existingAliases" | grep -wF "\<${firstName}\>")

if [[ ${aliasExists} ]]; then
    echo "$firstName is already an Alias for $currentUsername"
else
    echo "Setting alias $firstName for /Users/$currentUsername"
    sudo dscl . -merge /Users/${currentUsername} RecordName ${firstName}
fi


