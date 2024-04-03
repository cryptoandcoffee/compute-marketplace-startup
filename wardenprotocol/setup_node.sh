#!/bin/bash

# Setting up environment variables
MONIKER=${MONIKER:-"spheron.network"}
CHAIN_ID="alfama"
WARDEN_HOME="$HOME/.warden"
CONFIG_FOLDER="$WARDEN_HOME/config"
KEYRING_BACKEND="test"
KEY_NAME="validator"
PUBLIC_RPC_ENDPOINT="https://rpc.alfama.wardenprotocol.org:443"

# Function to display the first page
display_first_page() {
  cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Validator Setup</title>
</head>
<body>
    <h1>Validator Setup</h1>
    <a href="/create_wallet">Create New Wallet</a>
    <br>
    <a href="/import_wallet">Import Wallet</a>
</body>
</html>
EOF
}

# Function to display the create wallet page
display_create_wallet_page() {
  cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Create New Wallet</title>
    <script>
        function saveVariables() {
            var data = {
                moniker: document.getElementById('moniker').value,
                identity: document.getElementById('identity').value,
                about: document.getElementById('about').value,
                website: document.getElementById('website').value,
                contact: document.getElementById('contact').value
            };
            
            fetch('/save_variables', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            })
            .then(response => response.text())
            .then(result => { window.location.href = '/start'; });
        }
        
        function checkBalance() {
            fetch('/check_balance')
                .then(response => response.json())
                .then(data => { document.getElementById('balance').textContent = data.balance; });
        }
        
        setInterval(checkBalance, 5000);
    </script>
</head>
<body>
    <h1>Create New Wallet</h1>
    <p>Wallet Address: <span id="wallet_address"></span></p>
    <p>Balance: <span id="balance"></span></p>
    
    <form onsubmit="saveVariables(); return false;">
        <label for="moniker">Moniker:</label>
        <input type="text" id="moniker" name="moniker" value="spheron.network" required><br>
        
        <label for="identity">Identity:</label>
        <input type="text" id="identity" name="identity" value="spheron.network" required><br>
        
        <label for="about">About:</label>
        <textarea id="about" name="about" required></textarea><br>
        
        <label for="website">Website:</label>
        <input type="url" id="website" name="website" required><br>
        
        <label for="contact">Contact:</label>
        <input type="text" id="contact" name="contact" required><br>
        
        <button type="submit">Save</button>
    </form>
</body>
</html>
EOF
}

# Function to display the import wallet page
display_import_wallet_page() {
  cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Import Wallet</title>
    <script>
        function importWallet() {
            var fileInput = document.getElementById('validator_json');
            var file = fileInput.files[0];
            var reader = new FileReader();
            
            reader.onload = function(e) {
                var validatorData = JSON.parse(e.target.result);
                fetch('/import_wallet', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(validatorData)
                })
                .then(response => response.text())
                .then(result => { window.location.href = '/create_wallet'; });
            };
            
            reader.readAsText(file);
        }
    </script>
</head>
<body>
    <h1>Import Wallet</h1>
    <input type="file" id="validator_json" accept=".json">
    <button onclick="importWallet()">Import</button>
</body>
</html>
EOF
}

# Function to display the start page
display_start_page() {
  cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Start Validator</title>
    <script>
        function startValidator() {
            fetch('/start_validator', { method: 'POST' })
                .then(response => response.text())
                .then(result => { document.getElementById('status').textContent = 'Validator started successfully!'; });
        }
    </script>
</head>
<body>
    <h1>Start Validator</h1>
    <p>Moniker: <span id="moniker"></span></p>
    <p>Identity: <span id="identity"></span></p>
    <p>About: <span id="about"></span></p>
    <p>Website: <span id="website"></span></p>
    <p>Contact: <span id="contact"></span></p>
    
    <a href="/validator.json" download>Download validator.json</a>
    <br>
    <button onclick="startValidator()" id="start_button" disabled>Start</button>
    
    <p id="status"></p>
    
    <script>
        fetch('/get_variables')
            .then(response => response.json())
            .then(data => {
                document.getElementById('moniker').textContent = data.moniker;
                document.getElementById('identity').textContent = data.identity;
                document.getElementById('about').textContent = data.about;
                document.getElementById('website').textContent = data.website;
                document.getElementById('contact').textContent = data.contact;
                document.getElementById('start_button').disabled = false;
            });
    </script>
</body>
</html>
EOF
}

