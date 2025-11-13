#!/bin/zsh
# ============================================================================
# Script Information:
# 
# Author        : Stephen Laney
# Creation Date : 2023-08-31
# Last Modified : 2023-09-13
# 
# Purpose     : Upload local Mac log files to an AWS S3 bucket
# Usage       : Used with Workato automation to gather the upload URL to upload 
#               to AWS storage
# Contact     : Mac Admins Slack - slaney
# ============================================================================
#
# ------------------------------------------------------------------------------------------------------------------
# Script Summary:
#
# This script is used to collect and submit specified log files to IT. It creates a dialog box for users to
# select the types of log files they want to submit. After submission, IT will receive a notification.
#
# The script contains the following main functionalities:
#   - Generate a dialog box for users to select the type of logs to submit.
#   - Define and process various log types such as GlobalProtect, Jamf Connect Logs, and Sysdiagnose Logs.
#   - Collect, create, and upload the log files to an S3 bucket.
#
# Functions in the script:
#   - processLogType: Processes the selected log types and performs necessary actions to collect and prepare the logs.
#   - createCheckLogStatusAndUploadScript: Creates a script that checks for the specified logs and uploads them when the S3 URL is ready.
#   - createAndLoadLaunchDaemon: Creates and loads a Launch Daemon to periodically check logs status and S3 bucket upload URL readiness.
#   - deletePrefixedFiles: Deletes the files and directories with a specified prefix in a given directory path.
#   - generateS3BucketURL: Generates an S3 bucket URL using Workato API and returns the UUID.
#
# Replace the following variables with appropriate values according
# to the automation software or API used to generate the S3 bucket URL.
AUTOMATION_API="https://example.com/automation/api" # replace with your API URL
API_TOKEN_HEADER="API-TOKEN" # replace with your API token header
# When polling for the presigned URL, the placeholder __UUID__ will be replaced
# with the UUID returned by your automation. Update this template to match your API.
PRESIGNED_STATUS_URL_TEMPLATE="${AUTOMATION_API}/status/__UUID__"
# 
#
#  TODO - HOMEWORK IF THIS SCRIPT IS TO BE ADOPTED AND USED
#         This script was originally created with the aid of an automation service that generated the AWS PreSigned URL
#         from Lambda Function.  This is to securly generate the AWS Upload URL off the local device and not share API 
#         credentials.  This function will need to be replicated or replaced if this script is to be adopted.
#         The generateS3BucketURL function initiates the creation of the URL.  We noticed that it took up to 1-3 minutes
#         for the URL to generate via API and accounted for that by returning a UUID that could be supplied to our automation
#         resource to collect the URL when finished.
#         
#         This can be seen in the generateS3BucketURL, where the UUID is collected and then in the local script that is created
#         on lines 282-307, the UUID is used to check if the URL has been generated, checking periodically before proceeding.

#         Resources:
#         https://docs.aws.amazon.com/lambda/latest/dg/urls-invocation.html
#         https://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html
#         
# To add new log types to this script, follow the instructions in the comments labeled
# "NEW LOGS - ADMIN INPUT NEEDED".
# ------------------------------------------------------------------------------------------------------------------

# *****************************************************************************************************
# NEW LOGS - ADMIN INPUT NEEDED:
# To add new log types to this script, follow these instructions:
# 1. Add a key-value pair to the logTypeMap associative array for the new log type
# 2. Update the processLogType function to include the logic for collecting and storing the new logs in /var/tmp/
#
# For more information, search for the text "NEW LOGS - ADMIN INPUT NEEDED" in this script
# *****************************************************************************************************

# Define an associative array (dictionary) called logTypeMap.
# To add a new log type to this map, follow the example below:
#
# 1. Add a new key-value pair inside the parentheses.
# 2. The key must be a human-readable text presented to the user as a selectable option. This text will appear in the dialog box.
# 3. The value must be the first part of the log or zip file to be collected and submitted. It will be used as a variable when processing this log type.
#
#   Example for log file "sysdiagnose_2023.08.31_15-16-10-0600_macOS_MacBookPro18-2_23A5328b.tar.gz"
#   the value would = "sysdiagnose" from the first part of the log file
#
# 4. Separate each key-value pair with a space.
# 5. Ensure all keys and values are enclosed in double quotes.
#
# Example format: "key" "value"


