#!/usr/bin/env bash
set -euo pipefail

echo "=== Restarting traefik ==="
cd /opt/wpmon/traefik
docker compose down
docker compose up -d

echo "=== Restarting webstack ==="
cd /opt/wpmon/webstack
docker compose down
docker compose up -d

echo "=== Restarting monitoring ==="
cd /opt/wpmon/monitoring
docker compose down
docker compose up -d

echo "=== Restart complete ==="
