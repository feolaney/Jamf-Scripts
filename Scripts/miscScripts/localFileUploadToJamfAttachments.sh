#!/bin/bash

################
# Created by slaney  06/28/22
# Modified by slaney 11/05/24
# Collects local file (designed for log files) and places it in attachments on the computer record

# README
# This script deals with the Jamf API and is designed to run on client computers.
# Make sure to use caution when passing credentials to the script, not advised to hard code credentials in the script
#    or to pass them as parameters in the script.

# Modify how your script will get the two following variables:
apiUser="username"
apiPassword=""

# Path of log to upload passed as parameter $4
logFile="${4}"
################
################

# Script Variables


deviceSerialNumber=$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')
myJssBaseUrl=$( /usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url )
myJssApiUrl="${myJssBaseUrl}JSSResource/"
jssApiPaths="${myJssApiUrl}computers/serialnumber/${deviceSerialNumber}"
curlOptions="--silent --show-error --connect-timeout 60 --fail"

################

# Bearer Token setup
bearerToken=""
tokenExpirationEpoch="0"

getBearerToken() {
	response=$(curl -s -u "$apiUser":"$apiPassword" "$myJssBaseUrl"/api/v1/auth/token -X POST)
	bearerToken=$(echo "$response" | plutil -extract token raw -)
	tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
}

getBearerToken

################


# Get Location computer information searching device by Serial Number and output into tmp/tmp0.xml
jssId=$(curl -XGET -H  "Authorization: Bearer ${bearerToken}" "${jssApiPaths}" ${curlOptions} | sed -E -e 's/.*<general><id>([0-9]*)<\/id><name>.*/\1/' -e t -e d)

# Debug output
echo "JSS ID: $jssId"




if [ -f $logFile ]; then
    logFileBasename=$(basename $logFile)
    logFileDirname=$(dirname $logFile)
    currentDate=$(date +"%Y-%m-%d")

    logFileWithDate="${logFileDirname}/${currentDate}_${logFileBasename}"

    echo "Copying $logFile to $logFileWithDate"

    cp $logFile $logFileWithDate
    sleep 1

    echo "Uploading $logFileWithDate to JSS ID $jssId as attachment"
    # Curl log file with date to computer record of this computer
    uploadUrl="${myJssBaseUrl}JSSResource/fileuploads/computers/id/$jssId"

    echo "Upload URL: $uploadUrl"
    curl -H "Authorization: Bearer ${bearerToken}" "$uploadUrl" -F name=@${logFileWithDate} -X POST

    # Remove Log file with date
    rm -f "$logFileWithDate"
else
    echo "${logFile} doesn't exist on this computer"
    exit 1
fi
