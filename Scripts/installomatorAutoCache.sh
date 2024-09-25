#!/bin/bash
# ============================================================================
# Script Information:
# 
# Author        : Stephen Laney
# Creation Date : 9/25/2024
# Last Modified : 9/25/2024
# 
# Purpose     : Automate the download and caching of application installers using Installomator
# Usage       : Executed from a Jamf policy with a space-separated list of applications as the fourth parameter
# Contact     : Mac Admins Slack - slaney
# ============================================================================
#
# ------------------------------------------------------------------------------------------------------------------
# Script Summary:
#
# This script is used to download and cache specified applications using the Installomator tool. It ensures that the
# Installomator script is available, downloads the specified applications, handles the downloaded files, and performs
# cleanup tasks to maintain a tidy cache directory.
#
# The script contains the following main functionalities:
#   - Check if the Installomator script exists and install it if necessary.
#   - Download specified applications and save the output to a log file.
#   - Handle and organize downloaded files, renaming and moving them to the appropriate directories.
#   - Clean up old files and directories to maintain a tidy cache directory.
#
# Functions in the script:
#   - logMessage: Logs messages with a timestamp to a log file.
#   - handleDownloadedFiles: Handles the files downloaded by Installomator, moving them to the appropriate directory and renaming them as necessary.
#   - cleanupOldFilesAndDirs: Cleans up old files and directories in the application's directory, keeping only the 10 most recent items.
#   - cleanupCache: Cleans up the main cache directory to ensure a smooth run for the next application.
#
# Example file structure for cached applications:
#
# /usr/local/Installomator Cached Files/
# ├── Installomator.sh (temporary)
# ├── installomatorCachedFiles.log
# ├── app1/
# │   ├── 1.0.0.pkg
# │   └── [other versions].pkg
# ├── app2/
# │   ├── 2.1.0.dmg
# │   └── [other versions].dmg
# └── app3/
#     ├── 3.2.0/
#     │   ├── multiple files 1.app
#     │   ├── multiple files 2.app
#     │   └── [other files]
#     └── [other versions]/
#         ├── multiple files 1.app
#         ├── multiple files 2.app
#         └── [other files]
# ------------------------------------------------------------------------------------------------------------------
#
# TODO FOR ADMINS:
#
# Needs to run as ADMIN
#
# This script was originally designed to work with Jamf and so it is naturally checking $4 for passed parameters to the script, 
# which is the first parameter option when deploying a script with Jamf. If you want to use the script in a different way where a 
# different parameter is used or the titles are hardcoded into the script, then you will need to modify the very first section 
# where the array appsToCache is populated.
#
# If you are using Jamf then add the comment below as parameter 4 under options
#
# Label for Jamf Options parameter 4:
# List of Installomator labels to cache separated by spaces e.g. firefoxpkg arcbrowser zoom

# Check if $4 is provided
if [ -z "$4" ]; then
    echo "No applications specified. Please provide a space-separated list of applications as the fourth parameter."
    exit 1
fi

# Populate the array appsToCache from the fourth parameter
IFS=' ' read -r -a appsToCache <<< "$4"

# Path to the Installomator script
installomatorPath="/usr/local/installomator"
installomatorScript="$installomatorPath/Installomator.sh"

# Path to the directory where the Installomator script will be copied
cacheDir="/usr/local/Installomator Cached Files"

# Ensure the cache directory exists
mkdir -p "$cacheDir"

# Path to the copied Installomator script
copiedInstallomatorScript="$cacheDir/Installomator.sh"

# Path to the log file
logFile="$cacheDir/installomatorCachedFiles.log"

# Create the log file if it doesn't exist
touch "$logFile"

# Function to log messages
logMessage() {
    local message="$1"
    local timestamp
    
    if [ -n "$message" ]; then
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "$timestamp - $message" | tee -a "$logFile"
    else
        echo "$message" | tee -a "$logFile"
    fi
}

# Function to check and install Installomator
checkInstallomator() {
    # Check if the copied Installomator script exists, if so, skip the rest of the function
    if [ -f "${copiedInstallomatorScript}" ]; then
        logMessage "Installomator script already exists in cache directory, skipping download."
        return
    fi

    # Check if the installomatorPath exists, if not, create it
    if [ ! -d "${installomatorPath}" ]; then
        mkdir -p "${installomatorPath}"
    fi

    # Check if the installomatorScript exists, if not, download it
    if [ ! -f "${installomatorScript}" ]; then
        logMessage "Pulling Installomator from github"
        latestURL=$(curl -sSL "https://api.github.com/repos/Installomator/Installomator/releases/latest" | grep tarball_url | awk '{gsub(/[",]/,"")}{print $2}')
        tarPath="$installomatorPath/installomator.latest.tar.gz"

        curl -sSL -o "$tarPath" "$latestURL"
        tar -xz -f "$tarPath" --strip-components 1 -C "$installomatorPath"
        rm -f "$tarPath"
    fi

    # Copy the Installomator script to the cache directory
    cp "$installomatorScript" "$copiedInstallomatorScript"
    logMessage "Copied Installomator script to cache directory"

    # Remove the installomatorPath and all files/directories in it
    rm -rf "$installomatorPath"
    logMessage "Removed installomatorPath and all its contents"
}

