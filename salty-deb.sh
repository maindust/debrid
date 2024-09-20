#!/bin/bash

# Step 0: Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please switch to root and run the script again."
    exit 1
fi

# Function to prompt user for input with default option
prompt_optional() {
    read -rp "$1 (Optional, press Enter to skip): " input
    echo "$input"
}

# Function to prompt user for input (required)
prompt_required() {
    while true; do
        read -rp "$1 (Required): " input
        if [[ -n "$input" ]]; then
            echo "$input"
            break
        else
            echo "This field is required."
        fi
    done
}

# Step 1: Install Saltbox
curl -sL https://install.saltbox.dev | bash

# Step 2: Navigate to the Saltbox directory
cd /srv/git/saltbox || { echo "Failed to navigate to /srv/git/saltbox"; exit 1; }

# Step 3: Prompt user to modify the existing accounts.yml file
echo "Modifying accounts.yml..."

# Step 4: Prompt user for optional inputs for accounts.yml
apprise=$(prompt_optional "Enter apprise details")
cloudflare_email=$(prompt_optional "Enter Cloudflare email")
cloudflare_api=$(prompt_optional "Enter Cloudflare API key")
dockerhub_user=$(prompt_optional "Enter DockerHub username")
dockerhub_token=$(prompt_optional "Enter DockerHub token")

# Step 5: Prompt user for required inputs for accounts.yml
user_name=$(prompt_required "Enter username for user:")
user_pass=$(prompt_required "Enter password for user:")
user_domain=$(prompt_required "Enter domain for user:")
user_email=$(prompt_required "Enter email for user:")
ssh_key=$(prompt_optional "Enter SSH key")

# Step 6: Modify the accounts.yml file with the input values
sed -i "s|apprise:.*|apprise: $apprise|" accounts.yml
sed -i "s|cloudflare:\n  email:.*|cloudflare:\n  email: $cloudflare_email\n  api: $cloudflare_api|" accounts.yml
sed -i "s|dockerhub:\n  user:.*|dockerhub:\n  user: $dockerhub_user\n  token: $dockerhub_token|" accounts.yml
sed -i "s|user:\n  name:.*|user:\n  name: $user_name\n  pass: $user_pass\n  domain: $user_domain\n  email: $user_email\n  ssh_key: $ssh_key|" accounts.yml

# Inform the user that accounts.yml has been updated
echo "accounts.yml has been modified with your input."

# Step 7: Prompt user to modify the existing settings.yml file
echo "Modifying settings.yml..."

# Step 8: Modify the settings.yml file to disable rclone and remove remotes
sed -i "s|enabled: yes|enabled: no|" settings.yml
sed -i "s|remotes:.*|remotes: []|" settings.yml

# Inform the user that settings.yml has been updated
echo "settings.yml has been modified to disable rclone and remove remotes."

# Step 9: Run sb install preinstall after modifications
echo "Running 'sb install preinstall'..."
sb install preinstall

# Inform the user that the preinstall step has been executed
echo "'sb install preinstall' has been successfully executed."

# Step 10: Switch to the user from accounts.yml
echo "Switching to user: $user_name..."
su - "$user_name"

# Inform the user that the switch to the specified user has been made
echo "Switched to user: $user_name."

# =================== Environment Setup and Directory Creation ===================

# Function to prompt user for necessary environment variables and create the .env file
create_env_file() {
  echo "Please provide the following information:"
  
  # Prompt user for Real-Debrid API Key
  read -p "Real-Debrid API Key: " RD_API_KEY
  
  # Prompt user for PUID (Process User ID)
  read -p "PUID (e.g., 1000): " PUID
  
  # Prompt user for GUID (Group User ID)
  read -p "GUID (e.g., 1000): " GUID
  
  # Prompt user for RD mount path
  read -p "Real-Debrid Mount Path (e.g., /mnt/remote/realdebrid): " RD_MOUNT_PATH
  
  # Prompt user for application data directory
  read -p "Application Data Directory (e.g., /opt): " APP_DATA_DIRECTORY
  
  # Create the .env file with the provided values
  echo "Creating .env file..."
  tee .env > /dev/null <<EOL
RD_API_KEY=$RD_API_KEY
PUID=$PUID
GUID=$GUID
RD_MOUNT_PATH=$RD_MOUNT_PATH
APP_DATA_DIRECTORY=$APP_DATA_DIRECTORY
EOL

  echo ".env file has been created."
}

