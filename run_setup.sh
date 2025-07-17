#!/bin/bash
set -euo pipefail # Exit on error, unset variables, pipefail

#--- Configuration ---
# The base directory where the application stack will be installed.
# Standard Linux locations include /opt, /usr/local/opt, /srv.
INSTALL_BASE_DIR="/opt" # You can change this default if needed

# The name of the application directory within $INSTALL_BASE_DIR
APP_NAME="wpmon"

fetch_and_copy() {
    echo "Cloning git repository..."
    if [ -d "./wp_on_vps_with_monitoring" ]; then
        echo "Warning: Temporary clone directory './wp_on_vps_with_monitoring' already exists. Removing it."
        rm -rf "./wp_on_vps_with_monitoring" || { echo "Error: Failed to remove existing clone directory. Exiting." >&2; exit 1; }
    fi
    git clone https://github.com/snekutaren/wp_on_vps_with_monitoring.git || { echo "Error: Git clone failed. Exiting." >&2; exit 1; }
    
    echo "Copying host-level /etc configurations..."
    rsync -av "./wp_on_vps_with_monitoring/etc/" "/etc/" || { echo "Error: Failed to copy /etc configurations. Exiting." >&2; exit 1; }

    echo "Moving application stack to ${INSTALL_BASE_DIR}/$APP_NAME..."
    if [ -d "${INSTALL_BASE_DIR}/$APP_NAME" ]; then
        echo "Warning: ${INSTALL_BASE_DIR}/$APP_NAME already exists. Deleting it before moving the new version."
        rm -rf "${INSTALL_BASE_DIR}/$APP_NAME" || { echo "Error: Failed to remove existing app directory. Exiting." >&2; exit 1; }
    fi
    mv "./wp_on_vps_with_monitoring/opt/wp_on_vps_with_monitoring" "${INSTALL_BASE_DIR}/$APP_NAME" || { echo "Error: Failed to move application stack. Exiting." >&2; exit 1; }
}

# --- Function to install common prerequisites ---
install_prerequisites() {
    echo "Installing common prerequisites..."
    apt update -y || { echo "Error: Failed to update package list. Exiting." >&2; exit 1; }
    apt install -y curl gnupg lsb-release software-properties-common net-tools nftables dnsutils rsync rclone htop tar gzip || { echo "Error: Failed to install prerequisites. Exiting." >&2; exit 1; }
    echo "Prerequisites installed successfully."
}

# --- Function to install Docker from the official repository ---
install_docker() {
    echo "Installing Docker from the official repository..."

    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        echo "Adding Docker GPG key..."
        install -m 0755 -d /etc/apt/keyrings || { echo "Error: Failed to create /etc/apt/keyrings. Exiting." >&2; exit 1; }
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo "Error: Failed to add Docker GPG key. Exiting." >&2; exit 1; }
    fi

    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
        echo "Setting up Docker repository..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo "Error: Failed to set up Docker repository. Exiting." >&2; exit 1; }
    fi

    apt update -y || { echo "Error: Failed to update apt package index. Exiting." >&2; exit 1; }
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo "Error: Failed to install Docker components. Exiting." >&2; exit 1; }

    echo "Docker installed successfully."
    systemctl enable docker || { echo "Error: Failed to enable Docker service. Exiting." >&2; exit 1; }
    systemctl start docker || { echo "Error: Failed to start Docker service. Exiting." >&2; exit 1; }
}

setup_env() {
    echo "Setting up environment files for Docker Compose stacks..."
    for stack in "traefik" "webstack" "monitoring"; do
        if [ -f "${INSTALL_BASE_DIR}/$APP_NAME/${stack}/example.env" ]; then
            mv -v "${INSTALL_BASE_DIR}/$APP_NAME/${stack}/example.env" "${INSTALL_BASE_DIR}/$APP_NAME/${stack}/.env" || { echo "Error: Failed to setup ${stack} .env file. Exiting." >&2; exit 1; }
        else
            echo "Warning: example.env not found for ${stack}. Skipping .env setup for this stack." >&2
        fi
    done
    echo "Environment files setup attempted."
}

# --- Password for backup key ---
create_backup_key_password() {
    echo "Generating a random password for backup key..."
    if tr -dc 'A-Za-z0-9_' < /dev/urandom | head -c 32 | tee "/root/backup_passphrase.key" > /dev/null; then
        echo "Password generated successfully."
        echo "" | tee -a "/root/backup_passphrase.key" > /dev/null # Ensure a newline
        if chmod 600 "/root/backup_passphrase.key"; then
            echo -e "\nRandom password generated and saved to /root/backup_passphrase.key with proper permissions."
            echo "Please take notice of or change backup password in /root/backup_passphrase.key"
        else
            echo "Error: Failed to set permissions for /root/backup_passphrase.key. Exiting." >&2; exit 1;
        fi
    else
        echo "Error: Failed to generate or save backup password to /root/backup_passphrase.key. Exiting." >&2; exit 1;
    fi
}

set_management_script_permissions() {
    echo "Setting execute permissions for management scripts..."
    chmod +x "${INSTALL_BASE_DIR}/$APP_NAME/deploy.sh" || { echo "Error: Failed to set execute permissions on deploy.sh. Exiting." >&2; exit 1; }
    chmod +x "${INSTALL_BASE_DIR}/$APP_NAME/reset.sh" || { echo "Error: Failed to set execute permissions on reset.sh. Exiting." >&2; exit 1; }
    echo "Management script permissions set successfully."
}

remove_download_dir() {
    echo "Removing git clone download directory: ./wp_on_vps_with_monitoring/..."
    rm -rf "./wp_on_vps_with_monitoring/" || { echo "Error: Failed to remove download directory. Exiting." >&2; exit 1; }
    echo "Download directory removed."
}

deploy() {
    echo "Initiating application deployment using deploy.sh..."
    cd "${INSTALL_BASE_DIR}/$APP_NAME" || { echo "Error: Could not change to application root directory. Exiting." >&2; exit 1; }
    "./deploy.sh" || { echo "Error: Deployment script (deploy.sh) failed. Exiting." >&2; exit 1; }
    echo "Deployment initiated. Checking Docker processes..."
    docker ps || { echo "Error: Failed to list Docker processes after deployment." >&2; }
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
    
    fetch_and_copy
    install_prerequisites
    install_docker
    setup_env
    create_backup_key_password
    set_management_script_permissions
    remove_download_dir
    deploy 

    echo -e "\n--- Setup and Deployment Process Complete ---"
    echo "Your application is installed at: ${INSTALL_BASE_DIR}/$APP_NAME"
    echo "You can manage it using:"
    echo "  ${INSTALL_BASE_DIR}/$APP_NAME/deploy.sh"
    echo "  ${INSTALL_BASE_DIR}/$APP_NAME/reset.sh"
    echo "Please ensure your .env files are correctly configured and DNS records are set up."
    echo "Check the output above for any errors or warnings."
}

# Call the main function
main "$@"