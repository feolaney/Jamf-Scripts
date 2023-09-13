#!/bin/bash

# ============================================================================
# Script Information:
# 
# Author        : Stephen Laney
# Creation Date : 2023-05-18
# Last Modified : 2023-09-12
# 
# Purpose     : Delay the execution of Jamf policies using launchd by checking macOS power assertions
# Usage       : Integrated with Jamf policy management for macOS systems
# Contact     : Mac Admins Slack - slaney
# 
# Disclaimer  : This script is provided "as is", without warranty of any kind, express or implied. In no event will the 
#               author be held liable for any damages or consequences arising from the use of this script.
# ============================================================================


# ------------------------------------------------------------------------------------------------------------------
# Script Summary:
#
# This script is designed to manage power assertions in a macOS environment with Jamf management to delay the execution of Jamf policies using launchd. It checks for active power assertions that prevent the display from going idle or sleep and intelligently avoids disrupting users while they are in video calls or using specific applications that require the display to be active.
#
# The script contains the following main functionalities:
#   - Check for any active power assertions that should not be ignored and notify if detected.
#   - Trigger a Jamf policy event if an active power assertion matches one in the list of ignored assertions.
#   - Create a new script file in /var/tmp directory and a Launch Daemon that runs the new script every 15 minutes if active power assertions are found.
#   - Unload the Launch Daemon and delete the script file each time the new script is run successfully.
#
# Functions in the script:
#   - createScript: Creates a new script file that checks for power assertions and triggers the Jamf policy if conditions are met.
#   - createDaemon: Creates a Launch Daemon that runs the newly created script at a specified interval.
#
# To accommodate new assertions, modify the list of assertions to ignore passed through the input variable $5.
# ------------------------------------------------------------------------------------------------------------------

# This script manages power assertions in macOS environments with Jamf management to delay Jamf policy executions.
# It checks for active power assertions (e.g. video call assertions) and reacts without disrupting users.

# The script takes two inputs: a Jamf Custom Event Trigger and a set of assertions to ignore (comma-separated).
# These can be passed as command-line arguments.

# Workflow:
# 1. Checks for active power assertions that shouldn't be ignored. If found, notifies and exits.
# 2. Triggers Jamf policy event if an active power assertion matches ignored assertions.
# 3. If active power assertions found, creates a new script (in /var/tmp) and a Launch Daemon running every 15 minutes.
# 4. When the new script runs successfully, unloads Launch Daemon, deletes script file, and triggers the Jamf policy.
# 5. Cleans up the Launch Daemon and script upon completion.


# There are multiple types of power assertions an app can assert.
# These specifically tend to be used when an app wants to try and prevent the OS from going to display sleep.
# Scenarios where an app may not want to have the display going to sleep include, but are not limited to:
#   Presentation (KeyNote, PowerPoint)
#   Web conference software (Zoom, Webex)
#   Screen sharing session
# Apps have to make the assertion and therefore it's possible some apps may not get captured.
# Some assertions can be found here: https://developer.apple.com/documentation/iokit/iopmlib_h/iopmassertiontypes

# This variable should be set in Jamf as the custom policy trigger that should run if no power assertions are found

jamfCustomEventTrigger="$4"

# This variable should be a list of the power assertions that should be ignored separated by commas, i.e.
# firefox,Google Chrome,Safari,Microsoft Edge,Opera,Amphetamine,caffeinate,Jolt of Caffeine,Garmin Express Map Updates

assertionsToIgnore="$5"

# When run this will contain all active power assertions
activeAssertions="$(/usr/bin/pmset -g assertions | /usr/bin/awk '/NoDisplaySleepAssertion | PreventUserIdleDisplaySleep/ && match($0,/\(.+\)/) && ! /coreaudiod/ {gsub(/^\ +/,"",$0); print};')"

# ---------------------------------
# ---------------------------------
# Functions
# ---------------------------------
# ---------------------------------

