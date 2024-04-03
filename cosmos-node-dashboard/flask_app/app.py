from flask import Flask, render_template, Response, request, jsonify, send_file
import json
import subprocess
from datetime import datetime
from threading import Thread, Event
import requests
import tempfile
import os

app = Flask(__name__, template_folder='templates')

LOCAL_NODE_RPC_URL = 'http://akash:26657'
LCD_API_URL = 'http://akash:1317'
RPC_REQUEST_INTERVAL = 5  # Interval in seconds between RPC requests

def send_rpc_request(method, params=None):
    try:
        if params is None:
            params = []
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params
        }
        cmd = f'curl -s "{LOCAL_NODE_RPC_URL}" -H "Content-Type: application/json" -d \'{json.dumps(payload)}\''
        result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        # Debug output
        print(f"RPC Request - Method: {method}, Params: {params}")
        print(f"RPC Response - Status Code: {result.returncode}, Output: {result.stdout.decode('utf-8')}, Error: {result.stderr.decode('utf-8')}")
        
        return json.loads(result.stdout.decode('utf-8'))
    except Exception as e:
        print(f"Error sending RPC request: {e}")
        return None

def update_config(key, value):
    try:
        with open('config.toml', 'r') as file:
            config = file.read()

        config = config.replace(f'{key} = false', f'{key} = {value}')

        with open('config.toml', 'w') as file:
            file.write(config)

        restart_node()
        return True
    except IOError as e:
        print(f"Error updating config: {e}")
        return False

def restart_node():
    try:
        subprocess.run(['systemctl', 'restart', 'akash-node'])
    except subprocess.CalledProcessError as e:
        print(f"Error restarting node: {e}")

@app.route('/')
def index():
    return render_template('index.html')

