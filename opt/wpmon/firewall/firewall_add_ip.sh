#!/bin/bash

# Configuration
IP="10.0.0.60" # IP to let through firewall! (Replace with your actual IP)
SSH_PORT="22"
WEB_PORTS="80,443"
TABLE_NAME="wp_on_vps_with_monitoring"
SSH_CHAIN="ssh_input"
WEB_CHAIN="web_input"

# Ensure nftables is installed
if ! command -v nft &> /dev/null; then
    echo "Error: nftables is not installed. Please install it first (e.g., sudo apt install nftables)."
    exit 1
fi

# IMPORTANT: Define the nftables rules in a here-document
# Variables like $TABLE_NAME will be expanded by bash before nft sees the rules.
# Only comments and log prefixes use double quotes.
nft -f - << EOF
# Flush our custom table
flush table inet $TABLE_NAME
delete table inet $TABLE_NAME

# Flush the default 'filter' tables in IPv4 and IPv6 families
# This fixes "No such file or directory" error for 'filter' table
flush table ip filter
delete table ip filter
flush table ip6 filter
delete table ip6 filter

# Create nftables table and chains
add table inet $TABLE_NAME
add chain inet $TABLE_NAME input { type filter hook input priority -10; policy drop; }
add chain inet $TABLE_NAME $SSH_CHAIN
add chain inet $TABLE_NAME $WEB_CHAIN

# Essential rules
add rule inet $TABLE_NAME input iif lo accept comment "Allow loopback traffic"
add rule inet $TABLE_NAME input ct state established,related accept comment "Allow established/related connections"
add rule inet $TABLE_NAME input tcp dport $SSH_PORT jump $SSH_CHAIN comment "Jump to SSH chain"
add rule inet $TABLE_NAME input tcp dport { $WEB_PORTS } jump $WEB_CHAIN comment "Jump to web chain"

# Log and drop unmatched input traffic with rate-limiting
add rule inet $TABLE_NAME input log prefix "INPUT_DROP: " limit rate 1/second drop comment "Log and drop unmatched input"

# Add IPv4 or IPv6 rules depending on IP format
EOF

# Use a separate here-document for IP-dependent rules
if [[ "$IP" =~ : ]]; then
    # IPv6
    nft -f - << EOF_IP_RULES
add rule inet $TABLE_NAME $SSH_CHAIN ip6 saddr $IP tcp dport $SSH_PORT log prefix "SSH_ACCEPT: " limit rate 1/second accept comment "Allow SSH from $IP"
add rule inet $TABLE_NAME $WEB_CHAIN ip6 saddr $IP tcp dport { $WEB_PORTS } log prefix "WEB_ACCEPT: " limit rate 1/second accept comment "Allow web from $IP"
EOF_IP_RULES
else
    # IPv4
    nft -f - << EOF_IP_RULES
add rule inet $TABLE_NAME $SSH_CHAIN ip saddr $IP tcp dport $SSH_PORT log prefix "SSH_ACCEPT: " limit rate 1/second accept comment "Allow SSH from $IP"
add rule inet $TABLE_NAME $WEB_CHAIN ip saddr $IP tcp dport { $WEB_PORTS } log prefix "WEB_ACCEPT: " limit rate 1/second accept comment "Allow web from $IP"
EOF_IP_RULES
fi

echo "Added rules for $IP"

nft -f - << EOF_DROPS
# Drop unmatched traffic in each chain (no logging)
add rule inet $TABLE_NAME $SSH_CHAIN drop comment "Drop unmatched SSH"
add rule inet $TABLE_NAME $WEB_CHAIN drop comment "Drop unmatched web"
EOF_DROPS

# Save rules for persistence
# Uncomment the following line if you want the rules to persist after reboot
# sudo nft list ruleset > /etc/nftables.conf

# Restart Docker to ensure its rules are applied
systemctl restart docker
