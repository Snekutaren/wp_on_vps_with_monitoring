#!/bin/bash
set -euo pipefail # Exit on error, unset variables, pipefail

#--- IMPORTANT NOTICE ---
# This setup script ensures the application stack at
# ${INSTALL_BASE_DIR}/${APP_NAME} exactly mirrors the state defined in the
# linked Git repository.
#####################################################################################
# *** IMPORTANT WARNING REGARDING DOCKER CONTAINERS ***
#
# This script detects if other Docker containers are already running on the host.
#
# If running containers are found, this script WILL NOT PROCEED WITH DEPLOYMENT
# and will instead EXIT. This prevents accidental port conflicts and ensures
# you are aware of existing services.
#
# If you intend to deploy this application stack and require existing Docker
# containers to be stopped, you must do so MANUALLY before re-running this script.
#
# A suggested command to stop ALL running Docker containers is provided in the
# output if this situation occurs. Use it with caution, as it affects all
# Dockerized services on this host.
#
# If you have custom configurations you wish to preserve, please back them
# up manually BEFORE running this script again.
#
# You can stop all containers with the following command (use with caution!):
#   sudo docker stop $(docker ps -aq)
#####################################################################################
#------------------------

#--- Configuration Defaults ---
# The base directory where the application stack will be installed.
# Standard Linux locations include /opt, /usr/local/opt, /srv.
INSTALL_BASE_DIR="/opt"

# Default base name for the application directory (e.g., 'wpmon')
DEFAULT_APP_BASE_NAME="wpmon"

# Default starting port numbers
HTTP_PORT="80"
HTTPS_PORT="443"
WP_PORT="80" # Default internal port for WordPress, as confirmed by docker-compose.yml
LOKI_PORT="3100"
GRAFANA_PORT="3000"

# The Git repository URL
REPO_URL="https://github.com/snekutaren/wp_on_vps_with_monitoring.git"

# The Git branch to clone. Can be overridden by the -b flag.
TARGET_BRANCH="main"

#--- Variables (will be set by CLI options or retain defaults) ---
# The final application directory name (e.g., 'wpmon', 'wpmon_2', 'my_app')
APP_NAME="$DEFAULT_APP_BASE_NAME" # Initial default, subject to CLI override

# Internal flags and values for option parsing
# APP_NAME_SUFFIX_VALUE will be set by -n and appended to APP_NAME
# CUSTOM_APP_NAME_PROVIDED will track if -a was used
# PORT_OFFSET will be set by -o
TEMP_DIR="" # Temporary directory for downloads, set during execution in main()

# --- Helper function to ensure a file ends with a newline ---
# This prevents content concatenation when appending.
ensure_newline_at_end() {
    local file="$1"
    if [ -f "$file" ]; then
        # Check if the last character is NOT a newline. wc -l returns 0 if no newline at end.
        if [ "$(tail -c 1 "$file" | wc -l)" -eq 0 ]; then
            echo "" >> "$file" || { echo "Error: Failed to append newline to $file. Exiting." >&2; exit 1; }
            echo "  Ensured '$file' ends with a newline."
        fi
    fi
}

