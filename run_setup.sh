#!/bin/bash

#--- Configuration ---
# The directory where the project is extracted.
# We determine this dynamically based on the script's location.
#SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
#PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")

# The stack will be installed into /opt/$APP_NAME
APP_NAME=wpmon

fetch_and_copy() {
    echo "Cloning git..."
    git clone https://github.com/snekutaren/wp_on_vps_with_monitoring.git
    echo "Copying files..."
    sudo rsync -av "./wp_on_vps_with_monitoring/etc/" "/etc/"
    echo "Moving application stack to /opt/$APP_NAME..."
    # Add a safety check to remove existing directory if it causes issues for mv
    if [ -d "/opt/$APP_NAME" ]; then
        echo "Warning: /opt/$APP_NAME already exists. Deleting it before moving the new version."
        sudo rm -rf "/opt/$APP_NAME"
    fi
    # This is the CRUCIAL line that directly targets the *nested* application directory
    # and moves/renames it to `/opt/$APP_NAME`.
    sudo mv "./wp_on_vps_with_monitoring/opt/wp_on_vps_with_monitoring" "/opt/$APP_NAME"
}

# --- Function to install common prerequisites ---
install_prerequisites() {
    echo "Installing common prerequisites..."

    # Update package list
    apt update -y

    # Install essential packages
    apt install -y \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        net-tools \
        nftables \
        dnsutils \
        rsync \
        rclone \
        htop \
        tar \
        gzip

    if [ $? -eq 0 ]; then
        echo "Prerequisites installed successfully."
    else
        echo "Error: Failed to install prerequisites. Exiting."
        exit 1
    fi
}

# --- Function to install Docker from the official repository ---
install_docker() {
    echo "Installing Docker from the official repository..."

    # Add Docker's official GPG key
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        echo "Adding Docker GPG key..."
        install -m 0755 -d /etc/apt/keyrings
        # Corrected: Changed /linux/debian/gpg to /linux/ubuntu/gpg
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        if [ $? -ne 0 ]; then
            echo "Error: Failed to add Docker GPG key. Exiting."
            exit 1
        fi
    fi

    # Set up the Docker repository
    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
        echo "Setting up Docker repository..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        if [ $? -ne 0 ]; then
            echo "Error: Failed to set up Docker repository. Exiting."
            exit 1
        fi
    fi

    # Update apt package index
    apt update -y
    if [ $? -ne 0 ]; then
        echo "Error: Failed to update apt package index. Exiting."
        exit 1
    fi

    # Install Docker Engine, containerd, and Docker Compose
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    if [ $? -eq 0 ]; then
        echo "Docker installed successfully."
        systemctl enable docker
        systemctl start docker
    else
        echo "Error: Failed to install Docker. Exiting."
        exit 1
    fi
}

setup_env() {
    mv -v /opt/$APP_NAME/traefik/example.env /opt/$APP_NAME/traefik/.env
    mv -v /opt/$APP_NAME/webstack/example.env /opt/$APP_NAME/webstack/.env
    mv -v /opt/$APP_NAME/monitoring/example.env /opt/$APP_NAME/monitoring/.env
}

# --- Password for backup key ---
create_backup_key_password() {
    echo "Generating a random password for backup key..."

    # Use the corrected command and check its exit status immediately
    if tr -dc A-Za-z0-9_ < /dev/urandom | head -c 32 > /root/backup_passphrase.key; then
        echo "Password generated successfully." # Indicate success of generation
        
        # Add the newline only if the key was written
        echo "" >> /root/backup_passphrase.key

        # Set permissions and check if chmod was successful
        if chmod 600 /root/backup_passphrase.key; then
            echo -e "\nRandom password generated and saved to /root/backup_passphrase.key with proper permissions."
            echo "Please take notice of or change backup password in /root/backup_passphrase.key"
        else
            echo "Error: Failed to set permissions for /root/backup_passphrase.key. Exiting."
            exit 1 # Exit if chmod fails
        fi
    else
        echo "Error: Failed to generate or save backup password to /root/backup_passphrase.key. Exiting."
        exit 1 # Exit if the password generation pipeline fails
    fi
}

remove_download_dir() {
    echo "Removing git clone download directory.."
    rm -rf ./wp_on_vps_with_monitoring/
}

deploy() {
    cd /opt/$APP_NAME/bin/deploy
    /opt/$APP_NAME/bin/deploy/deploy.sh
    docker ps
}

# --- Main script execution ---
main() {
    # Ensure the script is run as root
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root."
        exit 1
    fi
    fetch_and_copy
    install_prerequisites
    install_docker
    setup_env
    create_backup_key_password
    remove_download_dir
    deploy
}

# Call the main function
main
