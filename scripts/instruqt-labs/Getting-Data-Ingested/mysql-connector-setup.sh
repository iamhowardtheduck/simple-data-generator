#!/bin/bash

# Confirmation loop for Connector ID and API Key
while true; do
    read -rp "Enter Connector ID: " connId
    read -rp "Enter API Key: " apiKey

    echo
    echo "You entered:"
    echo "  Connector ID: $connId"
    echo "  API Key:      $apiKey"
    read -rp "Are these correct? [y/n]: " confirm

    case "$confirm" in
        [Yy]* ) break;;
        * ) echo "Let's try again."; echo;;
    esac
done

# Set config file path
CONFIG_FILE="$HOME/root/config-mysql.yml"

# Make sure the directory exists
mkdir -p "$HOME/root"

# Generate the YAML config file
cat > "$CONFIG_FILE" <<EOF
connectors:
- connector_id: "$connId"
  service_type: "mysql"
  api_key: "$apiKey"

elasticsearch:
  host: "http://elasticsearch-es-http.default.svc:9200"
  api_key: "$apiKey"
EOF

echo -e "\nGenerated $CONFIG_FILE:"
cat "$CONFIG_FILE"

# Find the ens4 IP address
ens4_ip=$(ip -4 -o addr show ens4 | awk '{print $4}' | cut -d/ -f1)

if [ -n "$ens4_ip" ]; then
    echo -e "\n---"
    echo "The IP address for ens4 is: $ens4_ip"
    echo "Copy and paste as needed."
    # Optionally: copy to clipboard if xclip is installed
    if command -v xclip >/dev/null 2>&1; then
        echo -n "$ens4_ip" | xclip -selection clipboard
        echo "(The IP address has also been copied to your clipboard!)"
    fi
    echo "---"
else
    echo "Could not determine the IP address for interface ens4."
fi

# Create the docker network 'elastic' if it does not exist
if ! sudo docker network ls | grep -q 'elastic'; then
    echo "Docker network 'elastic' does not exist. Creating..."
    sudo docker network create elastic
else
    echo "Docker network 'elastic' already exists."
fi

# Run the Docker container
sudo docker run -d --restart=always --name mysql-sales \
  -v ~/root:/config \
  --network "elastic" \
  --tty docker.elastic.co/enterprise-search/elastic-connectors:8.18.3 \
  /app/bin/elastic-ingest -c /config/config-mysql.yml

# Print summary for the student
echo -e "\n=================================================================="
echo "Summary of what this script did:"
echo
echo "1. Collected your Connector ID and API Key, and generated a configuration file at:"
echo "   $CONFIG_FILE"
echo
echo "2. Displayed your 'ens4' network interface IP address for easy reference."
echo
echo "3. Checked if the Docker network 'elastic' exists, and created it if needed."
echo
echo "4. Started the Elastic Connector Docker container named 'mysql-sales',"
echo "   using the configuration file you just created."
echo
echo "You now have an Elastic Connector running, configured for MySQL, and ready to use."
echo "If you need to connect your MySQL server, use the IP shown above for remote connections."
echo "=================================================================="