# Function to create power assertion script
function createScript {
    cat << EOF > "/var/tmp/powerassertion$jamfCustomEventTrigger.sh"
#!/bin/bash


jamfCustomEventTrigger="$jamfCustomEventTrigger"
assertionsToIgnore="$assertionsToIgnore"
activeAssertions="\$(/usr/bin/pmset -g assertions | /usr/bin/awk '/NoDisplaySleepAssertion | PreventUserIdleDisplaySleep/ && match(\$0,/\\(.+\\)/) && ! /coreaudiod/ {gsub(/^\\ +/,"",\$0); print};')"

# Set the path of the script and the log file
scriptPath=\$(dirname "\$0")
logFile="\$scriptPath/powerassertion\$jamfCustomEventTrigger.log"

# Function to log command output
log_command_output() {
    "\$@" >> "\$logFile" 2>&1
    echo "error code: $?" >> "\$logFile"
    echo >> "\$logFile"
}

# Log the current date
currentDate=\$(date +"%Y-%m-%d %H:%M:%S")
log_command_output echo "********************\\nStarting script at: \$currentDate \\n********************" >> "\$logFile"

launchPath="/Library/LaunchDaemons/com.jamf.powerassertion\$jamfCustomEventTrigger.plist"

log_command_output echo "assertionsToIgnore = \$assertionsToIgnore"
log_command_output echo "jamfCustomEventTrigger = \$jamfCustomEventTrigger"
log_command_output echo "launchPath = \$launchPath"

if [[ "\$activeAssertions" ]]; then
    log_command_output echo "The following display-related power assertions have been detected:"
    log_command_output echo "\$activeAssertions"
        
    OIFS=\$IFS
    IFS=","
    
    for Assertion in \$assertionsToIgnore; do
        if grep -i -q "\$Assertion" <<< "\$activeAssertions"; then
            echo "An ignored display sleep assertion has been detected: \$Assertion"
            echo "All display sleep assertions are going to be ignored."
            sudo launchctl bootout system "\$launchPath"
            rm -f "\$launchPath"
            rm -f "/var/tmp/powerassertion\$jamfCustomEventTrigger.sh"
            /usr/local/bin/jamf policy -event \$jamfCustomEventTrigger
            exit 0
        fi
    done
    
    IFS=\$OIFS
    
    log_command_output echo "Exiting script to avoid disrupting user while these power assertions are active."
    
    exit 1
fi


# Log the commands and their output
log_command_output echo "No detected power assertions"
log_command_output /usr/local/bin/jamf policy -event "\$jamfCustomEventTrigger"
log_command_output sudo rm -f "/var/tmp/powerassertion\$jamfCustomEventTrigger.sh"
log_command_output sudo rm -f "\$launchPath"
log_command_output sudo launchctl remove com.jamf.powerassertion\$jamfCustomEventTrigger




# echo "No detected power assertions"
# sudo launchctl bootout system "\$launchPath"
# sudo rm -f "\$launchPath"
# sudo rm -f "/var/tmp/powerassertion\$jamfCustomEventTrigger.sh"
# /usr/local/bin/jamf policy -event \$jamfCustomEventTrigger
exit 0
EOF

# Make the script executable
chmod +x "/var/tmp/powerassertion$jamfCustomEventTrigger.sh"
}

# Function to create Launch Daemon
function createDaemon {
    #Define the variable
    launchPath="/Library/LaunchDaemons/com.jamf.powerassertion$jamfCustomEventTrigger.plist"

    #############
    if [[ -f "$launchPath" ]];then
        sudo launchctl bootout system "$launchPath"
        rm -f "$launchPath"
    else
        echo "No daemon found."
    fi

    #Create the daemon
    #Create a label
    defaults write "$launchPath" Label com.jamf.powerassertion$jamfCustomEventTrigger
    #Create a program with an array
    defaults write "$launchPath" ProgramArguments -array "/bin/sh" "/var/tmp/powerassertion$jamfCustomEventTrigger.sh"
    #Start or RUN at load.
    defaults write "$launchPath" RunAtLoad -boolean true
    # Set to run every 15 minutes
    defaults write "$launchPath" StartInterval -integer 120
    ############################
    ##Change permissions and ownership of the daemon####
    chmod 755 "$launchPath"
    chown root:wheel "$launchPath"

    ##Load the daemon####
    sudo launchctl bootstrap system "$launchPath"
}

# Checking for power assertions and creating Launch Daemon/script process to continue checking if power assertions are running
# ---------------------------------
# ---------------------------------

if [[ "$activeAssertions" ]]; then
    echo "The following display-related power assertions have been detected:"
    echo "$activeAssertions"
      
    OIFS=$IFS
    IFS=,
    
    for Assertion in $assertionsToIgnore; do
        if grep -i -q "$Assertion" <<< "$activeAssertions"; then
            echo "An ignored display sleep assertion has been detected: $Assertion"
            echo "All display sleep assertions are going to be ignored."
            /usr/local/bin/jamf policy -event $jamfCustomEventTrigger
            exit 0
        fi
    done
    
    IFS=$OIFS
    
    echo "Exiting script to avoid disrupting user while these power assertions are active."
    createScript
    createDaemon
    exit 0
fi
echo "No detected power assertions"
/usr/local/bin/jamf policy -event $jamfCustomEventTrigger
exit 0
