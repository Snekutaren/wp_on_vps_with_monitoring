#!/bin/bash

# Script to flush Docker-related nftables rules while preserving custom rules
# Ensure the script runs as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Define the nftables table used by your custom rules
CUSTOM_TABLE="insolita"

# Check if nftables is installed
if ! command -v nft &> /dev/null; then
    echo "Error: nftables not installed" >&2
    exit 1
fi

# List current nftables rules for reference
echo "Current nftables rules before flushing Docker rules:"
nft list ruleset

# Identify Docker-related chains in the filter table
DOCKER_CHAINS=$(nft list tables | grep "table inet filter" -A1 | \
    nft list table inet filter | grep chain | \
    grep -E "DOCKER|DOCKER-USER|DOCKER-INGRESS" | awk '{print $2}')

# Flush Docker-related chains
for CHAIN in $DOCKER_CHAINS; do
    echo "Flushing chain: $CHAIN"
    nft flush chain inet filter "$CHAIN"
done

# Check if DOCKER-USER chain exists and ensure it's empty (Docker may recreate it)
if nft list chain inet filter DOCKER-USER &> /dev/null; then
    echo "Ensuring DOCKER-USER chain is empty"
    nft flush chain inet filter DOCKER-USER
fi

# Optionally, restart Docker to recreate necessary rules
# Uncomment the following lines if you want Docker to regenerate its rules
# echo "Restarting Docker to recreate default rules"
# systemctl restart docker
# if [ $? -eq 0 ]; then
#     echo "Docker restarted successfully"
# else
#     echo "Error: Failed to restart Docker" >&2
#     exit 1
# fi

# Verify custom table (insolita) is intact
if nft list table inet "$CUSTOM_TABLE" &> /dev/null; then
    echo "Custom table $CUSTOM_TABLE remains intact"
else
    echo "Error: Custom table $CUSTOM_TABLE not found. Check your firewall-nft.sh script." >&2
    exit 1
fi

# List updated nftables rules
echo "Updated nftables rules after flushing Docker rules:"
nft list ruleset

# Verify logging to /var/log/nftables.log
echo "Checking recent entries in /var/log/nftables.log"
tail -n 10 /var/log/nftables.log

echo "Docker rules flushed successfully"
exit 0
