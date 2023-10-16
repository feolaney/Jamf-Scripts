# Jamf Scripts

  

This repository contains a collection of scripts designed to be used with Jamf management for macOS devices. These scripts help manage various aspects of macOS environments, such as delaying policy executions, managing power assertions, and submitting log files to IT.

  

Some of the scripts in this repository, like the Log Collection and Submission script, require encrypted passwords or tokens to authenticate and access APIs or protected resources. These encrypted tokens need to be decrypted before they can be utilized in the script.

  

## DecryptString Function Usage

To handle the decryption, the `DecryptString` function is implemented in the scripts, allowing secure storage and usage of sensitive information. The function accepts three arguments:

  

- Encrypted String: The encrypted token or password to be decrypted

- Salt: A random data value generated during encryption to ensure uniqueness and strengthen the security of the encrypted data

- Passphrase: A secret key or password used during encryption and decryption process

  

Here's an example of how the function is used in a script:

  

bash

  

Copy code

  

```bash

workatoApiToken=$(DecryptString $4 $5 $6)

```

  

In this example,5, and $6 are the command-line arguments that need to be passed for the encrypted string, salt, and passphrase, respectively.

  

When deploying the scripts, be sure to supply the correct encrypted string, salt, and passphrase as command-line arguments, ensuring secure decryption and use of sensitive tokens or passwords within the script.

  

## Available Scripts

  

1. [jamfLocalPolicyDelay.sh](https://github.com/feolaney/Jamf-Scripts/blob/main/jamfLocalPolicyDelay.sh)
2. [selfServiceLogSubmissionTool.sh](https://github.com/feolaney/Jamf-Scripts/blob/main/Scripts/selfSerivceLogSubmissionTool.sh)
3. [updateAliasBasedOnUserName.sh](https://github.com/feolaney/Jamf-Scripts/blob/main/Scripts/updateAliasBasedOnUserName.sh)
4. [MDMIssuesReport.sh](https://github.com/feolaney/Jamf-Scripts/blob/main/Scripts/MDMIssuesReport.sh)

  

## Script Descriptions

****

### Power Assertion Management

  

This script is used to manage power assertions in macOS environments with Jamf management, enabling a delay in Jamf policy executions. It takes Jamf Custom Event Trigger and a set of assertions to ignore as inputs and performs the following main operations:

  

- Checks for active power assertions that shouldn't be ignored

- Triggers a Jamf policy event if an active power assertion matches ignored assertions

- Creates a new script and Launch Daemon if active power assertions are found, running the script every 15 minutes

  

This script minimizes disruptions to users while managing power assertions, for example, during video calls or when specific applications require an active display.

****

### Log Collection and Submission

  

This script is designed to collect and submit specified log files to IT in macOS environments. It allows users to select the type of log files they want to submit, processes the logs, and performs the operations:

  

- Creates a dialog box for users to select the log types to submit

- Defines and processes various log types (e.g., GlobalProtect, Jamf Connect Logs, and Sysdiagnose Logs)

- Collects, creates, and uploads log files to an AWS S3 bucket

- Notifies IT via Slack when log files are submitted successfully or if there are any errors

  

This script facilitates log file management by allowing simple log submission from users to IT through a friendly interface.

  

==**Homework for the user**==

The script provided was initially created with the help of an automation service that generated the AWS PreSigned URL using an AWS Lambda Function. This approach was used to securely generate the AWS Upload URL off the local device, avoiding the need to share API credentials. In order for this script to be effectively adopted and used, this function may need to be replicated or replaced to suit your specific needs.

  

The `generateS3BucketURL` function is responsible for initiating the creation of the AWS PreSigned URL. It was observed that the URL generation process took between 1 to 3 minutes when using the automation API. To account for this delay, a UUID was returned by the function, which could then be supplied to the automation resource to collect the URL when finished.

  

This process can be seen in the `generateS3BucketURL` function, where the UUID is collected. Then, within the locally created script from lines 282-307, the UUID is used to check if the URL has been generated. The script will periodically check for the URL generation before proceeding to upload the logs.

  

For more information on AWS Lambda Function invocations and related API documentation, refer to the following resources:

  

- [Invoking AWS Lambda Functions](https://docs.aws.amazon.com/lambda/latest/dg/urls-invocation.html)

- [Invoke in AWS Lambda API Documentation](https://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html)

****
### Local Alias Creation
Alias Creation Based on Asset Inventory System This script is used to add a macOS local user alias based on information pulled from an external asset inventory system. The script performs the following main operations:

- Fetches user information from external asset management system
- Extracts the first name of the assigned user
- Checks if the alias already exists for the current user
- If not, sets the alias for the current user

This script automates the process of alias creation for macOS users, simplifying user management in systems integrated with external asset inventory systems.

****

###MDM Failed Errors Search

  

This script is designed to interact with the Jamf API, to perform a series of checks on a group of computers managed by Jamf Pro, and to identify computers with specific status messages. It takes a list of status messages and smart group's ID as input, checks the command history for each computer within the smart group, and identifies computers with a history item containing any of the specified status messages. The script provides a summary of the IDs of computers, for each status message, along with respective URLs to access the records of the computers on the Jamf Pro web interface.

Script could run for a while if the search smart group is large

**Variables to Set:**

- `apiUser`: Set this variable to the username of the Jamf Pro API user. This is required for making API requests.
    
- `jssApiPassword`: Set this variable to the password for the Jamf Pro API user. This is also required for making API requests.
    
- `smartGroupId`: Set this variable to the ID number of the smart group in your Jamf Pro system. All computers within this group will be checked.

- `reportLocation`: Set this variable if you want the report saved to a .txt file. The current date will be appended to the end of the filename as to not delete/copy over an existing report
    
- `statusTexts`: This variable is an array of status messages. The script will attempt to find these statuses in each computer's command history. Set the statuses according to the issues you want to identify. For example, a status message might indicate a problem with MDM communication or that a required configuration profile is missing.
	- Example: `statusTexts=("The device token is not active for the specified topic." "Another status message")`