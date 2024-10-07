#!/bin/bash

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

# Prompt the user to select services as before
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

# Mapping the user's choices to service names
declare -A services_map
services_map[1]="autoscan"
services_map[2]="petio"
services_map[3]="plex"
services_map[4]="prowlarr"
services_map[5]="radarr"
services_map[6]="radarr-4k"
services_map[7]="radarr-anime"
services_map[8]="sonarr"
services_map[9]="sonarr-4k"
services_map[10]="sonarr-anime"
services_map[11]="recyclarr"

# Function to append selected services to docker-compose.yml
append_service_to_docker_compose() {
  local service_name=$1
  case $service_name in
    autoscan)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  autoscan:
    image: hotio/autoscan
    container_name: autoscan
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/autoscan:/config
      - /mnt:/mnt
EOL
    ;;
    petio)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  petio:
    image: petio/petio
    container_name: petio
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/petio:/config
EOL
    ;;
    plex)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  plex:
    image: plexinc/pms-docker
    container_name: plex
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/plex:/config
      - /mnt/plex:/plex
EOL
    ;;
    prowlarr)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  prowlarr:
    image: linuxserver/prowlarr
    container_name: prowlarr
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/prowlarr:/config
      - /mnt:/mnt
EOL
    ;;
    radarr)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  radarr:
    image: linuxserver/radarr
    container_name: radarr
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/radarr:/config
      - /mnt:/mnt
EOL
    ;;
    radarr-4k)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  radarr-4k:
    image: linuxserver/radarr
    container_name: radarr-4k
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/radarr4k:/config
      - /mnt:/mnt
    environment:
      - RADARR_INSTANCE=4k
EOL
    ;;
    radarr-anime)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  radarr-anime:
    image: linuxserver/radarr
    container_name: radarr-anime
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/radarr-anime:/config
      - /mnt:/mnt
    environment:
      - RADARR_INSTANCE=anime
EOL
    ;;
    sonarr)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  sonarr:
    image: linuxserver/sonarr
    container_name: sonarr
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/sonarr:/config
      - /mnt:/mnt
EOL
    ;;
    sonarr-4k)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  sonarr-4k:
    image: linuxserver/sonarr
    container_name: sonarr-4k
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/sonarr4k:/config
      - /mnt:/mnt
    environment:
      - SONARR_INSTANCE=4k
EOL
    ;;
    sonarr-anime)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  sonarr-anime:
    image: linuxserver/sonarr
    container_name: sonarr-anime
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/sonarr-anime:/config
      - /mnt:/mnt
    environment:
      - SONARR_INSTANCE=anime
EOL
    ;;
    recyclarr)
      tee -a /opt/docker-compose.yml > /dev/null <<EOL
  recyclarr:
    image: hotio/recyclarr
    container_name: recyclarr
    environment:
      - PUID=$PUID
      - PGID=$GUID
      - TZ=Etc/UTC
    volumes:
      - $APP_DATA_DIRECTORY/recyclarr:/config
      - /mnt:/mnt
EOL
    ;;
  esac
}

# Process the user's selected choices
for choice in $CHOICES; do
  service_name=${services_map[$choice]}
  append_service_to_docker_compose "$service_name"
done

# Finalizing the docker-compose.yml file
tee -a /opt/docker-compose.yml > /dev/null <<EOL
networks:
  default:
    driver: bridge
EOL

# Final ownership changes if needed
chown -R $PUID:$GUID $APP_DATA_DIRECTORY
chown -R $PUID:$GUID /mnt

echo "Starting the selected services using docker-compose..."
cd /opt
docker-compose up -d

echo "Containers have been started. The setup is complete."
echo "Please remember to configure Plex, all Sonarrs, and Radarrs, then set up Black Hole if desired."
