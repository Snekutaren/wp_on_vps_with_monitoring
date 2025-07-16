#!/usr/bin/env bash
set -euo pipefail

echo "=== Restarting traefik ==="
cd /opt/wp_on_vps_with_monitoring/traefik
docker compose down
docker compose up -d

echo "=== Restarting webstack ==="
cd /opt/wp_on_vps_with_monitoring/webstack
docker compose down
docker compose up -d

echo "=== Restarting monitoring ==="
cd /opt/wp_on_vps_with_monitoring/monitoring
docker compose down
docker compose up -d

echo "=== Restart complete ==="
