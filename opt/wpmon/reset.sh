#!/usr/bin/env bash
set -euo pipefail

# --- Main script execution ---
main() {
    # CRUCIAL CHECK: Ensure the script is run as root (EUID 0 indicates root user)
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root." >&2;
        echo "Please execute it either as: 'sudo ./reset.sh' (if sudo is installed)" >&2;
        echo "OR: switch to the root user first (e.g., 'sudo su -' or 'su -') and then run './reset.sh'." >&2;
        exit 1;
    fi

    echo "=== WARNING: This will DELETE ALL DATA, VOLUMES, AND NETWORKS ==="
    read -p "Are you absolutely sure you want to reset everything? (yes/[no]): " confirm

    if [[ "$confirm" != "yes" ]]; then
        echo "Reset aborted."
        exit 0
    fi

    # Dynamically determine the application's root directory based on this script's location.
    # Consistent with deploy.sh, this assumes the script is directly in the app root.
    APP_ROOT_DIR=$(dirname "$0")

    # Define the list of Docker Compose stack directories (consistent with deploy.sh)
    declare -a STACKS=("traefik" "webstack" "monitoring")

    echo "=== Starting Full Application Reset ==="

    # Loop through each defined stack to bring it down and remove volumes
    for stack_dir in "${STACKS[@]}"; do
        echo "--- Resetting $stack_dir stack (including volumes) ---"

        # Construct the full absolute path to the current stack's directory
        STACK_PATH="${APP_ROOT_DIR}/$stack_dir"

        # Check if the stack's directory actually exists
        if [ ! -d "$STACK_PATH" ]; then
            echo "Warning: Stack directory '$STACK_PATH' not found. Skipping reset of $stack_dir." >&2 # Output error to stderr
            continue # Skip to the next stack in the loop
        fi

        # Use a subshell to perform the 'cd' operation safely.
        # This prevents the 'cd' from affecting the main script's working directory.
        (
            echo "Changing directory to $STACK_PATH"
            # Change into the stack directory. If 'cd' fails, exit the subshell immediately.
            cd "$STACK_PATH" || { echo "Fatal Error: Could not change to directory '$STACK_PATH'. Exiting subshell." >&2; exit 1; }

            echo "Running 'docker compose down -v' for $stack_dir..."
            # Execute the docker compose command. If it fails, exit the subshell.
            docker compose down -v || { echo "Error: Failed to bring down and remove volumes for $stack_dir stack." >&2; exit 1; }
        ) || { echo "Error: Subshell for $stack_dir reset failed. Please check logs for '$stack_dir'." >&2; exit 1; } # Check the exit status of the entire subshell.
        
        echo "--- $stack_dir stack reset successfully ---"
        echo "" # Add an empty line for better readability between stack operations
    done

    echo "=== Pruning unused Docker networks ==="
    # Prune unused networks. If it fails, print an error and exit.
    docker network prune -f || { echo "Error: Failed to prune unused Docker networks." >&2; exit 1; }
    echo "Docker networks pruned successfully."

    echo -e "\n=== Full Application Reset Complete ==="
    echo "All Docker containers, images, volumes, and networks associated with the defined stacks have been removed."
    echo "The application is now in a clean state, ready for a fresh deployment."
}

# Call the main function
main "$@"