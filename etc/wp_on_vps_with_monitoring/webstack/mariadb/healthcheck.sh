#!/bin/bash
set -e

# Load .env file if it exists (commented out for now, enable for future mysql checks)
# ENV_FILE="/env/.env"
# if [ -f "$ENV_FILE" ]; then
#   set -a
#   source "$ENV_FILE"
#   set +a
# fi

# Check if MariaDB process is running
if pgrep mariadbd >/dev/null; then
  exit 0
fi

# Fallback: Check for mariadbd in ps aux
if ps aux | grep '[m]ariadbd' >/dev/null; then
  exit 0
fi

# Future: Check socket file
# test -S /run/mysqld/mysqld.sock || { echo "Socket not found"; exit 1; }

# Future: Add mysql client check if available
# mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" --silent || { echo "Database query failed"; exit 1; }

echo "MariaDB process not found"
exit 1
