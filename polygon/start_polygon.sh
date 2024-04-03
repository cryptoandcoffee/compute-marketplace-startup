#!/bin/bash

# Start Heimdall
heimdalld start &

# Wait for Heimdall to sync
echo "Waiting for Heimdall to sync..."
while [ "$(curl -s localhost:26657/status | jq -r '.result.sync_info.catching_up')" == "true" ]; do
  sleep 10
done
echo "Heimdall is synced"

# Start Bor
bor --datadir /root/.bor server &

# Wait for Bor to sync
echo "Waiting for Bor to sync..."
while [ "$(curl -s localhost:8545 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq -r '.result')" != "false" ]; do
  sleep 10
done
echo "Bor is synced"

# Keep the container running
tail -f /dev/null