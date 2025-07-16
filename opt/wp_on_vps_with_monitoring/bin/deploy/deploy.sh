#!/usr/bin/env bash
set -euo pipefail

echo "=== Deploying traefik ==="
cd /opt/wp_on_vps_with_monitoring/traefik
docker compose up -d

echo "=== Deploying webstack ==="
cd /opt/wp_on_vps_with_monitoring/webstack
docker compose up -d

echo "=== Deploying monitoring ==="
cd /opt/wp_on_vps_with_monitoring/monitoring
docker compose up -d

echo "=== Deployment complete ==="
