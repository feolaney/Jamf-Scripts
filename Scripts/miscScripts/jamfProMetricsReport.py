import requests
import subprocess
import json

# read jamf url from system defaults
myJssBaseurl = subprocess.getoutput("/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url")
jamf_url = f"{myJssBaseurl}api/v1/jamf-management-framework/redeploy/"

# your bearer token
bearer_token = '<bearer_token_here>'
headers = {'Authorization': 'Bearer %s' % bearer_token}

#Id of your smart group
smart_group_id = '<smart_group_id_here>'

def get_computers_in_smartgroup():
    # your JAMF Pro end point - replace placeholder with actual endpoint
    endpoint = f'{jamf_url}/JSSResource/advancedcomputersearches/id/{smart_group_id}'

    # send a GET request to the JAMF Pro end point
    response = requests.get(endpoint, headers=headers)

    # handle response
    if response.status_code != 200:
        print('Error with status {}: ', response.content )
        sys.exit()

    # get the JSON response body
    data = response.json()

    # We will check computers from response. 
    computers = data.get('computers')

    # print each computer's OS version
    for computer in computers:
        print("Computer with id: {} has OS version: {}".format(computer['id'], computer['os_version']))

if __name__ == "__main__":
    get_computers_in_smartgroup()