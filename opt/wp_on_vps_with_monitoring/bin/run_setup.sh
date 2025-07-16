#!/bin/bash

# --- Configuration ---
# The directory where the project is extracted.
# We determine this dynamically based on the script's location.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")

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

# --- Function to move project files into place ---
setup_files() {
    echo "Starting file setup..."

    # Check if we are running from a temporary or non-root location
    if [[ "$PROJECT_ROOT_DIR" != "/" ]]; then
        echo "Detected project extracted at: $PROJECT_ROOT_DIR"
        echo "Moving files to their respective system locations."

        # Move etc, opt, var directories
        # We use 'rsync -av' for merging directories, handling existing files gracefully.
        # Then, we remove the source directory to effectively "move" it.

        if [ -d "$PROJECT_ROOT_DIR/etc" ]; then
            echo "Moving 'etc' directory contents to /etc/..."
            rsync -av "$PROJECT_ROOT_DIR/etc/" "/etc/"
            rm -rf "$PROJECT_ROOT_DIR/etc" # Remove after successful rsync
        fi

        if [ -d "$PROJECT_ROOT_DIR/opt" ]; then
            echo "Moving 'opt' directory contents to /opt/..."
            rsync -av "$PROJECT_ROOT_DIR/opt/" "/opt/"
            rm -rf "$PROJECT_ROOT_DIR/opt"
        fi

        if [ -d "$PROJECT_ROOT_DIR/var" ]; then
            echo "Moving 'var' directory contents to /var/..."
            rsync -av "$PROJECT_ROOT_DIR/var/" "/var/"
            rm -rf "$PROJECT_ROOT_DIR/var"
        fi

        # Copy helper scripts to /usr/local/bin and make them executable
        echo "Copying helper scripts to /usr/local/bin..."
        mkdir -p /usr/local/bin

        SCRIPTS=(
            "firewall_add_domain.sh"
            "firewall_add_ip.sh"
            "flush_iptables.sh"
            "flush_nft_docker.sh"
        )

        for script in "${SCRIPTS[@]}"; do
            if [ -f "$PROJECT_ROOT_DIR/$script" ]; then
                cp "$PROJECT_ROOT_DIR/$script" "/usr/local/bin/"
                chmod +x "/usr/local/bin/$script"
                echo "Copied and made executable: /usr/local/bin/$script"
                rm "$PROJECT_ROOT_DIR/$script" # Remove after successful copy
            fi
        done

        # After moving/copying, remove the project's root directory if it's empty
        # or contains only .gitignore or similar meta files.
        echo "Cleaning up temporary project directory: $PROJECT_ROOT_DIR"
        find "$PROJECT_ROOT_DIR" -depth -empty -delete 2>/dev/null || true # Delete empty directories
        if [ -d "$PROJECT_ROOT_DIR" ] && [ -z "$(ls -A "$PROJECT_ROOT_DIR")" ]; then
            rmdir "$PROJECT_ROOT_DIR" 2>/dev/null || true
        fi

        echo "File setup complete."
    else
        echo "Script is running from the root directory. Assuming files are already in place."
        echo "Ensuring helper scripts in /usr/local/bin are executable."
        chmod +x /usr/local/bin/firewall_add_domain.sh 2>/dev/null || true
        chmod +x /usr/local/bin/firewall_add_ip.sh 2>/dev/null || true
        chmod +x /usr/local/bin/flush_iptables.sh 2>/dev/null || true
        chmod +x /usr/local/bin/flush_nft_docker.sh 2>/dev/null || true
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
            chmod 600 /root/backup_passphrase.key
            echo -e "\nRandom password generated and saved to /root/backup_passphrase.key with proper permissions."
            ;;
        * )
            echo "Invalid choice. Skipping backup key password setup."
            ;;
    esac
}

# --- Main script execution ---
main() {
    # Ensure the script is run as root
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root."
        exit 1
    fi

    install_prerequisites
    install_docker
    setup_files
    create_backup_key_password
    echo ""
    echo "Setup script finished."
    echo "Please review the configurations and restart necessary services if required (e.g., Docker, nftables service)."
}

# Call the main function
main