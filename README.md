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
2. [selfServiceLogSubmissionTool.sh]()

## Script Descriptions

### Power Assertion Management

This script is used to manage power assertions in macOS environments with Jamf management, enabling a delay in Jamf policy executions. It takes Jamf Custom Event Trigger and a set of assertions to ignore as inputs and performs the following main operations:

- Checks for active power assertions that shouldn't be ignored
- Triggers a Jamf policy event if an active power assertion matches ignored assertions
- Creates a new script and Launch Daemon if active power assertions are found, running the script every 15 minutes

This script minimizes disruptions to users while managing power assertions, for example, during video calls or when specific applications require an active display.

### Log Collection and Submission

This script is designed to collect and submit specified log files to IT in macOS environments. It allows users to select the type of log files they want to submit, processes the logs, and performs the operations:

- Creates a dialog box for users to select the log types to submit
- Defines and processes various log types (e.g., GlobalProtect, Jamf Connect Logs, and Sysdiagnose Logs)
- Collects, creates, and uploads log files to an AWS S3 bucket
- Notifies IT via Slack when log files are submitted successfully or if there are any errors

This script facilitates log file management by allowing simple log submission from users to IT through a friendly interface.
