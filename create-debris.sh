#!/bin/bash

# Load environment variables from .env file
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "Error: .env file not found!"
  exit 1
fi

# Ensure necessary variables are set in the .env file
if [ -z "$RD_API_KEY" ] || [ -z "$PUID" ] || [ -z "$GUID" ] || [ -z "$RD_MOUNT_PATH" ] || [ -z "$APP_DATA_DIRECTORY" ]; then
  echo "Error: Please ensure all required variables are set in the .env file."
  exit 1
fi

# Update and upgrade the system (assuming the user runs with root privileges)
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

# Prompt the user to select services as before (same logic as in previous example)
echo "Select the services you would like to install (separate choices with spaces):"
echo "1. Autoscan"
echo "2. Petio"
echo "3. Plex"
echo "4. Prowlarr"
echo "5. Radarr"
echo "6. Radarr 4K"
echo "7. Radarr Anime"
echo "8. Sonarr"
echo "9. Sonarr 4K"
echo "10. Sonarr Anime"
echo "11. Recyclarr"
read -p "Enter your choices (e.g., 1 2 3): " CHOICES

# Start building docker-compose.yml based on selected services
echo "Creating docker-compose.yml based on selected services..."
tee /opt/docker-compose.yml > /dev/null <<EOL
version: '3.8'
services:
EOL

# Append services based on user's choices (same logic as before)

# Final ownership changes if needed
chown -R $PUID:$GUID $APP_DATA_DIRECTORY
chown -R $PUID:$GUID /mnt

echo "Starting the selected services using docker-compose..."
cd /opt
docker-compose up -d

echo "Containers have been started. The setup is complete."
echo "Please remember to configure Plex, all Sonarrs, and Radarrs, then set up Black Hole if desired."
