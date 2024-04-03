import requests
import json

# Base URL for the local node RPC
LOCAL_NODE_RPC_URL = 'http://localhost:26657'

# List of endpoints to fetch data from
endpoints = [
    'status',
    'net_info',
    'abci_info',
    'consensus_state',
]

def fetch_data(url):
    """Fetch data from a given URL."""
    try:
        response = requests.get(url)
        response.raise_for_status()  # Raises error for 4xx/5xx responses
        return response.json()
    except requests.RequestException as e:
        print(f"Error fetching data from {url}: {e}")
        return None

def dump_data():
    """Fetch and dump data from specified endpoints."""
    dumped_data = {}
    for endpoint in endpoints:
        full_url = f"{LOCAL_NODE_RPC_URL}/{endpoint}"
        data = fetch_data(full_url)
        dumped_data[endpoint] = data
        print(f"\n{endpoint} Data:")
        print(json.dumps(data, indent=4))

    # Optionally, save all fetched data to a file for easier review
    with open('node_data_dump.json', 'w') as file:
        json.dump(dumped_data, file, indent=4)

if __name__ == '__main__':
    dump_data()
