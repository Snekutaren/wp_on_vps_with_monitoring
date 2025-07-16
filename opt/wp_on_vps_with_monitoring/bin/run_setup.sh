#!/bin/bash

4# --- Configuration ---
# The directory where the project is extracted.
# We determine this dynamically based on the script's location.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")

fetching_and_copy() {
    echo "Cloning git.."
    git clone https://github.com/snekutaren/wp_on_vps_with_monitoring.git

    echo "Copying files.."
    sudo rsync -av ./wp_on_vps_with_monitoring/etc/ /etc/
    sudo rsync -av ./wp_on_vps_with_monitoring/opt/ /opt/
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

# --- Password for backup key ---
create_backup_key_password() {
    echo ""
    read -p "Do you want to supply a password for the backup key? If no a random password will be generated (yes/no): " choice
    case "$choice" in
        yes|Yes|Y|y )
            read -sp "Enter password for backup key: " backup_pass
            echo "$backup_pass" > /root/backup_passphrase.key
            chmod 600 /root/backup_passphrase.key
            echo -e "\nPassword saved to /root/backup_passphrase.key with proper permissions."
            ;;
        no|No|N|n )
            echo "Generating a random password for backup key..."
            < /dev/urandom tr -dc A-Za-z0-9_ | head -c 32 > /root/backup_passphrase.key
	    echo "" | sudo tee -a /root/backup_passphrase.key > /dev/null
            chmod 600 /root/backup_passphrase.key
            echo -e "\nRandom password generated and saved to /root/backup_passphrase.key with proper permissions."
            ;;
        * )
            echo "Invalid choice. Skipping backup key password setup."
            ;;
    esac
}

remove_download_dir() {
    echo "Removing git clone download directory.."
    rm -rf ./wp_on_vps_with_monitoring/
}

# --- Main script execution ---
main() {
    # Ensure the script is run as root
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root."
        exit 1
    fi
    fetching_and_copy
    install_prerequisites
    install_docker
    create_backup_key_password
    echo ""
    echo "Setup script finished."
    echo "Please take notice of backup password in /root/backup_passphrase.key"
    remove_download_dir
}

# Call the main function
main