# Function to configure Nginx
configure_nginx() {
  mv /nginx-default.conf /etc/nginx/nginx.conf
  cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    server_name _;

    location / {
        proxy_pass http://localhost:8080;
    }
}
EOF
  nginx -s reload
  echo "Starting nginx..."
  /etc/init.d/nginx start
}

# Function to save variables from the form
save_variables() {
  MONIKER=$(echo "$1" | jq -r '.moniker')
  IDENTITY=$(echo "$1" | jq -r '.identity')
  ABOUT=$(echo "$1" | jq -r '.about')
  WEBSITE=$(echo "$1" | jq -r '.website')
  CONTACT=$(echo "$1" | jq -r '.contact')
  
  echo "MONIKER=$MONIKER" > /root/variables
  echo "IDENTITY=$IDENTITY" >> /root/variables
  echo "ABOUT=$ABOUT" >> /root/variables
  echo "WEBSITE=$WEBSITE" >> /root/variables
  echo "CONTACT=$CONTACT" >> /root/variables
  
  cat > validator.json <<EOF
{
  "pubkey": "",
  "amount": "1000000uward",
  "moniker": "$MONIKER",
  "identity": "$IDENTITY",
  "website": "$WEBSITE",
  "security": "",
  "details": "$ABOUT",
  "commission-rate": "0.1",
  "commission-max-rate": "0.2",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}
EOF
}

# Function to import wallet from validator.json
import_wallet() {
  RESTORE=$(cat)
  MONIKER=$(echo "$RESTORE" | jq -r '.moniker')
  IDENTITY=$(echo "$RESTORE" | jq -r '.identity')
  ABOUT=$(echo "$RESTORE" | jq -r '.details')
  WEBSITE=$(echo "$RESTORE" | jq -r '.website')
  CONTACT=$(echo "$RESTORE" | jq -r '.contact')
  
  echo "MONIKER=$MONIKER" > /root/variables
  echo "IDENTITY=$IDENTITY" >> /root/variables
  echo "ABOUT=$ABOUT" >> /root/variables
  echo "WEBSITE=$WEBSITE" >> /root/variables
  echo "CONTACT=$CONTACT" >> /root/variables
}

# Function to get variables for the start page
get_variables() {
  MONIKER=$(grep MONIKER /root/variables | cut -d'=' -f2)
  IDENTITY=$(grep IDENTITY /root/variables | cut -d'=' -f2)
  ABOUT=$(grep ABOUT /root/variables | cut -d'=' -f2)
  WEBSITE=$(grep WEBSITE /root/variables | cut -d'=' -f2)
  CONTACT=$(grep CONTACT /root/variables | cut -d'=' -f2)
  
  cat <<EOF
{
  "moniker": "$MONIKER",
  "identity": "$IDENTITY",
  "about": "$ABOUT",
  "website": "$WEBSITE",
  "contact": "$CONTACT"
}
EOF
}

# Function to check balance
check_balance() {
  VALIDATOR_ADDRESS=$(wardend keys show $KEY_NAME -a --keyring-backend $KEYRING_BACKEND --home $WARDEN_HOME)
  BALANCE_RESPONSE=$(curl -sSL "https://rest.alfama.wardenprotocol.org/cosmos/bank/v1beta1/balances/$VALIDATOR_ADDRESS" -H "accept: application/json")
  BALANCE=$(echo "$BALANCE_RESPONSE" | jq -r '.balances[] | select(.denom == "uward") | .amount // "0"')
  
  cat <<EOF
{
  "balance": "$BALANCE"
}
EOF
}

