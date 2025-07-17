#!/bin/bash
set -euo pipefail # Exit on error, unset variables, pipefail

#--- IMPORTANT NOTICE ---
# This setup script is designed to ensure the application stack at
# ${INSTALL_BASE_DIR}/${APP_NAME} exactly mirrors the state defined in the
# linked Git repository.
#
# If this script is run multiple times, it will overwrite any previous
# manual modifications or custom configurations within the application's
# directories (e.g., .env files).
#
# If you have custom configurations you wish to preserve, please back them
# up manually BEFORE running this script again.
#------------------------

#--- Configuration ---
# The base directory where the application stack will be installed.
# Standard Linux locations include /opt, /usr/local/opt, /srv.
INSTALL_BASE_DIR="/opt" # You can change this default if needed

# The name of the application directory within $INSTALL_BASE_DIR
APP_NAME="wpmon"

# The Git branch to clone. Can be overridden by the -b flag.
TARGET_BRANCH="main"

# Temporary directory for downloads, will be set during execution in main()
TEMP_DIR=""

fetch_and_copy() {
    echo "=== Fetching and Synchronizing Application Files ==="
    local REPO_URL="https://github.com/snekutaren/wp_on_vps_with_monitoring.git"
    local CLONE_DIR="${TEMP_DIR}/wp_on_vps_with_monitoring_temp_clone" # Use the temporary dir for cloning

    # Ensure the temporary clone directory is clean before cloning
    if [ -d "$CLONE_DIR" ]; then
        echo "  Warning: Temporary clone directory '${CLONE_DIR}' already exists. Removing it."
        rm -rf "$CLONE_DIR" || { echo "Error: Failed to remove existing clone directory. Exiting." >&2; exit 1; }
    fi
    
    echo "  Cloning git repository branch '${TARGET_BRANCH}' to temporary location: ${CLONE_DIR}..."
    git clone -b "$TARGET_BRANCH" "$REPO_DIR" "$CLONE_DIR" || { echo "Error: Git clone of branch '${TARGET_BRANCH}' failed. Exiting." >&2; exit 1; }
    
    # Removed: All code related to '/etc' synchronization, as per your instruction.

    # Synchronize the main application stack directory
    echo "  Synchronizing application stack to ${INSTALL_BASE_DIR}/$APP_NAME..."
    # Create the base directory if it doesn't exist
    mkdir -p "${INSTALL_BASE_DIR}/$APP_NAME" || { echo "Error: Failed to create application base directory. Exiting." >&2; exit 1; }
    
    # rsync -av --delete will:
    # - Synchronize files from source to destination.
    # - Create destination directories if they don't exist.
    # - Update existing files if they are newer in the source.
    # - Delete files in the destination that are no longer in the source (--delete).
    # This effectively makes the destination mirror the source's content without deleting the top-level folder itself.
    # REVERTED: The rsync source path is now back to "${CLONE_DIR}/opt/wp_on_vps_with_monitoring/"
    rsync -av --delete "${CLONE_DIR}/opt/wp_on_vps_with_monitoring/" "${INSTALL_BASE_DIR}/$APP_NAME/" || { echo "Error: Failed to synchronize application stack. Exiting." >&2; exit 1; }
    echo "Application files synchronization complete."
    echo ""
}

# --- Function to install common prerequisites ---
install_prerequisites() {
    echo "=== Installing Common Prerequisites ==="
    apt update -y || { echo "Error: Failed to update package list. Exiting." >&2; exit 1; }
    apt install -y curl gnupg lsb-release software-properties-common net-tools nftables dnsutils rsync rclone htop tar gzip || { echo "Error: Failed to install prerequisites. Exiting." >&2; exit 1; }
    echo "Prerequisites installed successfully."
    echo ""
}

# --- Function to install Docker from the official repository ---
install_docker() {
    echo "=== Installing Docker from Official Repository ==="

    # Removed: 'if command -v docker ... then return 0 fi' block, as per your preference.
    # Relying on apt's internal idempotency for installation process.

    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        echo "  Adding Docker GPG key..."
        install -m 0755 -d /etc/apt/keyrings || { echo "Error: Failed to create /etc/apt/keyrings. Exiting." >&2; exit 1; }
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo "Error: Failed to add Docker GPG key. Exiting." >&2; exit 1; }
        chmod 644 /etc/apt/keyrings/docker.gpg # Set permissions for the key file as requested
        echo "  Docker GPG key added."
    fi

    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
        echo "  Setting up Docker repository..."
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo "Error: Failed to set up Docker repository. Exiting." >&2; exit 1; }
        echo "  Docker repository set up."
    fi

    apt update -y || { echo "Error: Failed to update apt package index. Exiting." >&2; exit 1; }
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo "Error: Failed to install Docker components. Exiting." >&2; exit 1; }

    echo "Docker installed successfully."
    systemctl enable docker || { echo "Error: Failed to enable Docker service. Exiting." >&2; exit 1; }
    systemctl start docker || { echo "Error: Failed to start Docker service. Exiting." >&2; exit 1; }
    echo "Docker and Docker Compose setup complete."
    echo ""
}

setup_env() {
    echo "=== Setting Up Environment Files ==="
    for stack in "traefik" "webstack" "monitoring"; do
        local stack_env_file="${INSTALL_BASE_DIR}/$APP_NAME/${stack}/.env"
        local example_env_path="${INSTALL_BASE_DIR}/$APP_NAME/${stack}/example.env"
        
        echo "Processing .env file for stack: ${stack}"

        # Step 1: Ensure the .env file exists and has its base content
        if [ ! -f "$stack_env_file" ]; then
            # If .env file does NOT exist, create it from example.env or as an empty file
            if [ -f "$example_env_path" ]; then
                echo "  Copying $example_env_path to $stack_env_file (initial creation)."
                cp -v "$example_env_path" "$stack_env_file" || { echo "Error: Failed to copy ${stack} example.env. Exiting." >&2; exit 1; }
            else
                echo "  Creating empty .env file for ${stack} at $stack_env_file (no example.env found)."
                touch "$stack_env_file" || { echo "Error: Failed to create empty .env for ${stack}. Exiting." >&2; exit 1; }
            fi
        else
            echo "  .env file for ${stack} already exists. Preserving its content."
        fi

        # Step 2: Ensure APP_NAME is correctly set in the .env file (idempotent update)
        # This uses the idempotent logic discussed for updating APP_NAME.
        if grep -q "^APP_NAME=" "$stack_env_file"; then
            echo "  Updating APP_NAME in $stack_env_file to '$APP_NAME'."
            sed -i "s|^APP_NAME=.*|APP_NAME=$APP_NAME|" "$stack_env_file" || { echo "Error: Failed to update APP_NAME in ${stack} .env file. Exiting." >&2; exit 1; }
        else
            echo "  Appending APP_NAME=$APP_NAME to $stack_env_file."
            echo "APP_NAME=$APP_NAME" >> "$stack_env_file" || { echo "Error: Failed to append APP_NAME to ${stack} .env file. Exiting." >&2; exit 1;