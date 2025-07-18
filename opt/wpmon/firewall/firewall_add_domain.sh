#!/bin/bash

# Configuration
DOMAIN="example.com" # Domain to resolve!
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

# Function to update nftables with domain IPs
update_domain_ips() {
    # Clear existing rules in SSH and web chains
    nft flush chain inet $TABLE_NAME $SSH_CHAIN 2>/dev/null || true
    nft flush chain inet $TABLE_NAME $WEB_CHAIN 2>/dev/null || true

    # Resolve domain IPs (IPv4)
    IPSv4=$(dig +short A $DOMAIN | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

    # Resolve domain IPs (IPv6)
    IPSv6=$(dig +short AAAA $DOMAIN | grep -E '^[0-9a-fA-F:]+$')

    if [ -z "$IPSv4" ] && [ -z "$IPSv6" ]; then
        echo "Error: Could not resolve any IPs for $DOMAIN"
        exit 1
    fi

    # Add rules for each resolved IPv4
    for IP in $IPSv4; do
        nft add rule inet $TABLE_NAME $SSH_CHAIN ip saddr $IP tcp dport $SSH_PORT log prefix "SSH_ACCEPT: " limit rate 1/second accept comment "Allow SSH from $IP"
        nft add rule inet $TABLE_NAME $WEB_CHAIN ip saddr $IP tcp dport { $WEB_PORTS } log prefix "WEB_ACCEPT: " limit rate 1/second accept comment "Allow web from $IP"
        echo "Added IPv4 rules for $IP"
    done

    # Add rules for each resolved IPv6
    for IP in $IPSv6; do
        nft add rule inet $TABLE_NAME $SSH_CHAIN ip6 saddr $IP tcp dport $SSH_PORT log prefix "SSH_ACCEPT: " limit rate 1/second accept comment "Allow SSH from $IP"
        nft add rule inet $TABLE_NAME $WEB_CHAIN ip6 saddr $IP tcp dport { $WEB_PORTS } log prefix "WEB_ACCEPT: " limit rate 1/second accept comment "Allow web from $IP"
        echo "Added IPv6 rules for $IP"
    done

    # Drop unmatched traffic in each chain (no logging)
    nft add rule inet $TABLE_NAME $SSH_CHAIN drop comment "Drop unmatched SSH"
    nft add rule inet $TABLE_NAME $WEB_CHAIN drop comment "Drop unmatched web"
}

# Update nftables with domain IPs
update_domain_ips

# Save rules for persistence
nft list ruleset > /etc/nftables.conf

# Restart Docker to ensure its rules are applied
systemctl restart docker

# Optional: Schedule this script to run periodically via cron
# Example cron entry (run every 6 hours):
# 0 */6 * * * /opt/wp_on_vps_with_monitoring/firewall/firewall_add_domain.sh