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
    git clone -b "$TARGET_BRANCH" "$REPO_URL" "$CLONE_DIR" || { echo "Error: Git clone of branch '${TARGET_BRANCH}' failed. Exiting." >&2; exit 1; }
    
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
    # It assumes the target content is within 'opt/wp_on_vps_with_monitoring' inside the cloned repo.
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
            echo "APP_NAME=$APP_NAME" >> "$stack_env_file" || { echo "Error: Failed to append APP_NAME to ${stack} .env file. Exiting." >&2; exit 1; }
        fi
        
        # Step 3: Ensure the file ends with a newline character for best practice
        # This check prevents adding multiple blank lines if one already exists
        [ "$(tail -c 1 "$stack_env_file" | wc -l)" -eq 0 ] && echo "" >> "$stack_env_file"

    done
    echo "Environment files setup complete."
    echo ""
}

# --- Password for backup key ---
create_backup_key_password() {
    echo "=== Creating Backup Key Password ==="
    local BACKUP_KEY_PATH="/root/backup_passphrase.key"

    if [ -f "$BACKUP_KEY_PATH" ]; then
        echo "  Backup key password file already exists at ${BACKUP_KEY_PATH}. Preserving existing key."
        echo "  Please take notice of or change backup password in ${BACKUP_KEY_PATH} if needed."
    else
        echo "  Generating a random password for backup key..."
        if tr -dc 'A-Za-z0-9_' < /dev/urandom | head -c 32 | tee "$BACKUP_KEY_PATH" > /dev/null; then
            echo "" | tee -a "$BACKUP_KEY_PATH" > /dev/null # Ensure a newline
            if chmod 600 "$BACKUP_KEY_PATH"; then
                echo -e "  Random password generated and saved to ${BACKUP_KEY_PATH} with proper permissions."
                echo "  Please take notice of or change backup password in ${BACKUP_KEY_PATH}"
            else
                echo "Error: Failed to set permissions for ${BACKUP_KEY_PATH}. Exiting." >&2; exit 1;
            fi
        else
            echo "Error: Failed to generate or save backup password to ${BACKUP_KEY_PATH}. Exiting." >&2; exit 1;
        fi
    fi
    echo "Backup key password setup complete."
    echo ""
}

set_management_script_permissions() {
    echo "=== Setting Management Script Permissions ==="
    local SCRIPT_DIR="${INSTALL_BASE_DIR}/${APP_NAME}"
    echo "Setting execute permissions for management scripts in ${SCRIPT_DIR}..."
    chmod +x "${SCRIPT_DIR}/deploy.sh" \
             "${SCRIPT_DIR}/reset.sh" \
             "${SCRIPT_DIR}/restart.sh" \
             "${SCRIPT_DIR}/shutdown.sh" || { echo "Error: Failed to set execute permissions on management scripts. Exiting." >&2; exit 1; }
    echo "Management script permissions set successfully."
    echo ""
}

# Renamed from 'remove_download_dir' to 'cleanup' and updated to use TEMP_DIR
cleanup() {
    echo "=== Cleaning Up Temporary Files ==="
    if [ -d "$TEMP_DIR" ]; then
        echo "Removing temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR" || echo "Warning: Failed to remove temporary directory." >&2
    fi
    echo "Cleanup complete."
}

deploy() {
    echo "=== Initiating Application Deployment ==="

    # Check for active Docker containers before deployment, as per instruction.
    if docker ps -q | grep -q .; then
        echo "Error: Docker containers are already running on this host." >&2
        echo "This deployment will likely result in port conflicts (e.g., ports 80, 443)." >&2
        echo "If you intend to run multiple application stacks, you must manually adjust the" >&2
        echo "exposed ports in their respective 'docker-compose.yml' files or stop existing" >&2
        echo "Docker services before running this setup script." >&2
        exit 1 # Exit immediately as per instruction
    fi

    cd "${INSTALL_BASE_DIR}/$APP_NAME" || { echo "Error: Could not change to application root directory. Exiting." >&2; exit 1; }
    "./deploy.sh" || { echo "Error: Deployment script (deploy.sh) failed. Exiting." >&2; exit 1; }
    echo "Deployment initiated. Checking Docker processes..."
    docker ps || { echo "Warning: Failed to list Docker processes after deployment. Check Docker status manually." >&2; }
    echo ""
}

# --- Main script execution ---
main() {
    # CRUCIAL CHECK: Ensure the script is run as root (EUID 0 indicates root user)
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root." >&2;
        echo "Please execute it either as: 'sudo ./run_setup.sh' (if sudo is installed)" >&2;
        echo "OR: switch to the root user first (e.g., 'sudo su -' or 'su -') and then run './run_setup.sh'." >&2;
        exit 1;
    fi

    # Parse command-line options
    while getopts "b:" opt; do
      case $opt in
        b)
          TARGET_BRANCH="$OPTARG"
          ;;
        \?)
          echo "Invalid option: -$OPTARG" >&2
          exit 1
          ;;
      esac
    done
    shift $((OPTIND-1)) # Shift positional parameters, so remaining arguments are not processed as options
    
    # Create a temporary directory and set up cleanup trap, as requested
    TEMP_DIR=$(mktemp -d) || { echo "Error: Failed to create temporary directory. Exiting." >&2; exit 1; }
    trap cleanup EXIT # Ensures cleanup runs on script exit or error

    fetch_and_copy
    install_prerequisites
    install_docker
    setup_env
    create_backup_key_password
    set_management_script_permissions
    deploy 

    echo -e "\n--- Setup and Deployment Process Complete ---"
    echo "Your application is installed at: ${INSTALL_BASE_DIR}/$APP_NAME"
    echo "You can manage it using:"
    echo "   ${INSTALL_BASE_DIR}/$APP_NAME/deploy.sh"
    echo "   ${INSTALL_BASE_DIR}/$APP_NAME/reset.sh"
    echo "   ${INSTALL_BASE_DIR}/$APP_NAME/restart.sh" # Included in final message as its permissions are now set
    echo "   ${INSTALL_BASE_DIR}/$APP_NAME/shutdown.sh" # Included in final message as its permissions are now set
    echo "Please ensure your .env files are correctly configured and DNS records are set up."
    echo "Check the output above for any errors or warnings."
}

# Call the main function
main "$@"