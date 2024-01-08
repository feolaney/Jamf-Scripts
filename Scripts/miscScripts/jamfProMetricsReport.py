import requests
import subprocess

# read jamf url from system defaults
myJssBaseurl = subprocess.getoutput("/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url")
jamf_url = f"{myJssBaseurl}api/v1/jamf-management-framework/redeploy/"

# your bearer token
bearer_token = '<bearer_token_here>'
headers = {'Authorization': 'Bearer %s' % bearer_token}

#Your smart groups IDs
smart_group_ids = ['<id1>', '<id2>', '<id3>',...] #Replace with your IDs

def get_info_smartgroup(smart_group_id):
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
    # We will get group name and computers count from response. 
    group_name = data['name']
    computers_count = len(data['computers'])

    return (group_name, computers_count)

if __name__ == "__main__":
    results = []
    for gid in smart_group_ids:
        results.append(get_info_smartgroup(gid))

    #Sort results by number of computers in DESC order
    sorted_results = sorted(results, key=lambda x:x[1], reverse=True)

    #Print the results
    for res in sorted_results:
        print('Smart Group Name: {}, Number of Computers: {}'.format(res[0],res[1]))