typeset -A logTypeMap
logTypeMap=(
    "GlobalProtect/Networking logs" "GlobalProtect"
    "Jamf Connect Logs" "jconnect"
    "Sysdiagnose Logs" "sysdiagnose"
)

# Define separate key and value arrays
logTypeKeys=("${(@k)logTypeMap}")
logTypeValues=("${(@v)logTypeMap}")

# *****************************************************************************************************
# Global Variables
# *****************************************************************************************************
# Function to decrypt automation tokens passed via Jamf
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -md md5 -d -a -A -S "${2}" -k "${3}"
}

tmpDirectoryPath="/var/tmp"
launchDaemonPath="/Library/LaunchDaemons"

computerName=$(scutil --get ComputerName)
timestamp=$(date +"%Y%m%d")
automationApiToken=$(DecryptString $4 $5 $6)





# *****************************************************************************************************
# FUNCTIONS
# *****************************************************************************************************



# Function for processing log type
processLogType() {
    logType="$1"

    launchDaemonFile="com.macadmin.${logType}check.plist"
    strippedLaunchDaemonLabel="${launchDaemonFile%.plist}"
    launchDaemonFullPath="$launchDaemonPath/$launchDaemonFile"
    scriptFile="check${logType}.zsh"
    scriptFullPath="$tmpDirectoryPath/$scriptFile"

    # First curl request to start the generation of S3 bucket url, returns UUID to be used to check progress and eventually
    # obtain S3 upload URL, logic built into createCheckLogStatusAndUploadScript function
    returned_uuid=$(generateS3BucketURL "$automationApiToken" "$computerName" "$logType" "$timestamp")

    configPrefix="${tmpDirectoryPath}/${logType}_${returned_uuid}"
    automationTokenFile="${configPrefix}.token"
    statusTemplateFile="${configPrefix}.template"
    apiHeaderFile="${configPrefix}.header"

    printf '%s' "$automationApiToken" > "$automationTokenFile"
    printf '%s' "$PRESIGNED_STATUS_URL_TEMPLATE" > "$statusTemplateFile"
    printf '%s' "$API_TOKEN_HEADER" > "$apiHeaderFile"
    chmod 600 "$automationTokenFile" "$statusTemplateFile" "$apiHeaderFile"

    #Find log files that have been placed in the tmp directory path
    deletePrefixedFiles "/var/tmp" "$logType"


    # *****************************************************************************************************

    if [ "$logType" = "GlobalProtect" ]; then
        # (GlobalProtect specific log generation code)
        googlePingFile="/var/tmp/${logType}${computerName}_${timestamp}_googleping.txt"

   # Ping 8.8.8.8 and print the results to the file and the console
    echo "Ping to 8.8.8.8:" | tee -a "$googlePingFile"
    ping -c 6 8.8.8.8 | tee -a "$googlePingFile" || echo "Ping to 8.8.8.8 failed"
    echo " "

    # Ping google.com and print the results to the file and the console
    echo "Ping to google.com:" | tee -a "$googlePingFile"
    ping -c 6 google.com | tee -a "$googlePingFile" || echo "Ping to google.com failed"
    echo " "

    # Perform traceroute to google.com and print the results to the file and the console
    echo "Traceroute to google.com:" | tee -a "$googlePingFile"
    traceroute google.com | tee -a "$googlePingFile" || echo "Traceroute to google.com failed"
    echo " "

    # Perform nslookup of google.com and print the results to the file and the console
    echo "NS lookup for google.com:" | tee -a "$googlePingFile"
    nslookup google.com | tee -a "$googlePingFile" || echo "NS lookup for google.com failed"

    # Ping gateway (server from traceroute to google)
    server_ip=\$(nslookup google.com | awk '/^Server:/ { print \$2 }')
    echo "Ping to Gateway - \$server_ip" | tee -a "$googlePingFile"
    ping -c 6 \$server_ip | tee -a "$googlePingFile" || echo "Ping to 8.8.8.8 failed"
    echo " "

    echo "Results saved to file: $googlePingFile"

    # Create GP log file, copy temp file with date to upload

    # Deleting log file if exists

    if [ -f /var/tmp/GlobalProtectLogs.tgz ]; then
        rm /var/tmp/GlobalProtectLogs.tgz
        echo "Deleted /var/tmp/GlobalProtectLogs.tgz"
    else
        echo "/var/tmp/GlobalProtectLogs.tgz does not exist"
    fi

    # Running /Applications/GlobalProtect.app/Contents/Resources/gp_support.sh to generate log files for GP and zip them at /var/tmp
    . /Applications/GlobalProtect.app/Contents/Resources/gp_support.sh "/var/tmp"

    globalProtectLogFile="/var/tmp/GlobalProtectLogs.tgz"

    # setting failed exit code, if empty default 1
    FAILED_EXIT_CODE="${10}"
    if [ -z "$FAILED_EXIT_CODE" ]; then
        FAILED_EXIT_CODE=1
    fi

    if [ -f $globalProtectLogFile ]; then


        # create a temporary directory
        tmp_dir=$(mktemp -d)

        # extract the contents of the .tgz file to the temporary directory
        tar -xzf "$globalProtectLogFile" -C "$tmp_dir"

        # *****************************************************************************************************
        # LOOK AT THIS DESTINATION TO VERIFY THE NAME IS CORRECT
        mv -f "$googlePingFile" "$tmp_dir"
        # *****************************************************************************************************


        # create a .zip file from the contents of the temporary directory
        zip -r "${globalProtectLogFile%.tgz}.zip" "$tmp_dir"

        # delete the temporary directory
        rm -r "$tmp_dir"
        globalProtectLogFileZipped="${globalProtectLogFile%.tgz}.zip"
        rm -r $globalProtectLogFile
    fi
    elif [ "$logType" = "jconnect" ]; then
     # Create file paths for log files and Zip file for Jamf Connect logs
    jamfConnectLoginLogFile="${tmpDirectoryPath}/${logType}Login.log"
    jamfConnectLogFile="${tmpDirectoryPath}/${logType}.log"
    jamfConnectZipFile="${tmpDirectoryPath}/${logType}.zip"
    sudo log show --style compact --predicate 'subsystem == "com.jamf.connect.login"' --debug > ${jamfConnectLoginLogFile}
    sleep 5
    sudo log show --style compact --predicate 'subsystem == "com.jamf.connect"' --debug > ${jamfConnectLogFile}
    sleep 5
    # Zip the log files
    zip "${jamfConnectZipFile}" "${jamfConnectLoginLogFile}" "${jamfConnectLogFile}"

    # Check if the zip operation succeeded
    if [ $? -eq 0 ]; then
    echo "Zip operation for Original JamfConnect log files successful"

    # Delete the original log files
    rm "${jamfConnectLoginLogFile}"
    rm "${jamfConnectLogFile}"
    echo "Original JamfConnect log files deleted"
    else
    echo "Zip operation for Original JamfConnect log files failed"
    fi
        # (JamfConnect specific log generation code)
    elif [ "$logType" = "sysdiagnose" ]; then
        /usr/bin/sysdiagnose -u &
    fi

    # *****************************************************************************************************
    # NEW LOGS - ADMIN INPUT NEEDED:
    # For each NEW log to be added to this script be sure to add a new elif with the corresponding logType above.  
    #
    # Then include the commands needed and have them saved in /var/tmp/ with the first part of the name of the 
    # log file or zip contaiing the logs to match the name in the variable $logType
    #
    # Example:
    # elif [ "$logType" = "sysdiagnose" ]; then
    #     /usr/bin/sysdiagnose -u &
    # fi
    # *****************************************************************************************************
    # Create the check script at /var/tmp
    createCheckLogStatusAndUploadScript "$returned_uuid" "$strippedLaunchDaemonLabel" "$launchDaemonFullPath" "$scriptFullPath" "$logType" "$automationTokenFile" "$statusTemplateFile" "$apiHeaderFile"

    # Create and load the launch daemon used to periodically check if the log files and the S3 URL is ready
    createAndLoadLaunchDaemon "$scriptFullPath" "$launchDaemonFullPath" "$logType"
}

