#!/bin/bash

# --- Configuration ---
BACKUP_DIR="/var/backups/wp_on_vps_with monitoring"
PASSPHRASE_FILE="/root/backup_passphrase.key"
RCLONE_REMOTE="gdrive:vps_backups" # Your rclone remote destination

# --- Timestamp for Backup Directory ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

# --- Basic Setup and Validation ---

# Ensure passphrase file exists and is readable
if [ ! -s "$PASSPHRASE_FILE" ]; then
    echo "Error: Passphrase file ($PASSPHRASE_FILE) not found or is empty. Exiting."
    exit 1
fi
if [ ! -r "$PASSPHRASE_FILE" ]; then
    echo "Error: Passphrase file ($PASSPHRASE_FILE) is not readable. Set permissions to 0400 or 0600. Exiting."
    exit 1
fi

# Create local backup directory
mkdir -p "$BACKUP_PATH" || { echo "Error: Failed to create $BACKUP_PATH. Exiting."; exit 1; }

# --- Core Backup Functions ---

# Function to encrypt and generate checksum
process_backup() {
    local source_path="$1"
    local archive_name="$2"
    local encrypted_archive="$BACKUP_PATH/${archive_name}.tar.gz.gpg"
    local checksum_file="${encrypted_archive}.sha256"

    echo "Compressing and encrypting $source_path..."
    tar -czf - -C "$(dirname "$source_path")" "$(basename "$source_path")" | \
    gpg --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSPHRASE_FILE" \
        --batch --yes \
        --pinentry-mode loopback \
        -o "$encrypted_archive" || { echo "Error: Encryption failed for $source_path. Exiting."; exit 1; }
    echo "Encryption complete: $encrypted_archive"

    echo "Generating checksum for $encrypted_archive..."
    sha256sum "$encrypted_archive" > "$checksum_file" || { echo "Error: Checksum generation failed for $encrypted_archive. Exiting."; exit 1; }
    echo "Checksum generated: $checksum_file"

    # Verify checksum immediately
    echo "Verifying checksum for $encrypted_archive..."
    sha256sum --check "$checksum_file" || { echo "Error: Checksum verification failed for $encrypted_archive. Exiting."; exit 1; }
    echo "Checksum verification successful."
}

# --- 1. System Files Backup ---
echo "--- Starting System Files Backup ---"
SYSTEM_SNAPSHOT_DIR="$BACKUP_PATH/system_snapshot_$TIMESTAMP"
mkdir -p "$SYSTEM_SNAPSHOT_DIR" || { echo "Error: Failed to create $SYSTEM_SNAPSHOT_DIR. Exiting."; exit 1; }