# --- Function to fetch and synchronize application files ---
fetch_and_copy() {
    echo "=== Fetching and Synchronizing Application Files ==="
    local CLONE_DIR="${TEMP_DIR}/wp_on_vps_with_monitoring_temp_clone"

    # Ensure the temporary clone directory is clean before cloning
    if [ -d "$CLONE_DIR" ]; then
        echo "  Warning: Temporary clone directory '${CLONE_DIR}' already exists. Removing it."
        rm -rf "$CLONE_DIR" || { echo "Error: Failed to remove existing clone directory. Exiting." >&2; exit 1; }
    fi
    
    echo "  Cloning git repository branch '${TARGET_BRANCH}' to temporary location: ${CLONE_DIR}..."
    git clone -b "$TARGET_BRANCH" "$REPO_URL" "$CLONE_DIR" || { echo "Error: Git clone of branch '${TARGET_BRANCH}' failed. Exiting." >&2; exit 1; }
    
    # Synchronize the main application stack directory
    echo "  Synchronizing application stack to ${INSTALL_BASE_DIR}/$APP_NAME..."
    mkdir -p "${INSTALL_BASE_DIR}/$APP_NAME" || { echo "Error: Failed to create application base directory. Exiting." >&2; exit 1; }
    
    # rsync -av --delete synchronizes files and deletes extra files in destination
    rsync -av --delete "${CLONE_DIR}/opt/wpmon/" "${INSTALL_BASE_DIR}/$APP_NAME/" || { echo "Error: Failed to synchronize application stack. Exiting." >&2; exit 1; }
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

    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        echo "  Adding Docker GPG key..."
        install -m 0755 -d /etc/apt/keyrings || { echo "Error: Failed to create /etc/apt/keyrings. Exiting." >&2; exit 1; }
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo "Error: Failed to add Docker GPG key. Exiting." >&2; exit 1; }
        chmod 644 /etc/apt/keyrings/docker.gpg # Set permissions for the key file
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

