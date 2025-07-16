#!/usr/bin/env bash
set -euo pipefail

echo "=== Deploying traefik ==="
cd /opt/wpmon/traefik
docker compose up -d

echo "=== Deploying webstack ==="
cd /opt/wpmon/webstack
docker compose up -d

echo "=== Deploying monitoring ==="
cd /opt/wpmon/monitoring
docker compose up -d

echo "=== Deployment complete ==="
