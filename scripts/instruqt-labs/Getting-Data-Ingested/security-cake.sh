#!/bin/bash
# Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

# Define the URL and filename
URL="https://downloads.plex.tv/plex-media-server-new/1.42.1.10060-4e8b05daf/debian/plexmediaserver_1.42.1.10060-4e8b05daf_amd64.deb"
FILE="plexmediaserver_1.42.1.10060-4e8b05daf_amd64.deb"

# Download the file
wget "$URL" -O "$FILE"

# Install the package
sudo dpkg -i "$FILE"