# Function to load the environment variables from the .env file
load_env_file() {
  if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
  else
    echo "Error: .env file not found!"
    exit 1
  fi
}

# Create the .env file by prompting the user for input
create_env_file

# Load environment variables from the newly created .env file
load_env_file

# Ensure necessary variables are set in the .env file
if [ -z "$RD_API_KEY" ] || [ -z "$PUID" ] || [ -z "$GUID" ] || [ -z "$RD_MOUNT_PATH" ] || [ -z "$APP_DATA_DIRECTORY" ]; then
  echo "Error: Please ensure all required variables are set in the .env file."
  exit 1
fi

# Update and upgrade the system
echo "Updating and upgrading the system..."
apt update && apt upgrade -y

# Create necessary directories
echo "Creating necessary directory structure..."
mkdir -p $APP_DATA_DIRECTORY/zurg-testing $RD_MOUNT_PATH
mkdir -p /mnt/symlinks/radarr /mnt/symlinks/sonarr /mnt/symlinks/radarr4k /mnt/symlinks/sonarr4k
mkdir -p /mnt/plex/Movies /mnt/plex/TV /mnt/plex/"Movies - 4K" /mnt/plex/"TV - 4K"

# Change ownership of the directories to the specified PUID and GUID
echo "Changing ownership of directories to PUID:$PUID and GUID:$GUID..."
chown -R $PUID:$GUID $APP_DATA_DIRECTORY
chown -R $PUID:$GUID /mnt

# Create the config.yml file with the Real-Debrid API token
echo "Creating config.yml in $APP_DATA_DIRECTORY/zurg-testing..."
tee $APP_DATA_DIRECTORY/zurg-testing/config.yml > /dev/null <<EOL
# Zurg configuration version
zurg: v1
token: $RD_API_KEY # Injected Real-Debrid API token
api_rate_limit_per_minute: 60
torrents_rate_limit_per_minute: 25
concurrent_workers: 32
check_for_changes_every_secs: 10
ignore_renames: true
retain_rd_torrent_name: true
retain_folder_name_extension: true
enable_repair: false
auto_delete_rar_torrents: false
get_torrents_count: 5000
serve_from_rclone: true
directories:
  torrents:
    group: 1
    filters:
      - regex: /.*/
EOL

# Create the rclone.conf file for Zurg
echo "Creating rclone.conf in $APP_DATA_DIRECTORY/zurg-testing..."
tee $APP_DATA_DIRECTORY/zurg-testing/rclone.conf > /dev/null <<EOL
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
EOL

# Create the docker-compose.yml file for Zurg and Rclone
echo "Creating docker-compose.yml in $APP_DATA_DIRECTORY/zurg-testing..."
tee $APP_DATA_DIRECTORY/zurg-testing/docker-compose.yml > /dev/null <<EOL
version: '3.8'
services:
  zurg:
    image: ghcr.io/debridmediamanager/zurg-testing:v0.9.3-final
    container_name: zurg
    restart: unless-stopped
    healthcheck:
      test: curl -f localhost:9999/dav/version.txt || exit 1
    ports:
      - 9999:9999
    volumes:
      - ./config.yml:/app/config.yml
      - ./data:/app/data
    environment:
      - REAL_DEBRID_API_TOKEN=$RD_API_KEY

  rclone:
    image: rclone/rclone:latest
    container_name: rclone
    restart: unless-stopped
    environment:
      TZ=UTC
      PUID=$PUID
      PGID=$GUID
    volumes:
      - $RD_MOUNT_PATH:/data:rshared
      - $APP_DATA_DIRECTORY/zurg-testing/rclone.conf:/config/rclone/rclone.conf
      - /mnt:/mnt
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse:rwm
    depends_on:
      zurg:
        condition: service_healthy
        restart: true
    command: "mount zurg: /data --allow-non-empty --allow-other --uid=$PUID --gid=$GUID --umask=002 --dir-cache-time 10s"
EOL

# Run sb install mediabox
echo "Running 'sb install mediabox'..."
sb install mediabox

echo "All necessary files and directories have been created successfully."

# Reboot the server
echo "Rebooting the server..."
reboot
