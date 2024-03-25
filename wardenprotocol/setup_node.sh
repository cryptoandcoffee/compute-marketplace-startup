#!/bin/bash

# Setting up environment variables
MONIKER=${MONIKER:-"YOUR_MONIKER_GOES_HERE"}
RSYNC_BACKUP=${RSYNC_BACKUP:-""}
RSYNC_LOCATION=${RSYNC_LOCATION:-""}
RSYNC_RESTORE_BACKUP=${RSYNC_RESTORE_BACKUP:-""}
RSYNC_RESTORE_LOCATION=${RSYNC_RESTORE_LOCATION:-""}
RESTORE=${RESTORE:-""}

# Retrieve RESTORE JSON from remote location if RSYNC_RESTORE_BACKUP and RSYNC_RESTORE_LOCATION are set
if [ -n "$RSYNC_RESTORE_BACKUP" ] && [ -n "$RSYNC_RESTORE_LOCATION" ]; then
  echo "Retrieving RESTORE JSON from remote location..."
  rsync -avz --quiet $RSYNC_RESTORE_BACKUP:$RSYNC_RESTORE_LOCATION/validator_backup.json .
  RESTORE=$(cat validator_backup.json)
  echo "RESTORE JSON retrieved from remote location."
fi

# Initialize node
wardend init $MONIKER

# Get genesis file
curl https://raw.githubusercontent.com/warden-protocol/networks/main/testnet-alfama/genesis.json > ~/.warden/config/genesis.json

# Set minimum gas price and peers
sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "0.0025uward"/' ~/.warden/config/app.toml
sed -i 's/persistent_peers = ""/persistent_peers = "6a8de92a3bb422c10f764fe8b0ab32e1e334d0bd@sentry-1.alfama.wardenprotocol.org:26656,7560460b016ee0867cae5642adace5d011c6c0ae@sentry-2.alfama.wardenprotocol.org:26656,24ad598e2f3fc82630554d98418d26cc3edf28b9@sentry-3.alfama.wardenprotocol.org:26656"/' ~/.warden/config/config.toml

# Setup state sync
SNAP_RPC_SERVERS="https://rpc.sentry-1.alfama.wardenprotocol.org:443,https://rpc.sentry-2.alfama.wardenprotocol.org:443,https://rpc.sentry-3.alfama.wardenprotocol.org:443"
LATEST_HEIGHT=$(curl -s "https://rpc.alfama.wardenprotocol.org/block" | jq -r .result.block.header.height)
BLOCK_HEIGHT=$((LATEST_HEIGHT - 2000))
TRUST_HASH=$(curl -s "https://rpc.alfama.wardenprotocol.org/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ; \
s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$SNAP_RPC_SERVERS\"| ; \
s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT| ; \
s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"|" ~/.warden/config/config.toml

if [ -n "$RESTORE" ]; then
  echo "Restoring from backup..."
  VALIDATOR_ADDRESS=$(echo $RESTORE | jq -r '.validator_address')
  VALIDATOR_PASSWORD=$(echo $RESTORE | jq -r '.validator_password')
  VALIDATOR_KEY_INFO=$(echo $RESTORE | jq -r '.validator_key_info')
  
  # Import validator key
  echo $VALIDATOR_KEY_INFO | jq -r '.mnemonic' | wardend keys add validator --keyring-backend test --recover
else
  # Create new wallet
  echo "Creating new wallet..."
  VALIDATOR_PASSWORD=$(openssl rand -base64 32)
  echo $VALIDATOR_PASSWORD | wardend keys add validator --keyring-backend test --output json --recover
  VALIDATOR_ADDRESS=$(wardend keys show validator -a --keyring-backend test)
  echo "New wallet address: $VALIDATOR_ADDRESS"
  echo "Please fund this wallet address to continue."

  # Wait for the wallet to be funded (check every 6 seconds for up to 5 minutes)
  BALANCE=0
  TIMEOUT=300
  START_TIME=$(date +%s)
  while [ $BALANCE -eq 0 ]; do
    BALANCE=$(wardend q bank balances $VALIDATOR_ADDRESS -o json | jq -r '.balances[0].amount')
    echo "Current balance: $BALANCE"
    
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
      echo "Timeout reached. Wallet funding not received within 5 minutes."
      exit 1
    fi
    
    sleep 6
  done

  echo "Wallet funded. Continuing..."
fi

# Create new validator
echo "Creating new validator..."
echo $VALIDATOR_PASSWORD | wardend tx staking create-validator \
  --amount=1000000uward \
  --pubkey=$(wardend tendermint show-validator) \
  --moniker=$MONIKER \
  --chain-id=alfama \
  --commission-rate="0.10" \
  --commission-max-rate="0.20" \
  --commission-max-change-rate="0.01" \
  --min-self-delegation="1000000" \
  --gas="auto" \
  --gas-prices="0.0025uward" \
  --from=validator \
  --keyring-backend=test \
  --yes

# Extract validator key information
VALIDATOR_KEY_INFO=$(echo $VALIDATOR_PASSWORD | wardend keys show validator --keyring-backend test --output json)

# Generate backup JSON
BACKUP_JSON=$(jq -n --arg va "$VALIDATOR_ADDRESS" --arg vp "$VALIDATOR_PASSWORD" --arg vk "$VALIDATOR_KEY_INFO" \
  '{validator_address: $va, validator_password: $vp, validator_key_info: $vk}')

# Save backup JSON to a file
echo $BACKUP_JSON > validator_backup.json
echo "Validator backup saved to validator_backup.json"

# Send validator_backup.json to rsync backup location if RSYNC_BACKUP and RSYNC_LOCATION are set
if [ -n "$RSYNC_BACKUP" ] && [ -n "$RSYNC_LOCATION" ]; then
  echo "Sending validator_backup.json to rsync backup location..."
  rsync -avz --quiet validator_backup.json $RSYNC_BACKUP:$RSYNC_LOCATION
  echo "Validator backup sent to rsync backup location."
fi

# Start the node
echo "Starting the node..."
wardend start
