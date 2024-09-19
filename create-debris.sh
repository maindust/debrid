#!/bin/bash

# Function to prompt user for Real-Debrid API token
read -sp "Please enter your Real-Debrid API token: " RD_API_TOKEN
echo ""

# Update and upgrade the system
echo "Updating and upgrading the system..."
sudo apt update && sudo apt upgrade -y

# Create necessary directories
echo "Creating directory structure under /mnt..."
sudo mkdir -p /mnt/symlinks/radarr /mnt/symlinks/sonarr /mnt/symlinks/radarr4k /mnt/symlinks/sonarr4k /mnt/symlinks/radarranime /mnt/symlinks/sonarranime
sudo mkdir -p /mnt/plex/Movies /mnt/plex/TV /mnt/plex/"Movies - 4K" /mnt/plex/"TV - 4K" /mnt/plex/anime

echo "Creating /opt/zurg-testing directory..."
sudo mkdir -p /opt/zurg-testing

# Store the API token in an .env file for persistent use
echo "Storing Real-Debrid API token in /opt/zurg-testing/.env..."
sudo tee /opt/zurg-testing/.env > /dev/null <<EOL
REAL_DEBRID_API_TOKEN=$RD_API_TOKEN
EOL

# Create the config.yml file for Zurg, using the environment variable from the .env file
echo "Creating config.yml in /opt/zurg-testing..."
sudo tee /opt/zurg-testing/config.yml > /dev/null <<EOL
# Zurg configuration version
zurg: v1
token: \${REAL_DEBRID_API_TOKEN} # Using environment variable from .env file
# host: "[::]"
# port: 9999
# username:
# password:
# proxy:
api_rate_limit_per_minute: 60
torrents_rate_limit_per_minute: 25
concurrent_workers: 32
check_for_changes_every_secs: 10
# repair_every_mins: 60
ignore_renames: true
retain_rd_torrent_name: true
retain_folder_name_extension: true
enable_repair: false
auto_delete_rar_torrents: false
get_torrents_count: 5000
# api_timeout_secs: 15
# download_timeout_secs: 10
# enable_download_mount: false
# rate_limit_sleep_secs: 6
# retries_until_failed: 2
# network_buffer_size: 4194304 # 4MB
serve_from_rclone: true
# verify_download_link: false
# force_ipv6: false
directories:
  torrents:
    group: 1
    filters:
      - regex: /.*/
EOL

# Create the rclone.conf file for Zurg
echo "Creating rclone.conf in /opt/zurg-testing..."
sudo tee /opt/zurg-testing/rclone.conf > /dev/null <<EOL
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
EOL

# Create the docker-compose.yml file for Zurg and Rclone, referencing the .env file for token
echo "Creating docker-compose.yml in /opt/zurg-testing..."
sudo tee /opt/zurg-testing/docker-compose.yml > /dev/null <<EOL
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
    env_file:
      - .env

  rclone:
    image: rclone/rclone:latest
    container_name: rclone
    restart: unless-stopped
    environment:
      TZ=UTC
      PUID=1000
      PGID=1000
    volumes:
      - /mnt/remote/realdebrid:/data:rshared
      - /opt/zurg-testing/rclone.conf:/config/rclone/rclone.conf
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
    command: "mount zurg: /data --allow-non-empty --allow-other --uid=1000 --gid=1000 --umask=002 --dir-cache-time 10s"
EOL

# Create necessary directories under /opt
echo "Creating necessary directories under /opt..."
sudo mkdir -p /opt/autoscan /opt/petio /opt/petio/mongodb/config /opt/plex /opt/prowlarr /opt/radarr /opt/radarr4k /opt/radarranime /opt/scripts /opt/sonarr /opt/sonarr4k /opt/sonarranime /opt/recyclarr

