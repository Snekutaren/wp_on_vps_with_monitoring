#!/usr/bin/env bash
set -euo pipefail

echo "=== Shutting down monitoring ==="
cd /opt/wp_on_vps_with_monitoring/monitoring
docker compose down

echo "=== Shutting down webstack ==="
cd /opt/wp_on_vps_with_monitoring/webstack
docker compose down

echo "=== Shutting down reverse-proxy ==="
cd /opt/wp_on_vps_with_monitoring/traefik
docker compose down

echo "=== Shutdown complete ==="