# Function to create a script that will be run to check for desired logs and upload them to S3 bucket when URL has been fully created
createCheckLogStatusAndUploadScript() {
    localUuid="$1"
    strippedLaunchDaemonLabel="$2"
    launchDaemonFullPath="$3"
    scriptFullPath="$4"
    logType="$5"
    automationTokenFile="$6"
    statusTemplateFile="$7"
    apiHeaderFile="$8"
    cat > "$scriptFullPath" << EOL
#!/bin/zsh

tmpDirectoryPath="/var/tmp"
${logType}Files=\$(ls -1d "\$tmpDirectoryPath"/${logType}*)
logFile="\$tmpDirectoryPath/check${logType}.log"
timestamp=\$(date +"[%Y-%m-%d %H:%M:%S]")
automationTokenFile="$automationTokenFile"
statusTemplateFile="$statusTemplateFile"
apiHeaderFile="$apiHeaderFile"
scriptFullPath="$scriptFullPath"
launchDaemonFullPath="$launchDaemonFullPath"
strippedLaunchDaemonLabel="$strippedLaunchDaemonLabel"

cleanupArtifacts() {
    sudo rm -f "\$scriptFullPath" 2>> "\$logFile"
    sudo rm -f "\$launchDaemonFullPath" 2>> "\$logFile"
    sudo launchctl remove "$strippedLaunchDaemonLabel" 2>> "\$logFile"
    sudo rm -f "\$automationTokenFile" "\$statusTemplateFile" "\$apiHeaderFile" 2>> "\$logFile"
}

if [ "\${#${logType}Files[@]}" -gt 0 ]; then
    ${logType}FileToUpload=\$(ls -1d "\$tmpDirectoryPath"/${logType}* | head -n 1)
    echo "\$timestamp ${logType} files and directories found:" | tee -a \$logFile
    echo "\$timestamp \$${logType}FileToUpload" | tee -a \$logFile

    if [[ ! -r "\$automationTokenFile" || ! -r "\$statusTemplateFile" || ! -r "\$apiHeaderFile" ]]; then
        echo "\$timestamp Missing automation configuration files. Exiting." | tee -a \$logFile
        cleanupArtifacts
        exit 1
    fi

    automationApiToken=\$(cat "\$automationTokenFile")
    statusUrlTemplate=\$(cat "\$statusTemplateFile")
    apiTokenHeader=\$(cat "\$apiHeaderFile")

    if [[ "\$statusUrlTemplate" == *"__UUID__"* ]]; then
        statusEndpoint="\${statusUrlTemplate//__UUID__/${localUuid}}"
    else
        trimmedTemplate=\${statusUrlTemplate%/}
        statusEndpoint="\${trimmedTemplate}/${localUuid}"
    fi

    # Repeat up to 30 times
    for i in {1..30}; do
        presignedUrlResponse=\$(curl -s -H "\$apiTokenHeader: \$automationApiToken" "\$statusEndpoint")

        # Check if the curl command outputs an error
        if [[ $? -ne 0 ]]; then
            echo "\$timestamp An error occurred while fetching the URL" | tee -a \$logFile
            s3URL=""
            break
        fi

        s3URL=\$(echo "\$presignedUrlResponse" | sed -E 's/.*"url":"([^"]+).*/\1/')
        echo "\$timestamp URL: \$s3URL"  >> \$logFile

        if [[ "\$s3URL" != *'"response":"Did not find'* && -n "\$s3URL" ]]; then
            break
        fi

        # Wait for 10 seconds
        echo "S3 Upload URL not ready, checking again in 10 seconds" | tee -a \$logFile
        sleep 10
    done

    if [[ -z "\$s3URL" || "\$s3URL" == *'"response":"Did not find'* ]]; then
        echo "\$timestamp Presigned URL was not returned within the expected window." | tee -a \$logFile
        cleanupArtifacts
        exit 1
    fi

    # Submitting ${logType} file to S3 bucket
    echo "\$timestamp Submitting ${logType} file to S3 bucket" >> \$logFile
    curl_output=\$(curl -v --upload-file \$${logType}FileToUpload "\$s3URL" 2>&1)

    echo "\$timestamp ---CURL OUTPUT--- \$curl_output" >> \$logFile

    # Check for success in curl_output
    if [[ "\$curl_output" == *"We are completely uploaded and fine"* ]]; then
        # API call successful
        echo "\$timestamp The API successfully uploaded \$${logType}FileToUpload to the S3 bucket" >> \$logFile
    else
        # The API responded poorly
        echo "\$timestamp The API responded poorly" >> \$logFile
    fi
    
    cleanupArtifacts

else
    echo "\$timestamp No ${logType} files or directories found" >> "\$logFile"
    cleanupArtifacts
fi
EOL

    # Setting the execute permission for the check${logType}.zsh script
    chmod +x "$scriptFullPath"
}

