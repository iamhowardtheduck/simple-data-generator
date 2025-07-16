#!/bin/bash
set -e

# Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

# DPKG lock wait function
wait_for_dpkg_lock() {
  local max_attempts=30
  local attempt=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    pid=$(fuser /var/lib/dpkg/lock-frontend 2>/dev/null)
    echo "Waiting for dpkg lock to be released (held by PID $pid)..."
    attempt=$((attempt+1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "Lock held too long. Killing PID $pid..."
      kill -9 "$pid"
      break
    fi
    sleep 2
  done
}

export DEBIAN_FRONTEND=noninteractive

wait_for_dpkg_lock
apt-get update

wait_for_dpkg_lock
apt-get install -y curl gnupg lsb-release wget software-properties-common jq gdebi-core -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Download and install osquery 5.18.1 from official source
OSQUERY_DEB_URL="https://pkg.osquery.io/deb/osquery_5.18.1-1.linux_amd64.deb"
TMP_DEB="/tmp/osquery.deb"

echo "Downloading osquery 5.18.1..."
curl -fsSL "$OSQUERY_DEB_URL" -o "$TMP_DEB"

wait_for_dpkg_lock
gdebi -n "$TMP_DEB"
rm -f "$TMP_DEB"

# Create configuration directory
mkdir -p /etc/osquery
CONFIG_FILE="/etc/osquery/osquery.conf"
PACKS_DIR="/etc/osquery/packs"

# Download config and packs from 5.18.1 tag
curl -fsSL https://raw.githubusercontent.com/osquery/osquery/5.18.1/tools/deployment/osquery.example.conf -o "$CONFIG_FILE"

mkdir -p "$PACKS_DIR"
curl -sL https://github.com/osquery/osquery/archive/refs/tags/5.18.1.tar.gz | \
  tar -xz --strip-components=2 -C "$PACKS_DIR" osquery-5.18.1/packs

# Inject all packs into config
PACKS_JSON=$(jq -n '{packs: {} }')
for pack_file in "$PACKS_DIR"/*.conf; do
  pack_name=$(basename "$pack_file" .conf)
  PACKS_JSON=$(echo "$PACKS_JSON" | jq --arg name "$pack_name" --arg path "$pack_file" '.packs[$name] = $path')
done

jq --argjson packs "$(echo "$PACKS_JSON" | jq '.packs')" '. + {packs: $packs}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

# Start osquery service
systemctl daemon-reexec
systemctl enable osqueryd
systemctl restart osqueryd

echo "✅ Osquery 5.18.1 installed and fully configured with default packs."
