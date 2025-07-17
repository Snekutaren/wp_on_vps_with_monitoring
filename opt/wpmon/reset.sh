#!/usr/bin/env bash
set -euo pipefail

echo "=== WARNING: This will DELETE ALL DATA, VOLUMES, AND NETWORKS ==="
read -p "Are you absolutely sure you want to reset everything? (yes/[no]): " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "Reset aborted."
  exit 0
fi

echo "=== Resetting monitoring (including volumes) ==="
cd /opt/wpmon/monitoring
docker compose down -v

echo "=== Resetting webstack (including volumes) ==="
cd /opt/wpmon/webstack
docker compose down -v

echo "=== Resetting traefik (including volumes) ==="
cd /opt/wpmon/traefik
docker compose down -v

echo "=== Pruning unused networks ==="
docker network prune -f

echo "=== Reset complete ==="