# Function to create and load a Launch Daemon to be used to separate the process of creating logs and the S3 bucket upload URL
createAndLoadLaunchDaemon() {
    scriptFullPath="$1"
    launchDaemonFullPath="$2"
    logType="$3"

    # Setting the execute permission for the script
    sudo echo "
    <?xml version=\"1.0\" encoding=\"UTF-8\"?>
    <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
    <plist version=\"1.0\">
    <dict>
        <key>Label</key>
        <string>com.macadmin.${logType}check</string>
        <key>ProgramArguments</key>
        <array>
            <string>/bin/zsh</string>
            <string>$scriptFullPath</string>
        </array>
        <key>StartInterval</key>
        <integer>300</integer>
        <key>RunAtLoad</key>
        <true/>
    </dict>
    </plist>
    " | sudo tee "$launchDaemonFullPath" > /dev/null
    sudo launchctl load -w "$launchDaemonFullPath"
}

# Function to delete files and directories with the specified prefix in the given directory path
deletePrefixedFiles() {
    directoryPath="$1"
    filePrefix="$2"
    
    # Find files with the specified prefix placed in the directory path
    existingFiles=$(ls -1d "${directoryPath}/${filePrefix}"*)

    if [ "${#existingFiles[@]}" -gt 0 ]; then
        echo "Deleting existing ${filePrefix} files and directories:"
        echo "$existingFiles"
        rm -r "${directoryPath}/${filePrefix}"*
    fi
}

