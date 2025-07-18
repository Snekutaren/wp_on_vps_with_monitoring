#!/usr/bin/env bash

set -euo pipefail

# Dynamically determine the application's root directory based on this script's location.
# Since run_setup.sh ensures this script is executed from APP_ROOT_DIR,
# $(dirname "$0") will resolve to the current directory ('.').
APP_ROOT_DIR=$(dirname "$0")
APP_NAME=$(basename "$(realpath "$(dirname "$0")/..")")

# Define the list of Docker Compose stack directories
declare -a STACKS=("traefik" "webstack" "monitoring")

echo "=== Starting Docker Compose Deployments ==="

# Loop through each defined stack directory to deploy it
for stack_dir in "${STACKS[@]}"; do
    echo "--- Deploying $stack_dir stack ---"

   export COMPOSE_PROJECT_NAME="{$APP_NAME}${stack_dir}"

    # Construct the full absolute path to the current stack's directory
    STACK_PATH="${APP_ROOT_DIR}/$stack_dir"

    # Check if the stack's directory actually exists on the filesystem
    if [ ! -d "$STACK_PATH" ]; then
        echo "Error: Stack directory '$STACK_PATH' not found. Skipping deployment of $stack_dir." >&2 # Output error to stderr
        continue # Skip to the next stack in the loop, do not stop the entire script
    fi

    # Use a subshell (commands within parentheses) to perform the 'cd' operation.
    # This is a robust pattern: the 'cd' command only affects the environment of the
    # current subshell, ensuring that the main script's working directory (and future
    # iterations of the loop) remain unaffected.
    (
        echo "Changing directory to $STACK_PATH"
        # Change into the stack directory. If 'cd' fails (e.g., directory permissions),
        # print an error and exit the subshell immediately.
        cd "$STACK_PATH" || { echo "Fatal Error: Could not change to directory '$STACK_PATH'. Exiting subshell." >&2; exit 1; }

        echo "Running 'docker compose up -d' for $stack_dir..."
        # Execute the docker compose command in detached mode.
        docker compose up -d
    )

    # Check the exit status of the entire subshell.
    if [ $? -eq 0 ]; then
        echo "--- $stack_dir stack deployed successfully ---"
    else
        echo "Error: Failed to deploy $stack_dir stack. Please review Docker Compose logs for details." >&2 # Output error to stderr
        exit 1
    fi
    echo "" # Add an empty line for better readability between stack deployments
done

echo "=== All Docker Compose Deployments Attempted ==="
echo "=== Deployment complete ==="