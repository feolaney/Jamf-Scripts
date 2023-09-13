#!/bin/bash

#                 Name: Jamf Policy delay script
#           Created by: Stephen Laney                
#          Description: Check macOS power assertions to delay the execution of Jamf policies using launchd
#        Creation date: 05/18/2023
#   Last Modified Date: 09/12/2023
#            More Info: 
#           Disclaimer: This script is provided "as is", without warranty of any kind, express or implied. In no event will the 
#                       author be held liable for any damages or consequences arising from the use of this script.


# This script is designed to manage power assertions in a macOS environment with Jamf management.
# The purpose is to check for any active power assertions that prevent the display from going idle or sleep. 
# Intended power assertions this script is concerned with are video call assertions, as to not disrupt users when in video calls.
# Power assertios that are normal can be ignored with the assertionsToIgnore variable.  The follwing are examples of assertions to ignore:
# firefox,Google Chrome,Safari,Microsoft Edge,Opera,Amphetamine,caffeinate,Jolt of Caffeine,Garmin Express Map Updates

# The script receives two inputs, a Jamf Custom Event Trigger and a set of assertions to ignore.
# These inputs can be passed as command-line arguments when the script is called.

# The script starts by checking for any active power assertions that should not be ignored.
# If such assertions are found, the script notifies that they were detected and exits.

# If an active power assertion matches one in the list of assertions to ignore, 
# the script triggers a Jamf policy event using the provided custom event trigger and exits.

# If  active power assertions are found
# the script creates a new script file in /var/tmp directory. This new script essentially performs the same functions as the original script, 
# checking for power assertions, and reacting accordingly. 

# The script then creates a Launch Daemon that runs the new script every 15 minutes.
# The Launch Daemon is unloaded and the script file is deleted each time the new script is run successfully. 

# This ensures the system continues to check for power assertions periodically 
# and takes appropriate actions as specified by the script.  When conditions are correct then the Jamf Policy will run
# and the script will remove/clean the Launch Daemon and Script


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