# Function to generate S3 bucket URL using automation software or API and return the UUID
generateS3BucketURL() {
    local automationApiToken="$1"
    local computerName="$2"
    local logType="$3"
    local timestamp="$4"
    
    # First curl request to start the generation of S3 bucket url
    local uuidCurlResponse
    uuidCurlResponse=$(curl -s -XPOST -H "${API_TOKEN_HEADER}: $automationApiToken" "${AUTOMATION_API}/LogUploads/$computerName-$logType-$timestamp.txt")
    local uuid
    uuid=$(echo "$uuidCurlResponse" | sed -E 's/.*"uuid":"([^"]+).*/\1/')
    
    echo "$uuid"
}

# Iterate through the logDialogNames array and append a checkbox string for each entry
# Create checkboxes string
checkboxes=""
for (( i=1; i<=${#logTypeKeys}; i++ )); do
    checkboxes+=" --checkbox \"${logTypeKeys[i]}\""
done

# Print the checkboxes string
echo "$checkboxes"
# Generate dialog command asking which options are going to be used
dialogCommand="/usr/local/bin/dialog --title \"Log Submission Tool\" --message \"Please select log files to submit to IT:\"\
 ${checkboxes}\
 --button1text \"OK\" --button2text \"Cancel\""

# Execute swiftDialog and store the chosen options
chosenOptions=$(eval $dialogCommand)
echo "$chosenOptions"

# Check if at least one option is selected
foundOption=false
for logName in "${logTypeKeys[@]}"; do
    if [[ "$chosenOptions" == *'"'"${logName}"'" : "true"'* ]]; then
        foundOption=true
        break
    fi
done

# Check if all options are false
if [ "$foundOption" = true ]; then
    echo "At least 1 option was selected"
    /usr/local/bin/dialog --title "Log Submission Tool" --message "Logs are being collected and submitted to IT.\\n\\nThis process will run in the background and IT will recieve a notification when logs are fully submitted" --timer 15 --hidetimerbar --timer 15 --hidetimerbar --button1text "OK"
else
    echo "No options selected, exiting without collecting any logs"
    /usr/local/bin/dialog --title "Log Submission Tool" --message "No logs were selected" --timer 15 --hidetimerbar --button1text "OK"
fi

# Process the selected logs
for logName in "${logTypeKeys[@]}"; do
    if [[ $chosenOptions == *'"'"${logName}"'" : "true"'* ]]; then
        echo "Performing the action for ${logName}"
        processLogType "${logTypeMap[$logName]}"
    fi
done
