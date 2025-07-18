#!/usr/bin/env bash
set -euo pipefail

# --- Main script execution ---
main() {
    # CRUCIAL CHECK: Ensure the script is run as root (EUID 0 indicates root user)
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root." >&2;
        echo "Please execute it either as: 'sudo ./restart.sh' (if sudo is installed)" >&2;
        echo "OR: switch to the root user first (e.g., 'sudo su -' or 'su -') and then run './restart.sh'." >&2;
        exit 1;
    fi

    # Dynamically determine the application's root directory based on this script's location.
    # Consistent with deploy.sh and reset.sh, this assumes the script is directly in the app root.
    APP_ROOT_DIR=$(dirname "$0")

    # Define the list of Docker Compose stack directories (consistent with deploy.sh and reset.sh)
    # The order generally matters for dependencies (e.g., Traefik often needs to start before web services).
    declare -a STACKS=("traefik" "webstack" "monitoring")

    echo "=== Starting Docker Compose Services Restart ==="

    # Loop through each defined stack to restart it
    for stack_dir in "${STACKS[@]}"; do
        echo "--- Restarting $stack_dir stack ---"

        # Construct the full absolute path to the current stack's directory
        STACK_PATH="${APP_ROOT_DIR}/$stack_dir"

        # Check if the stack's directory actually exists
        if [ ! -d "$STACK_PATH" ]; then
            echo "Warning: Stack directory '$STACK_PATH' not found. Skipping restart of $stack_dir." >&2 # Output error to stderr
            continue # Skip to the next stack in the loop
        fi

        # Use a subshell (commands within parentheses) to perform the 'cd' operation.
        # This is a robust pattern: the 'cd' command only affects the environment of the
        # current subshell, ensuring that the main script's working directory (and future
        # iterations of the loop) remain unaffected.
        (
            echo "Changing directory to $STACK_PATH"
            # Change into the stack directory. If 'cd' fails, print an error and exit the subshell immediately.
            cd "$STACK_PATH" || { echo "Fatal Error: Could not change to directory '$STACK_PATH'. Exiting subshell." >&2; exit 1; }

            echo "Running 'docker compose down' for $stack_dir..."
            # Execute the docker compose down command. If it fails (e.g., stack not running),
            # print a warning but continue to 'up' as the goal is to get it running.
            docker compose down || echo "Warning: Failed to stop $stack_dir stack cleanly. Attempting to start anyway." >&2

            echo "Running 'docker compose up -d' for $stack_dir..."
            # Execute the docker compose up command in detached mode. If it fails, print an error and exit the subshell.
            docker compose up -d || { echo "Error: Failed to start $stack_dir stack. Exiting subshell." >&2; exit 1; }
        ) || { echo "Error: Subshell for $stack_dir restart failed. Please check logs for '$stack_dir'." >&2; exit 1; } # Check the exit status of the entire subshell.
        
        echo "--- $stack_dir stack restarted successfully ---"
        echo "" # Add an empty line for better readability between stack operations
    done

    echo "=== All Docker Compose Services Restarted ==="
    echo "=== Restart complete ==="
}

# Call the main function
main "$@"