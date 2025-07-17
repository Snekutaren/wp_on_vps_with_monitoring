#!/usr/bin/env bash
set -euo pipefail

# --- Main script execution ---
main() {
    # CRUCIAL CHECK: Ensure the script is run as root (EUID 0 indicates root user)
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root." >&2;
        echo "Please execute it either as: 'sudo ./shutdown.sh' (if sudo is installed)" >&2;
        echo "OR: switch to the root user first (e.g., 'sudo su -' or 'su -') and then run './shutdown.sh'." >&2;
        exit 1;
    fi

    # Dynamically determine the application's root directory based on this script's location.
    # Consistent with other management scripts, this assumes the script is directly in the app root.
    APP_ROOT_DIR=$(dirname "$0")

    # Define the list of Docker Compose stack directories.
    # For shutdown, it's generally best to stop dependent services before the services they rely on.
    # The order provided (monitoring, webstack, traefik) correctly shuts down dependent services first.
    declare -a STACKS=("monitoring" "webstack" "traefik")

    echo "=== Starting Docker Compose Services Shutdown ==="

    # Loop through each defined stack to bring it down
    for stack_dir in "${STACKS[@]}"; do
        echo "--- Shutting down $stack_dir stack ---"

        # Construct the full absolute path to the current stack's directory
        STACK_PATH="${APP_ROOT_DIR}/$stack_dir"

        # Check if the stack's directory actually exists
        if [ ! -d "$STACK_PATH" ]; then
            echo "Warning: Stack directory '$STACK_PATH' not found. Skipping shutdown of $stack_dir." >&2 # Output error to stderr
            continue # Skip to the next stack in the loop
        fi

        # Use a subshell (commands within parentheses) to perform the 'cd' operation.
        # This prevents the 'cd' from affecting the main script's working directory.
        (
            echo "Changing directory to $STACK_PATH"
            # Change into the stack directory. If 'cd' fails, print an error and exit the subshell immediately.
            cd "$STACK_PATH" || { echo "Fatal Error: Could not change to directory '$STACK_PATH'. Exiting subshell." >&2; exit 1; }

            echo "Running 'docker compose down' for $stack_dir..."
            # Execute the docker compose down command. If it fails (e.g., stack not running),
            # print a warning but continue, as the goal is to shut down as many as possible.
            docker compose down || echo "Warning: Failed to shut down $stack_dir stack cleanly. Continuing with other shutdowns." >&2
        ) || { echo "Error: Subshell for $stack_dir shutdown process failed. Please check logs for '$stack_dir'." >&2; } # Check the exit status of the entire subshell.
        
        echo "--- $stack_dir stack shutdown attempted ---"
        echo "" # Add an empty line for better readability between stack operations
    done

    echo "=== All Docker Compose Services Shutdown Attempted ==="
    echo "=== Shutdown complete ==="
}

# Call the main function
main "$@"