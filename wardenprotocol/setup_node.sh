#!/bin/bash

# Setting up environment variables
MONIKER=${MONIKER:-"spheron.network"}
CHAIN_ID="alfama"
WARDEN_HOME="$HOME/.warden"
CONFIG_FOLDER="$WARDEN_HOME/config"
KEYRING_BACKEND="test"
KEY_NAME="validator"
RSYNC_BACKUP=${RSYNC_BACKUP:-""}
RSYNC_LOCATION=${RSYNC_LOCATION:-""}
RSYNC_RESTORE_BACKUP=${RSYNC_RESTORE_BACKUP:-""}
RSYNC_RESTORE_LOCATION=${RSYNC_RESTORE_LOCATION:-""}
RESTORE=${RESTORE:-""}
PUBLIC_RPC_ENDPOINT="https://rpc.alfama.wardenprotocol.org:443"


#YOUR_MONIKER_GOES_HERE : spheron.network
#identity: spheron.network (should be the gif location)
#About Us 
#Website:
#Contact: 

# Function to initialize the node
initialize_node() {
  echo "Initializing node..."
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

echo $LATEST_HEIGHT $BLOCK_HEIGHT $TRUST_HASH

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

    TIMEOUT=900  # 15 minutes in seconds
    WAIT_INTERVAL=6  # 6 seconds
    START_TIME=$(date +%s)

    while true; do
      echo "Checking balance..."
      BALANCE_RESPONSE=$(curl -sSL "https://rest.alfama.wardenprotocol.org/cosmos/bank/v1beta1/balances/$VALIDATOR_ADDRESS" -H "accept: application/json")
      echo "Balance response: $BALANCE_RESPONSE"

      BALANCES_LENGTH=$(echo "$BALANCE_RESPONSE" | jq '.balances | length')

      if [ "$BALANCES_LENGTH" -gt 0 ]; then
        BALANCE=$(echo "$BALANCE_RESPONSE" | jq -r '.balances[] | select(.denom == "uward") | .amount // "0"')
        echo "Balance: $BALANCE"

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
    echo "Balance response: $BALANCE_RESPONSE"

    BALANCES_LENGTH=$(echo "$BALANCE_RESPONSE" | jq '.balances | length')

    if [ "$BALANCES_LENGTH" -gt 0 ]; then
      BALANCE=$(echo "$BALANCE_RESPONSE" | jq -r '.balances[] | select(.denom == "uward") | .amount // "0"')
      echo "Balance: $BALANCE"

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

  echo "Running 'wardend tendermint show-validator --home $WARDEN_HOME'..."
  VALIDATOR_PUBKEY=$(wardend tendermint show-validator --home $WARDEN_HOME 2>/dev/null)
  echo "Output of 'wardend tendermint show-validator':"
  echo "$VALIDATOR_PUBKEY"

  if [ -z "$VALIDATOR_PUBKEY" ]; then
    echo "Failed to retrieve validator pubkey."
    exit 1
  fi

  echo "Creating validator.json file..."
  cat > validator.json <<EOF
{
  "pubkey": $VALIDATOR_PUBKEY,
  "amount": "1000000uward",
  "moniker": "$MONIKER",
  "identity": "spheron.network",
  "website": "https://spheron.network",
  "security": "",
  "details": "Deployed from https://spheron.network",
  "commission-rate": "0.1",
  "commission-max-rate": "0.2",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}
EOF

  echo "Validator.json content:"
  cat validator.json

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
  wardend start --home $WARDEN_HOME
sleep 90000000000000000
}

# Main script execution
initialize_node
setup_state_sync
create_or_restore_wallet
get_testnet_tokens
create_validator
backup_critical_files
#confirm_validator_active
start_node
