import requests
import subprocess
from getpass import getpass
from xml.etree import ElementTree

# read Jamf Pro URL from system defaults
myJssBaseurl = subprocess.getoutput("/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url")

# Ask for bearer token
bearerToken = getpass('Please enter bearer token: ')
headers = {'Authorization': 'Bearer %s' % bearerToken}

# List of smart group IDs to check
smartGroupIDs = ['1', '2', '3', '4', '5']

# IDs of separate groups to be totalled separately
totalEnrolledDevices = ['1', '2', '3', '4', '5']

def getInfoSmartGroup(smartGroupID):
    # Formatting API endpoint URL
    endpoint = f'{myJssBaseurl}JSSResource/computergroups/id/{smartGroupID}'

    # Sending GET request and handling possible HTTP error
    try:
        response = requests.get(endpoint, headers=headers)
        response.raise_for_status()
    except requests.exceptions.HTTPError as errh:
        print ("HTTP Error:", errh)
        return None

    # Parsing XML response and retrieving group name and computer count
    data = ElementTree.fromstring(response.content)
    groupName = data.find("name").text
    computerCount = len(data.findall(".//computer"))

    return (groupName, computerCount)

if __name__ == "__main__":
    results = []
    totalCount = 0 

    # Looping over smartGroupIDs to get group info and update total count
    for gid in smartGroupIDs:
        smartgroupInfo = getInfoSmartGroup(gid)
        if smartgroupInfo is not None:
            results.append(smartgroupInfo)
            totalCount += smartgroupInfo[1]

    # Output smart group information
    for res in results:
        print('Smart Group Name: {}, Number of Computers: {}'.format(res[0], res[1]))

    # Print total count across all smart groups
    print('Total Number of Computers: {}'.format(totalCount))

    # Processing separate groups
    print('Separate Groups:')
    for gid in totalEnrolledDevices:
        smartgroupInfo = getInfoSmartGroup(gid)
        if smartgroupInfo is not None:
            print('Smart Group Name: {}, Number of Computers: {}'.format(smartgroupInfo[0], smartgroupInfo[1]))