# --- Function to setup environment files (.env) for each stack ---
setup_env() {
    echo "=== Setting Up Environment Files ==="
    for stack in "traefik" "webstack" "monitoring"; do
        local stack_env_file="${INSTALL_BASE_DIR}/$APP_NAME/${stack}/.env"
        local example_env_path="${INSTALL_BASE_DIR}/$APP_NAME/${stack}/example.env"
        
        echo "Processing .env file for stack: ${stack}"

        # Step 1: Ensure the .env file exists and has its base content
        if [ ! -f "$stack_env_file" ]; then
            if [ -f "$example_env_path" ]; then
                echo "  Copying $example_env_path to $stack_env_file (initial creation)."
                cp -v "$example_env_path" "$stack_env_file" || { echo "Error: Failed to copy ${stack} example.env. Exiting." >&2; exit 1; }
            else
                echo "  Creating empty .env file for ${stack} at $stack_env_file (no example.env found)."
                touch "$stack_env_file" || { echo "Error: Failed to create empty .env for ${stack}. Exiting." >&2; exit 1; }
            fi
            # IMPORTANT: Ensure the newly created/copied .env file ends with a newline.
            # This prevents subsequent 'echo >>' from concatenating onto the last line.
            ensure_newline_at_end "$stack_env_file"
        else
            echo "  .env file for ${stack} already exists. Preserving its content."
            # Also ensure existing files end with a newline for robust updates
            ensure_newline_at_end "$stack_env_file"
        fi

        # Step 2: Ensure APP_NAME is correctly set in the .env file (idempotent update)
        if grep -q "^APP_NAME=" "$stack_env_file"; then
            echo "  Updating APP_NAME in $stack_env_file to '$APP_NAME'."
            sed -i "s|^APP_NAME=.*|APP_NAME=$APP_NAME|" "$stack_env_file" || { echo "Error: Failed to update APP_NAME in ${stack} .env file. Exiting." >&2; exit 1; }
        else
            echo "  Appending APP_NAME=$APP_NAME to $stack_env_file."
            echo "APP_NAME=$APP_NAME" >> "$stack_env_file" || { echo "Error: Failed to append APP_NAME to ${stack} .env file. Exiting." >&2; exit 1; }
        fi
        
        # Step 3: Set/Update Port Variables based on stack (idempotent update)
        case "$stack" in
            "traefik")
                # Handle HTTP_PORT port
                if grep -q "^HTTP_PORT=" "$stack_env_file"; then
                    echo "  Updating HTTP_PORT in $stack_env_file to '$HTTP_PORT'."
                    sed -i "s|^HTTP_PORT=.*|HTTP_PORT=$HTTP_PORT|" "$stack_env_file" || { echo "Error: Failed to update HTTP_PORT in traefik .env file. Exiting." >&2; exit 1; }
                else
                    echo "  Appending HTTP_PORT=$HTTP_PORT to $stack_env_file."
                    echo "HTTP_PORT=$HTTP_PORT" >> "$stack_env_file" || { echo "Error: Failed to append HTTP_PORT to traefik .env file. Exiting." >&2; exit 1; }
                fi
                # Handle HTTPS_PORT port
                if grep -q "^HTTPS_PORT=" "$stack_env_file"; then
                    echo "  Updating HTTPS_PORT in $stack_env_file to '$HTTPS_PORT'."
                    sed -i "s|^HTTPS_PORT=.*|HTTPS_PORT=$HTTPS_PORT|" "$stack_env_file" || { echo "Error: Failed to update HTTPS_PORT in traefik .env file. Exiting." >&2; exit 1; }
                else
                    echo "  Appending HTTPS_PORT=$HTTPS_PORT to $stack_env_file."
                    echo "HTTPS_PORT=$HTTPS_PORT" >> "$stack_env_file" || { echo "Error: Failed to append HTTPS_PORT to traefik .env file. Exiting." >&2; exit 1; }
                fi
                ;;
            "webstack")
                # Handle WP_PORT
                if grep -q "^WP_PORT=" "$stack_env_file"; then
                    echo "  Updating WP_PORT in $stack_env_file to '$WP_PORT'."
                    sed -i "s|^WP_PORT=.*|WP_PORT=$WP_PORT|" "$stack_env_file" || { echo "Error: Failed to update WP_PORT in webstack .env file. Exiting." >&2; exit 1; }
                else
                    echo "  Appending WP_PORT=$WP_PORT to $stack_env_file."
                    echo "WP_PORT=$WP_PORT" >> "$stack_env_file" || { echo "Error: Failed to append WP_PORT to webstack .env file. Exiting." >&2; exit 1; }
                fi
                ;;
            "monitoring")
                # Handle LOKI_PORT
                if grep -q "^LOKI_PORT=" "$stack_env_file"; then
                    echo "  Updating LOKI_PORT in $stack_env_file to '$LOKI_PORT'."
                    sed -i "s|^LOKI_PORT=.*|LOKI_PORT=$LOKI_PORT|" "$stack_env_file" || { echo "Error: Failed to update LOKI_PORT in monitoring .env file. Exiting." >&2; exit 1; }
                else
                    echo "  Appending LOKI_PORT=$LOKI_PORT to $stack_env_file."
                    echo "LOKI_PORT=$LOKI_PORT" >> "$stack_env_file" || { echo "Error: Failed to append LOKI_PORT to monitoring .env file. Exiting." >&2; exit 1; }
                fi
                # Handle GRAFANA_PORT
                if grep -q "^GRAFANA_PORT=" "$stack_env_file"; then
                    echo "  Updating GRAFANA_PORT in $stack_env_file to '$GRAFANA_PORT'."
                    sed -i "s|^GRAFANA_PORT=.*|GRAFANA_PORT=$GRAFANA_PORT|" "$stack_env_file" || { echo "Error: Failed to update GRAFANA_PORT in monitoring .env file. Exiting." >&2; exit 1; }
                else
                    echo "  Appending GRAFANA_PORT=$GRAFANA_PORT to $stack_env_file."
                    echo "GRAFANA_PORT=$GRAFANA_PORT" >> "$stack_env_file" || { echo "Error: Failed to append GRAFANA_PORT to monitoring .env file. Exiting." >&2; exit 1; }
                fi
                ;;
        esac
        
        # The final newline check for robustness
        ensure_newline_at_end "$stack_env_file"

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

# --- Set execute permissions for management scripts ---
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

# --- Cleanup temporary files ---
cleanup() {
    echo "=== Cleaning Up Temporary Files ==="
    if [ -d "$TEMP_DIR" ]; then
        echo "Removing temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR" || echo "Warning: Failed to remove temporary directory." >&2
    fi
    echo "Cleanup complete."
}

