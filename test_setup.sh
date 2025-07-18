#!/bin/bash
set -euo pipefail # Exit on error, unset variables, pipefail

# --- Test Script Configuration ---
# Path to your run_setup.sh script
RUN_SETUP_SCRIPT="./run_setup.sh"

# Number of stacks to deploy for testing
NUM_STACKS=3

# Base name for the application (matches DEFAULT_APP_BASE_NAME in run_setup.sh)
BASE_APP_NAME="wpmon"

# The branch to use for cloning the repository
TARGET_BRANCH="dev" # <-- Added this line

# --- Main Test Execution ---
echo "=================================================="
echo " Starting Automated Multi-Stack Deployment Test "
echo "=================================================="
echo "This script will deploy ${NUM_STACKS} instances of your application."
echo "Each instance will have an incrementing name (e.g., ${BASE_APP_NAME}_1, ${BASE_APP_NAME}_2) "
echo "and its ports will be offset by an incrementing number."
echo "All deployments will use the '${TARGET_BRANCH}' branch." # <-- Updated message
echo ""
read -p "Press Enter to begin deployment of ${NUM_STACKS} stacks..."

# Loop to deploy each stack
for i in $(seq 1 $NUM_STACKS); do
    echo ""
    echo "--------------------------------------------------"
    echo " Deploying Stack ${i} of ${NUM_STACKS} "
    echo "--------------------------------------------------"
    
    # Calculate suffix and offset for the current stack
    # -n: appends _<i> to the app name (e.g., wpmon_1, wpmon_2)
    # -o: adds <i> to all default port numbers (e.g., 80->81, 443->444 for stack 1)
    # -b: specifies the Git branch (now fixed to 'dev')
    
    # Execute the run_setup.sh script with the appropriate flags
    # We use 'sudo' because run_setup.sh requires root privileges
    sudo "$RUN_SETUP_SCRIPT" -b "$TARGET_BRANCH" -n "$i" -o "$i" || { # <-- Added -b flag
        echo "ERROR: Deployment of stack ${i} failed. Aborting test." >&2
        exit 1
    }
    
    echo "Stack ${i} deployment completed successfully."
done

echo ""
echo "=================================================="
echo " All ${NUM_STACKS} Stacks Deployed Successfully! "
echo "=================================================="
echo ""

# --- Cleanup Instructions ---
echo "--- Cleanup Instructions ---"
echo "To clean up these test stacks, you will need to perform the following steps for each stack:"
echo "1. Stop and remove Docker services and volumes using the reset script:"
for i in $(seq 1 $NUM_STACKS); do
    echo "   sudo /opt/${BASE_APP_NAME}_${i}/reset.sh"
done
echo ""
echo "2. Remove the application directories from /opt:"
for i in $(seq 1 $NUM_STACKS); do
    echo "   sudo rm -rf /opt/${BASE_APP_NAME}_${i}"
done
echo ""
echo "Please run these commands carefully after you have finished testing."
echo "Note: This script does NOT clean up Docker itself or other system-wide prerequisites."
echo "=================================================="
