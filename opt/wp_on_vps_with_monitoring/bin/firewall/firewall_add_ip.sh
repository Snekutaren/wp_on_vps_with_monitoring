#!/bin/bash

# Configuration
IP="123.456.789.1"  # IPv4 or IPv6 to allow through firewall
SSH_PORT="22"
WEB_PORTS="80,443"
TABLE_NAME="wp_on_vps_with_monitoring"
SSH_CHAIN="ssh_input"
WEB_CHAIN="web_input"

# Flush our table and default filter table (preserve Docker’s table inet docker)
nft flush table inet $TABLE_NAME 2>/dev/null || true
nft delete table inet $TABLE_NAME 2>/dev/null || true
nft flush table inet filter 2>/dev/null || true
nft delete table inet filter 2>/dev/null || true

# Create nftables table and chains
nft add table inet $TABLE_NAME
nft add chain inet $TABLE_NAME input { type filter hook input priority -10 \; policy drop \; }
nft add chain inet $TABLE_NAME $SSH_CHAIN
nft add chain inet $TABLE_NAME $WEB_CHAIN

# Essential rules
nft add rule inet $TABLE_NAME input iif lo accept comment "Allow loopback traffic"
nft add rule inet $TABLE_NAME input ct state established,related accept comment "Allow established/related connections"
nft add rule inet $TABLE_NAME input tcp dport $SSH_PORT jump $SSH_CHAIN comment "Jump to SSH chain"
nft add rule inet $TABLE_NAME input tcp dport { $WEB_PORTS } jump $WEB_CHAIN comment "Jump to web chain"

# Log and drop unmatched input traffic with rate-limiting
nft add rule inet $TABLE_NAME input log prefix "INPUT_DROP: " limit rate 1/second drop comment "Log and drop unmatched input"

# Add IPv4 or IPv6 rules depending on IP format
if [[ "$IP" =~ : ]]; then
    # IPv6
    nft add rule inet $TABLE_NAME $SSH_CHAIN ip6 saddr $IP tcp dport $SSH_PORT log prefix "SSH_ACCEPT: " limit rate 1/second accept comment "Allow SSH from $IP"
    nft add rule inet $TABLE_NAME $WEB_CHAIN ip6 saddr $IP tcp dport { $WEB_PORTS } log prefix "WEB_ACCEPT: " limit rate 1/second accept comment "Allow web from $IP"
else
    # IPv4
    nft add rule inet $TABLE_NAME $SSH_CHAIN ip saddr $IP tcp dport $SSH_PORT log prefix "SSH_ACCEPT: " limit rate 1/second accept comment "Allow SSH from $IP"
    nft add rule inet $TABLE_NAME $WEB_CHAIN ip saddr $IP tcp dport { $WEB_PORTS } log prefix "WEB_ACCEPT: " limit rate 1/second accept comment "Allow web from $IP"
fi

echo "Added rules for $IP"

# Drop unmatched traffic in each chain (no logging)
nft add rule inet $TABLE_NAME $SSH_CHAIN drop comment "Drop unmatched SSH"
nft add rule inet $TABLE_NAME $WEB_CHAIN drop comment "Drop unmatched web"

# Save rules for persistence
nft list ruleset > /etc/nftables.conf

# Restart Docker to ensure its rules are applied
systemctl restart docker