# --- Deploy the Docker application stack ---
deploy() {
    echo "=== Initiating Application Deployment ==="

    # Set the Docker Compose project name to be unique for this stack.
    # This ensures containers are named like 'wpmon_1-traefik-1', 'wpmon_2-traefik-1', etc.,
    # instead of just 'traefik-traefik-1' for multiple deployments.
    export COMPOSE_PROJECT_NAME="$APP_NAME"
    echo "  Setting Docker Compose project name to: $COMPOSE_PROJECT_NAME"

    cd "${INSTALL_BASE_DIR}/$APP_NAME" || { echo "Error: Could not change to application root directory. Exiting." >&2; exit 1; }
    "./deploy.sh" || { echo "Error: Deployment script (deploy.sh) failed. Exiting." >&2; exit 1; }
    echo "Deployment initiated. Checking Docker processes..."
    docker ps || { echo "Warning: Failed to list Docker processes after deployment. Check Docker status manually." >&2; }
    echo ""
}

# --- Main Script Execution
main() {
    # CRUCIAL CHECK: Ensure the script is run as root (EUID 0 indicates root user)
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root." >&2;
        echo "Please execute it either as: 'sudo ./run_setup.sh' (if sudo is installed)" >&2;
        echo "OR: switch to the root user first (e.g., 'sudo su -' or 'su -') and then run './run_setup.sh'." >&2;
        exit 1;
    fi

    local CUSTOM_APP_BASE_NAME_ARG=""
    local APP_NAME_SUFFIX_ARG=""
    local PORT_OFFSET_ARG=0
    PORT_OFFSET_ARG="$((PORT_OFFSET_ARG - 1))"

    # Parse command-line options
    while getopts "b:a:n:o:" opt; do
      case $opt in
        b)
          TARGET_BRANCH="$OPTARG"
          ;;
        a) # Custom application base name
          CUSTOM_APP_BASE_NAME_ARG="$OPTARG"
          ;;
        n) # Numeric suffix for application name (e.g., for wpmon_2)
          APP_NAME_SUFFIX_ARG="_$OPTARG"
          ;;
        o) # Global port offset (added to all default ports)
          PORT_OFFSET_ARG="$OPTARG"
          ;;
        \?)
          echo "Invalid option: -$OPTARG" >&2
          exit 1
          ;;
      esac
    done
    shift $((OPTIND-1)) # Shift positional parameters

    # Determine final APP_NAME
    if [ -n "$CUSTOM_APP_BASE_NAME_ARG" ]; then
        APP_NAME="${CUSTOM_APP_BASE_NAME_ARG}${APP_NAME_SUFFIX_ARG}"
    else
        APP_NAME="${DEFAULT_APP_BASE_NAME}${APP_NAME_SUFFIX_ARG}"
    fi

    # Apply global port offset to all relevant ports
    HTTP_PORT=$((HTTP_PORT + PORT_OFFSET_ARG))
    HTTPS_PORT=$((HTTPS_PORT + PORT_OFFSET_ARG))
    WP_PORT=$((WP_PORT + PORT_OFFSET_ARG))
    LOKI_PORT=$((LOKI_PORT + PORT_OFFSET_ARG))
    GRAFANA_PORT=$((GRAFANA_PORT + PORT_OFFSET_ARG))

    # Create a temporary directory and set up cleanup trap
    TEMP_DIR=$(mktemp -d) || { echo "Error: Failed to create temporary directory. Exiting." >&2; exit 1; }
    trap cleanup EXIT # Ensures cleanup runs on script exit or error

    # Execute setup steps in order
    fetch_and_copy
    install_prerequisites
    install_docker
    setup_env
    create_backup_key_password
    set_management_script_permissions
    deploy 

    echo -e "\n--- Setup and Deployment Process Complete ---"
    echo "Your application is installed at: ${INSTALL_BASE_DIR}/$APP_NAME"
    echo "You can manage it using the scripts in that directory:"
    echo "   ${INSTALL_BASE_DIR}/$APP_NAME/deploy.sh"
    echo "   ${INSTALL_BASE_DIR}/$APP_NAME/reset.sh"
    echo "   ${INSTALL_BASE_DIR}/$APP_NAME/restart.sh"
    echo "   ${INSTALL_BASE_DIR}/$APP_NAME/shutdown.sh"
    echo "Please ensure your .env files are correctly configured and DNS records are set up."
    echo "Review the output above for any errors or warnings."
}

# Call the main function
main "$@"