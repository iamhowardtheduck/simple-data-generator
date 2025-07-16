#!/bin/bash
set -e  # Exit on any error

# Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

echo "[1/4] Running osquery-setup.sh..."
bash simple-data-generator/scripts/instruqt-labs/Getting-Data-Ingested/osquery-setup.sh
echo "[1/4] Completed osquery-setup.sh."

echo "[2/4] Running mysql-docker-deploy.sh..."
bash simple-data-generator/scripts/instruqt-labs/Getting-Data-Ingested/mysql-docker-deploy.sh
echo "[2/4] Completed mysql-docker-deploy.sh."

echo "[3/4] Running install-fim-chaos.sh..."
bash simple-data-generator/scripts/instruqt-labs/Getting-Data-Ingested/install-fim-chaos.sh
echo "[3/4] Completed install-fim-chaos.sh."

echo "[4/4] Running update /etc/hosts"
bash simple-data-generator/scripts/instruqt-labs/Getting-Data-Ingested/update-etc_hosts.sh
echo "[4/4] Completed install update-etc_hosts.sh"

echo "✅ All scripts completed successfully."