# Function to initialize the node
initialize_node() {
  wardend init $MONIKER --chain-id $CHAIN_ID --home $WARDEN_HOME
  curl -sSL https://raw.githubusercontent.com/warden-protocol/networks/main/testnet-alfama/genesis.json > $CONFIG_FOLDER/genesis.json

  # Set minimum gas price and peers
  sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "0.0025uward"/' $CONFIG_FOLDER/app.toml
  sed -i 's/persistent_peers = ""/persistent_peers = "2fa750223e22cc19a96391be254680e76387039c@174.138.6.105:26656,12caf2f5e3618cb6c57f45e93ac713b2bc6243b1@164.90.205.67:26656,b9c77f2a0b725fb9b48b50e5ec50d100c58514af@165.232.87.163:26656"/' $CONFIG_FOLDER/config.toml
}

# Function to setup state sync
setup_state_sync() {
  export SNAP_RPC_SERVERS="https://rpc.sentry-1.alfama.wardenprotocol.org:443,https://rpc.sentry-2.alfama.wardenprotocol.org:443,https://rpc.sentry-3.alfama.wardenprotocol.org:443"
  export LATEST_HEIGHT=$(curl -s "$PUBLIC_RPC_ENDPOINT/block" | jq -r .result.block.header.height)
  export BLOCK_HEIGHT=$((LATEST_HEIGHT - 2000))
  export TRUST_HASH=$(curl -s "$PUBLIC_RPC_ENDPOINT/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

  sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ; \
  s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$SNAP_RPC_SERVERS\"| ; \
  s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT| ; \
  s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"|" $CONFIG_FOLDER/config.toml
}

# Function to create or restore a wallet key pair
create_or_restore_wallet() {
  if [ -n "$RESTORE" ]; then
    echo "Restoring wallet from backup..."
    VALIDATOR_MNEMONIC=$(echo $RESTORE | jq -r '.validator_mnemonic')
    echo -e "$VALIDATOR_MNEMONIC\n$VALIDATOR_MNEMONIC" | wardend keys add $KEY_NAME --keyring-backend $KEYRING_BACKEND --recover --home $WARDEN_HOME
  else
    echo "Creating new wallet..."
    wardend keys add $KEY_NAME --keyring-backend $KEYRING_BACKEND --home $WARDEN_HOME
  fi

  VALIDATOR_ADDRESS=$(wardend keys show $KEY_NAME -a --keyring-backend $KEYRING_BACKEND --home $WARDEN_HOME)
  echo "Wallet address: $VALIDATOR_ADDRESS"
}

get_testnet_tokens() {
  echo "Requesting testnet WARD tokens..."
  FAUCET_RESPONSE=$(curl -X POST -H "Content-Type: application/json" -d '{"address": "'"$VALIDATOR_ADDRESS"'"}' https://faucet.alfama.wardenprotocol.org)

  if echo "$FAUCET_RESPONSE" | grep -q "rate limited"; then
    echo "Faucet request rate limited. Please manually fund the wallet address: $VALIDATOR_ADDRESS"
    echo "Waiting for balance to be available..."

    TIMEOUT=900
    WAIT_INTERVAL=6
    START_TIME=$(date +%s)

    while true; do
      echo "Checking balance..."
      BALANCE_RESPONSE=$(curl -sSL "https://rest.alfama.wardenprotocol.org/cosmos/bank/v1beta1/balances/$VALIDATOR_ADDRESS" -H "accept: application/json")

      BALANCES_LENGTH=$(echo "$BALANCE_RESPONSE" | jq '.balances | length')

      if [ "$BALANCES_LENGTH" -gt 0 ]; then
        BALANCE=$(echo "$BALANCE_RESPONSE" | jq -r '.balances[] | select(.denom == "uward") | .amount // "0"')

        if [ "$BALANCE" != "null" ] && [ "$BALANCE" != "0" ]; then
          echo "Balance received: $BALANCE uward"
          break
        fi
      fi

      echo "Current balance: ${BALANCE:-0} uward"

      CURRENT_TIME=$(date +%s)
      ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

      if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
        echo "Timeout reached. Balance not received."
        exit 1
      fi

      sleep $WAIT_INTERVAL
    done
  else
    echo "Waiting for balance to be available..."
    sleep 10

    BALANCE_RESPONSE=$(curl -sSL "https://rest.alfama.wardenprotocol.org/cosmos/bank/v1beta1/balances/$VALIDATOR_ADDRESS" -H "accept: application/json")

    BALANCES_LENGTH=$(echo "$BALANCE_RESPONSE" | jq '.balances | length')

    if [ "$BALANCES_LENGTH" -gt 0 ]; then
      BALANCE=$(echo "$BALANCE_RESPONSE" | jq -r '.balances[] | select(.denom == "uward") | .amount // "0"')

      if [ "$BALANCE" != "null" ] && [ "$BALANCE" != "0" ]; then
        echo "Balance received: $BALANCE uward"
      else
        echo "Balance not received."
        exit 1
      fi
    else
echo "Balance not available."
      exit 1
    fi
  fi
}

create_validator() {
  echo "Creating new validator..."

  VALIDATOR_PUBKEY=$(jq -r '.pubkey' validator.json)
  if [ -z "$VALIDATOR_PUBKEY" ]; then
    echo "Failed to retrieve validator pubkey from validator.json."
    exit 1
  fi

  jq '.pubkey = "'"$VALIDATOR_PUBKEY"'"' validator.json > tmp.json && mv tmp.json validator.json

  echo "Running 'wardend tx staking create-validator'..."
  wardend tx staking create-validator validator.json \
    --from=$KEY_NAME \
    --keyring-backend=$KEYRING_BACKEND \
    --home=$WARDEN_HOME \
    --chain-id=$CHAIN_ID \
    --output json \
    --node $PUBLIC_RPC_ENDPOINT \
    -y

  echo "Sleep 3 blocks (18 seconds) to pickup validator"
  sleep 18
}

# Function to backup critical files
backup_critical_files() {
  echo "Backing up critical files..."
  mkdir -p $WARDEN_HOME/backup
  cp $CONFIG_FOLDER/priv_validator_key.json $WARDEN_HOME/backup/
  cp $CONFIG_FOLDER/node_key.json $WARDEN_HOME/backup/
}

# Function to start the node
start_node() {
  echo "Starting the node..."
  /etc/init.d/nginx stop
  wardend start --home $WARDEN_HOME
  sleep 90000000000000000
}

# Function to start the validator
start_validator() {
  initialize_node
  setup_state_sync
  create_or_restore_wallet
  get_testnet_tokens
  create_validator
  backup_critical_files
  start_node
}

# Function to handle web server requests
handle_request() {
  local path="$1"
  local method="$2"
  local body="$(cat)"

  case "$path" in
    "/")
      display_first_page
      ;;
    "/create_wallet")
      if [ "$method" = "GET" ]; then
        create_or_restore_wallet
        display_create_wallet_page
      fi
      ;;
    "/import_wallet")
      if [ "$method" = "GET" ]; then
        display_import_wallet_page
      elif [ "$method" = "POST" ]; then
        import_wallet
        echo "Wallet imported"
      fi
      ;;
    "/start")
      display_start_page
      ;;
    "/save_variables")
      save_variables "$body"
      echo "Variables saved"
      ;;
    "/get_variables")
      get_variables
      ;;
    "/check_balance")
      check_balance
      ;;
    "/start_validator")
      start_validator
      echo "Validator started"
      ;;
    *)
      echo "Unknown request"
      ;;
  esac
}

# Function to run the web server
run_web_server() {
  while true; do
    echo "Waiting for requests..."
    REQUEST=$(nc -l -p 8080)
    echo "Received request: $REQUEST"

    ROUTE=$(echo "$REQUEST" | awk '{print $2}')
    METHOD=$(echo "$REQUEST" | awk '{print $1}')
    BODY=$(echo "$REQUEST" | sed '1,/^$/d')

    RESPONSE=$(handle_request "$ROUTE" "$METHOD" "$BODY")

    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: ${#RESPONSE}\r\n\r\n$RESPONSE" | nc -q 0 localhost 8080
  done
}

# Main script execution
configure_nginx
run_web_server