echo "Rsyncing root filesystem to $SYSTEM_SNAPSHOT_DIR..."
rsync -aHX --numeric-ids \
    --exclude=/proc/* --exclude=/sys/* --exclude=/dev/* --exclude=/run/* --exclude=/tmp/* --exclude=/var/tmp/* --exclude=/backup/* \
    --exclude=/var/lib/docker/* \
    --exclude=/lost+found/* --exclude=/cdrom/* --exclude=/media/* \
    --exclude=/var/log/* \
    / "$SYSTEM_SNAPSHOT_DIR" || { echo "Error: Rsync failed for system files. Exiting."; exit 1; }

process_backup "$SYSTEM_SNAPSHOT_DIR" "system_$TIMESTAMP"
rm -rf "$SYSTEM_SNAPSHOT_DIR" # Clean up unencrypted snapshot
echo "System files backup complete."

### 2. Docker Volumes Backup

echo "--- Starting Docker Volumes Backup ---"
DOCKER_SNAPSHOT_DIR="$BACKUP_PATH/docker_volumes_snapshot_$TIMESTAMP"
mkdir -p "$DOCKER_SNAPSHOT_DIR" || { echo "Error: Failed to create $DOCKER_SNAPSHOT_DIR. Exiting."; exit 1; }

docker_volumes_found=0
for VOLUME in $(docker volume ls -q); do
    echo "Backing up Docker volume: $VOLUME..."
    docker run --rm -v "$VOLUME:/data" -v "$DOCKER_SNAPSHOT_DIR:/backup" busybox tar -cf "/backup/docker_volume_${VOLUME}.tar" -C /data . || { echo "Warning: Failed to backup volume $VOLUME. Continuing."; }
    docker_volumes_found=1
done

if [ "$docker_volumes_found" -eq 0 ]; then
    echo "No Docker volumes found to backup."
    rmdir "$DOCKER_SNAPSHOT_DIR" # Remove empty directory
else
    process_backup "$DOCKER_SNAPSHOT_DIR" "docker_volumes_$TIMESTAMP"
    rm -rf "$DOCKER_SNAPSHOT_DIR" # Clean up unencrypted snapshot
fi
echo "Docker volumes backup complete."

### 3. Metadata Backup

echo "--- Starting Metadata Backup ---"
METADATA_SNAPSHOT_DIR="$BACKUP_PATH/metadata_snapshot_$TIMESTAMP"
mkdir -p "$METADATA_SNAPSHOT_DIR" || { echo "Error: Failed to create $METADATA_SNAPSHOT_DIR. Exiting."; exit 1; }
mkdir -p "$METADATA_SNAPSHOT_DIR/network"

echo "Copying package data..."
cp -r /etc/apt/sources.list* "$METADATA_SNAPSHOT_DIR/" || echo "Warning: Failed to copy sources.list."
dpkg --get-selections > "$METADATA_SNAPSHOT_DIR/installed_packages.txt" || echo "Warning: Failed to get dpkg selections."

echo "Copying user data..."
cp /etc/passwd /etc/shadow /etc/group /etc/gshadow "$METADATA_SNAPSHOT_DIR/" || echo "Warning: Failed to copy user data."

echo "Copying network configuration..."
cp /etc/hosts "$METADATA_SNAPSHOT_DIR/network/" || echo "Warning: Failed to copy /etc/hosts."
if command -v nft &> /dev/null; then
    nft list ruleset > "$METADATA_SNAPSHOT_DIR/network/nft_rules.txt" || echo "Warning: Failed to get nft rules."
fi
if [ -f "/usr/local/sbin/firewall-nft.sh" ]; then
    cp /usr/local/sbin/firewall-nft.sh "$METADATA_SNAPSHOT_DIR/network/" || echo "Warning: Failed to copy firewall-nft.sh."
fi
if command -v netstat &> /dev/null; then
    netstat -rn > "$METADATA_SNAPSHOT_DIR/network/routing_table.txt" || echo "Warning: Failed to get routing table."
fi
if command -v ip &> /dev/null; then
    ip a > "$METADATA_SNAPSHOT_DIR/network/ip_addresses.txt" || echo "Warning: Failed to get IP addresses."
fi

echo "Backing up cron jobs..."
for user in $(cut -f1 -d: /etc/passwd); do
    crontab -l -u "$user" &> "$METADATA_SNAPSHOT_DIR/cron_$user.txt" || true # Ignore errors for users without crontabs
done

process_backup "$METADATA_SNAPSHOT_DIR" "metadata_$TIMESTAMP"
rm -rf "$METADATA_SNAPSHOT_DIR" # Clean up unencrypted snapshot
echo "Metadata backup complete."

### 4. Offsite Sync

echo "--- Starting Offsite Sync ---"
rclone sync "$BACKUP_PATH" "$RCLONE_REMOTE/$TIMESTAMP" --progress --copy-links || { echo "Error: Rclone sync failed. Exiting."; exit 1; }
echo "Offsite sync complete to $RCLONE_REMOTE/$TIMESTAMP."

### 5. Local Cleanup

echo "--- Starting Local Backup Cleanup ---"
find "$BACKUP_DIR" -maxdepth 1 -type d -regex ".*/[0-9]\{8\}_[0-9]\{6\}$" -mtime +7 -exec rm -rf {} \; || { echo "Warning: Cleanup failed. Check permissions."; }
echo "Local cleanup complete."

echo "Backup script finished successfully at $(date)."
