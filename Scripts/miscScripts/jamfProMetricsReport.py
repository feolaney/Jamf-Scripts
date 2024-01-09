import requests
import sys
import subprocess
from getpass import getpass
from xml.etree import ElementTree

# read jamf url from system defaults
myJssBaseurl = subprocess.getoutput("/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url")

# Ask for bearer token
bearerToken = getpass('Please enter bearer token: ')

headers = {'Authorization': 'Bearer %s' % bearerToken}

#Your smart groups IDs
smartGroupIDs = ['296', '297', '298','299','377']
# Add your new separate group ids
totalEnrolledDevices = ['1', '203']

def getInfoSmartGroup(smartGroupID):
    # your JAMF Pro endpoint
    endpoint = f'{myJssBaseurl}JSSResource/computergroups/id/{smartGroupID}'

    # send a GET request to the JAMF Pro endpoint
    try:
        response = requests.get(endpoint, headers=headers)
        response.raise_for_status()
    except requests.exceptions.HTTPError as errh:
        print ("HTTP Error:", errh)
        return None

    # get the XML response body
    data = ElementTree.fromstring(response.content)

    # We will get group name and computers count from response.
    groupName = data.find("name").text
    computerCount = len(data.findall(".//computer"))

    return (groupName, computerCount)

if __name__ == "__main__":
    results = []
    totalCount = 0 

    for gid in smartGroupIDs:
        smartgroupInfo = getInfoSmartGroup(gid)

        # handle case where getInfoSmartGroup returns None
        if smartgroupInfo is not None:
            results.append(smartgroupInfo)
            totalCount += smartgroupInfo[1]

    #Print the results
    for res in results:
        print('Smart Group Name: {}, Number of Computers: {}'.format(res[0],res[1]))

    # Print total count
    print('Total Number of Computers: {}'.format(totalCount))

    # Now deal with the separate groups
    print('Separate Groups:')
    for gid in totalEnrolledDevices:
        smartgroupInfo = getInfoSmartGroup(gid)
        if smartgroupInfo is not None:
            print('Smart Group Name: {}, Number of Computers: {}'.format(smartgroupInfo[0], smartgroupInfo[1]))