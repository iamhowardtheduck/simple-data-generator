#!/bin/bash


# Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

# Install nano via snap
#sudo snap install nano --classic
#export USER=$(whoami)

# Kick off osquery-setup.sh
bash simple-data-generator/scripts/instruqt-labs/Getting-Data-Ingested/osquery-setup.sh

# Kick off mysql-docker-deploy.sh
bash simple-data-generator/scripts/instruqt-labs/Getting-Data-Ingested/mysql-docker-deploy.sh

# Kick off install-fim-chaos.sh
bash simple-data-generator/scripts/instruqt-labs/Getting-Data-Ingested/install-fim-chaos.sh
