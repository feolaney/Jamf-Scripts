import requests
import sys
import subprocess
from getpass import getpass
from xml.etree import ElementTree

# read jamf url from system defaults
myJssBaseurl = subprocess.getoutput("/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url")

# Ask for bearer token
bearer_token = getpass('Please enter bearer token: ')

headers = {'Authorization': 'Bearer %s' % bearer_token}

#Your smart groups IDs
smart_group_ids = ['296', '297', '298','299','377']

def get_info_smartgroup(smart_group_id):
    # your JAMF Pro endpoint
    print(f'{myJssBaseurl}JSSResource/computergroups/id/{smart_group_id}')
    endpoint = f'{myJssBaseurl}JSSResource/computergroups/id/{smart_group_id}'

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
    group_name = data.find("name").text
    computers_count = len(data.findall(".//computer"))

    return (group_name, computers_count)

if __name__ == "__main__":
    results = []
    total_count = 0 

    for gid in smart_group_ids:
        smartgroup_info = get_info_smartgroup(gid)

        # handle case where get_info_smartgroup returns None
        if smartgroup_info is not None:
            results.append(smartgroup_info)
            total_count += smartgroup_info[1]

    # It's now the order they were checked, because we don't sort it anymore
    #Print the results
    for res in results:
        print('Smart Group Name: {}, Number of Computers: {}'.format(res[0],res[1]))

    # Print total count
    print('Total Number of Computers: {}'.format(total_count))