# Navigate to /opt and create another docker-compose.yml file with the new services configuration
echo "Creating another docker-compose.yml in /opt..."
sudo tee /opt/docker-compose.yml > /dev/null <<EOL
version: '3.8'
services:
  autoscan:
    container_name: autoscan
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    ports:
      - 3030/tcp
    hostname: autoscan
    image: saltydk/autoscan:latest
    restart: unless-stopped
    volumes:
      - /mnt:/mnt
      - /opt/autoscan:/config
    depends_on:
      - rclone
      - plex
      - radarr
      - sonarr

  petio:
    command:
      - node
      - petio.js
    container_name: petio
    ports:
      - 7777/tcp
    hostname: petio
    image: ghcr.io/petio-team/petio:latest
    restart: unless-stopped
    user: 1000:1000
    environment:
      - TZ=UTC
    volumes:
      - /mnt:/mnt
      - /opt/petio:/app/api/config
    working_dir: /app
    depends_on:
      - radarr
      - sonarr
      - plex

  petio-mongo:
    command:
      - mongod
    container_name: petio-mongo
    ports:
      - 27017/tcp
    hostname: petio-mongo
    image: mongo:4.4
    restart: unless-stopped
    user: 1000:1000
    environment:
      - TZ=UTC
    volumes:
      - /mnt:/mnt
      - /opt/petio/mongodb/config:/data/configdb
      - /opt/petio/mongodb:/data/db

  plex:
    container_name: plex
    devices:
      - /dev/dri:/dev/dri
    environment:
      - PLEX_UID=1000
      - PLEX_GID=1000
      - TZ=UTC
    ports:
      - 1900/udp
      - 32400/tcp
      - 32410/udp
      - 32412/udp
      - 32413/udp
      - 32414/udp
      - 32469/tcp
      - 8324/tcp
    hostname: plex
    image: plexinc/pms-docker:latest
    restart: unless-stopped
    volumes:
      - /dev/shm:/dev/shm
      - /mnt/local/transcodes/plex:/transcode
      - /mnt:/mnt
      - /opt/plex:/config
      - /opt/scripts:/scripts
    depends_on:
      - rclone

  prowlarr:
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    ports:
      - 9696/tcp
    hostname: prowlarr
    image: ghcr.io/hotio/prowlarr:release
    restart: unless-stopped
    volumes:
      - /mnt:/mnt
      - /opt/prowlarr/Definitions/Custom:/Custom
      - /opt/prowlarr:/config

  radarr:
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    ports:
      - 7878/tcp
    hostname: radarr
    image: ghcr.io/hotio/radarr:release
    restart: unless-stopped
    volumes:
      - /mnt:/mnt
      - /opt/radarr:/config
      - /opt/scripts:/scripts
      - /usr/bin/rclone:/usr/bin/rclone
    depends_on:
      - rclone

  radarr4k:
    container_name: radarr4k
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    ports:
      - 7878/tcp
    hostname: radarr4k
    image: ghcr.io/hotio/radarr:release
    restart: unless-stopped
    volumes:
      - /mnt:/mnt
      - /opt/radarr4k:/config
      - /opt/scripts:/scripts
      - /usr/bin/rclone:/usr/bin/rclone
    depends_on:
      - rclone

  radarranime:
    container_name: radarranime
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    ports:
      - 7878/tcp
    hostname: radarranime
    image: ghcr.io/hotio/radarr:release
    restart: unless-stopped
    volumes:
      - /mnt:/mnt
      - /opt/radarranime:/config
      - /opt/scripts:/scripts
      - /usr/bin/rclone:/usr/bin/rclone
    depends_on:
      - rclone

  sonarr:
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    ports:
      - 8989/tcp
    hostname: sonarr
    image: ghcr.io/hotio/sonarr:release
    restart: unless-stopped
    volumes:
      - /mnt:/mnt
      - /opt/scripts:/scripts
      - /opt/sonarr:/config
      - /usr/bin/rclone:/usr/bin/rclone
    depends_on:
      - rclone

  sonarr4k:
    container_name: sonarr4k
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    ports:
      - 8989/tcp
    hostname: sonarr4k
    image: ghcr.io/hotio/sonarr:release
    restart: unless-stopped
    volumes:
      - /mnt:/mnt
      - /opt/scripts:/scripts
      - /opt/sonarr4k:/config
      - /usr/bin/rclone:/usr/bin/rclone
    depends_on:
      - rclone

  sonarranime:
    container_name: sonarranime
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    ports:
      - 8989/tcp
    hostname: sonarranime
    image: ghcr.io/hotio/sonarr:release
    restart: unless-stopped
    volumes:
      - /mnt:/mnt
      - /opt/scripts:/scripts
      - /opt/sonarranime:/config
      - /usr/bin/rclone:/usr/bin/rclone
    depends_on:
      - rclone

  recyclarr:
    container_name: recyclarr
    image: ghcr.io/recyclarr/recyclarr
    user: 1000:1000
    environment:
      - TZ=UTC
    volumes:
      - /opt/recyclarr:/config
EOL

# Navigate to /opt/zurg-testing and start the containers
cd /opt/zurg-testing
echo "Starting Zurg and Rclone containers..."
sudo docker-compose up -d

# Navigate to /opt and start the newly created services
cd /opt
echo "Starting services defined in /opt/docker-compose.yml..."
sudo docker-compose up -d

echo "Containers have been started. The setup is complete."
echo "Please remember to configure Plex, all Sonarrs, and Radarrs, then set up Black Hole if desired."
