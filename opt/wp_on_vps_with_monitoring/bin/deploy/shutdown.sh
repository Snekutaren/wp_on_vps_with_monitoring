#!/usr/bin/env bash
set -euo pipefail

echo "=== Shutting down monitoring ==="
cd /opt/wpmon/monitoring
docker compose down

echo "=== Shutting down webstack ==="
cd /opt/wpmon/webstack
docker compose down

echo "=== Shutting down reverse-proxy ==="
cd /opt/wpmon/traefik
docker compose down

echo "=== Shutdown complete ==="