def fetch_node_status(stop_event):
    while not stop_event.is_set():
        status_data = send_rpc_request('status')
        net_info_data = send_rpc_request('net_info')

        if not status_data or not net_info_data or 'error' in status_data or 'error' in net_info_data:
            print("Error fetching node status data:")
            print(f"Status Data: {status_data}")
            print(f"Net Info Data: {net_info_data}")
            yield None
        else:
            node_info = status_data['result']['node_info']
            sync_info = status_data['result']['sync_info']
            validator_info = status_data['result']['validator_info']

            response_data = {
                'node_info': {
                    'id': node_info['id'],
                    'network': node_info['network'],
                    'version': node_info['version'],
                    'moniker': node_info['moniker']
                },
                'net_info': {
                    'listening': net_info_data['result']['listening'],
                    'listeners': net_info_data['result']['listeners'],
                    'n_peers': net_info_data['result']['n_peers'],
                    'peers': net_info_data['result']['peers']
                },
                'sync_info': {
                    'catching_up': sync_info['catching_up'],
                    'latest_block_height': sync_info['latest_block_height']
                },
                'validator_info': {
                    'address': validator_info['address'],
                    'voting_power': validator_info['voting_power']
                },
                'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            }

            print(f"Node Status Data: {response_data}")
            yield response_data

        stop_event.wait(RPC_REQUEST_INTERVAL)

@app.route('/node_status')
def node_status():
    stop_event = Event()
    node_status_generator = fetch_node_status(stop_event)

    def event_stream():
        try:
            for status_data in node_status_generator:
                if status_data:
                    yield f"data: {json.dumps(status_data)}\n\n"
                else:
                    yield f"data: {json.dumps({'error': 'Failed to fetch node status data'})}\n\n"
        finally:
            stop_event.set()

    return Response(event_stream(), mimetype='text/event-stream')

@app.route('/create_wallet', methods=['POST'])
def create_wallet():
    try:
        # Generate a new wallet using the LCD API
        response = requests.post(f"{LCD_API_URL}/cosmos/auth/v1beta1/accounts", json={})
        response.raise_for_status()
        account_data = response.json()

        # Extract relevant account information
        account_address = account_data['account']['@type']
        account_pubkey = account_data['account']['pub_key']
        account_sequence = account_data['account']['sequence']

        # Create a temporary file for the wallet backup
        with tempfile.NamedTemporaryFile(delete=False) as backup_file:
            # Write the wallet backup data to the file
            backup_data = {
                'address': account_address,
                'pubkey': account_pubkey,
                'sequence': account_sequence
            }
            backup_file.write(json.dumps(backup_data).encode('utf-8'))
            backup_file_path = backup_file.name

        # Return the account information and backup file path
        return jsonify({
            'address': account_address,
            'pubkey': account_pubkey,
            'sequence': account_sequence,
            'backup_file': backup_file_path
        })
    except requests.RequestException as e:
        print(f"Error creating wallet: {e}")
        return jsonify({'error': 'Failed to create wallet'}), 500

@app.route('/download_backup/<path:backup_file>')
def download_backup(backup_file):
    return send_file(backup_file, as_attachment=True)

@app.route('/restore_wallet', methods=['POST'])
def restore_wallet():
    try:
        # Get the restore method and data from the request
        restore_method = request.form['restore_method']
        
        if restore_method == 'backup':
            # Restore wallet from backup file
            backup_file = request.files['backup_file']
            backup_data = json.load(backup_file)
            account_address = backup_data['address']
            account_pubkey = backup_data['pubkey']
            account_sequence = backup_data['sequence']
        elif restore_method == 'mnemonic':
            # Restore wallet from mnemonic phrase
            mnemonic = request.form['mnemonic']
            # Use the LCD API to restore the wallet from the mnemonic phrase
            response = requests.post(f"{LCD_API_URL}/cosmos/auth/v1beta1/accounts/mnemonic", json={'mnemonic': mnemonic})
            response.raise_for_status()
            account_data = response.json()
            account_address = account_data['address']
            account_pubkey = account_data['pubkey']
            account_sequence = account_data['sequence']
        elif restore_method == 'private_key':
            # Restore wallet from private key
            private_key = request.form['private_key']
            # Use the LCD API to restore the wallet from the private key
            response = requests.post(f"{LCD_API_URL}/cosmos/auth/v1beta1/accounts/private_key", json={'private_key': private_key})
            response.raise_for_status()
            account_data = response.json()
            account_address = account_data['address']
            account_pubkey = account_data['pubkey']
            account_sequence = account_data['sequence']
        else:
            return jsonify({'error': 'Invalid restore method'}), 400

        # Return the restored account information
        return jsonify({
            'address': account_address,
            'pubkey': account_pubkey,
            'sequence': account_sequence
        })
    except (requests.RequestException, KeyError, json.JSONDecodeError) as e:
        print(f"Error restoring wallet: {e}")
        return jsonify({'error': 'Failed to restore wallet'}), 500

@app.route('/enable_api', methods=['POST'])
def enable_api():
    success = update_config('api', 'true')
    if success:
        return jsonify({'message': 'API enabled successfully'})
    else:
        return jsonify({'error': 'Failed to enable API'}), 500

@app.route('/enable_rpc', methods=['POST'])
def enable_rpc():
    success = update_config('rpc', 'true')
    if success:
        return jsonify({'message': 'RPC enabled successfully'})
    else:
        return jsonify({'error': 'Failed to enable RPC'}), 500

@app.route('/restore_validator', methods=['POST'])
def restore_validator():
    # Implement the logic to create a validator using the form data
    # Access the form data using request.form['moniker'], request.form['pubkey'], etc.
    # Perform the necessary operations to create the validator

    return jsonify({'message': 'Validator created successfully'})


@app.route('/create_validator', methods=['POST'])
def create_validator():
    # Implement the logic to create a validator using the form data
    # Access the form data using request.form['moniker'], request.form['pubkey'], etc.
    # Perform the necessary operations to create the validator

    return jsonify({'message': 'Validator created successfully'})

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