# Function to handle downloaded files
handleDownloadedFiles() {
    local app="$1"
    local appVersion="$2"
    local appDir="$3"
    
    # Find all files in the cache directory excluding directories, .sh, .log, and .DS_Store files
    IFS=$'\n' files=($(find "$cacheDir" -maxdepth 1 \( -type f -o -type d -name "*.app" \) -not -name "Installomator.sh" -not -name "*.log" -not -name ".DS_Store"))
    
    # Log the files found
    logMessage "Files found for $app: ${files[*]}"
    
    # Check the number of files found
    fileCount=${#files[@]}
    
    if [ "$fileCount" -eq 1 ]; then
        # Only one file found, rename and move it
        logMessage "Only 1 file found, renaming and moving"
        downloadedFile="${files[0]}"
        fileExtension="${downloadedFile##*.}"
        destination="$appDir/$appVersion.$fileExtension"
        
        # Remove the destination if it's a directory
        if [ -d "$destination" ]; then
            rm -rf "$destination"
        fi
        
        mv "$downloadedFile" "$destination"
        logMessage "Downloaded file for $app moved to $destination"
    elif [ "$fileCount" -gt 1 ]; then
        # More than one file found, move them into a new directory
        logMessage "More than 1 file found, moving all files"
        newDir="$appDir/$appVersion"
        mkdir -p "$newDir"
        for file in "${files[@]}"; do
            logMessage "File moving: $file"
            destination="$newDir/$(basename "$file")"
            
            # Remove the destination if it's a directory
            if [ -d "$destination" ]; then
                rm -rf "$destination"
            fi
            
            mv "$file" "$destination"
        done
        logMessage "Multiple downloaded files for $app moved to $newDir"
    else
        logMessage "ERROR - No file was downloaded for $app"
    fi
}

# Function to clean up old files and directories
cleanupOldFilesAndDirs() {
    local appDir="$1"
    
    # Check the number of files in the app directory and delete the oldest if there are more than 10
    fileCount=$(find "$appDir" -maxdepth 1 -type f | wc -l)
    if [ "$fileCount" -gt 10 ]; then
        oldestFiles=$(find "$appDir" -maxdepth 1 -type f -print0 | xargs -0 ls -t | tail -n $((fileCount - 10)))
        while IFS= read -r file; do
            echo "Deleting file: $file"  # Debug statement
            rm "$file"
            logMessage "Deleted oldest file for $appDir: $file"
        done <<< "$oldestFiles"
    fi

    # Check the number of child directories in the app directory and delete the oldest if there are more than 10
    dirCount=$(find "$appDir" -maxdepth 1 -type d -not -name "*.app" -not -name "*.zip" | wc -l)
    if [ "$dirCount" -gt 10 ]; then
        oldestDirs=$(find "$appDir" -maxdepth 1 -type d -not -name "*.app" -not -name "*.zip" -exec stat -f "%m %N" {} \; | sort -n | head -n $((dirCount - 10)) | cut -d ' ' -f 2-)
        while IFS= read -r dir; do
            echo "Deleting directory: $dir"  # Debug statement
            rm -rf "$dir"
            logMessage "Deleted oldest directory for $appDir: $dir"
        done <<< "$oldestDirs"
    fi
}

#Function to cleanup cacheDir
cleanupCache() {
    
    # Use IFS and find command to gather files and .app directories
    IFS=$'\n' files=($(find "$cacheDir" -maxdepth 1 \( -type f -not -name "*.sh" -not -name "*.log" -not -name ".DS_Store" \) -o \( -type d -name "*.app" \)))

    # Loop through the array and delete each item
    for item in "${files[@]}"; do
        if [ -d "$item" ]; then
            logMessage "ERROR - Found app: $item in main cache dir, removing in prep for next title."
            rm -rf "$item"
        elif [ -f "$item" ]; then
            logMessage "ERROR - Found file: $item in main cache dir, removing in prep for next title."
            rm -f "$item"
        fi
    done
}

# Log the start of a new script run
logMessage "----------------------"
logMessage "Starting new script run"

# Check and install Installomator if necessary
checkInstallomator

# Loop through each application in the array
for app in "${appsToCache[@]}"; do
    logMessage ""
    logMessage "*** Starting download of $app ***"

    # Cleaning up cacheDir
    cleanupCache
    
    # Create a directory for the app if it doesn't already exist
    appDir="$cacheDir/$app"
    mkdir -p "$appDir"
    
    # Run the copied Installomator script and capture the output
    output=$("$copiedInstallomatorScript" "$app" DEBUG=1 NOTIFY=silent 2>&1)
    
    # Save the output to a .txt file in the app's directory
    echo "$output" > "$appDir/${app}_installInformation.txt"
    
    # Extract the app version from the output
    appVersion=$(echo "$output" | grep -oE " : Latest version of .* is ([0-9]+\.[0-9]+(\.[0-9]+){0,2})" | awk '{print $NF}')

    # If no app version is detected, check the next line for the version number
    if [ -z "$appVersion" ]; then
        appVersion=$(echo "$output" | awk '/ : Latest version of /{getline; print}' | grep -oE "([0-9]+\.[0-9]+(\.[0-9]+){0,2})")
    fi

    # If still no app version is detected, use the current date formatted as date.MM.DD.YY
    if [ -z "$appVersion" ]; then
        appVersion=$(date +"date.%m.%d.%y")
    fi
    
    # Log the app version for verification
    logMessage "App: $app, Version: $appVersion"
    
    # Check for errors in the output and log them
    echo "$output" | grep -i "error" | while read -r line; do
        logMessage "Error: $line"
    done
    
    # Delay for 2 seconds before moving files
    sleep 2
    
    # Handle the downloaded files
    handleDownloadedFiles "$app" "$appVersion" "$appDir"
    
    # Clean up old files and directories
    cleanupOldFilesAndDirs "$appDir"
done

logMessage "Process complete"