#!/bin/bash

# Function to get and confirm the enrollment token
get_token() {
    while true; do
        read -rp "Please paste your Elastic Agent enrollment token: " ENROLLMENT_TOKEN
        echo "You entered: $ENROLLMENT_TOKEN"
        read -rp "Is this correct? (yes/no): " CONFIRM
        case "$CONFIRM" in
            [Yy][Ee][Ss]|[Yy]) break ;;
            *) echo "Let's try again." ;;
        esac
    done
}

# Get the enrollment token from user
get_token

# Create the Docker network 'elastic' if it doesn't exist
if ! docker network ls | grep -q ' elastic '; then
    echo "Creating Docker network 'elastic'..."
    docker network create elastic
else
    echo "Docker network 'elastic' already exists."
fi

# Run the Elastic Agent Synthetics container
echo "Starting Elastic-Agent-Synthetics container..."
sudo docker run -d \
    --restart=always \
    --name Elastic-Agent-Synthetics \
    --network elastic \
    --env FLEET_ENROLL=1 \
    --env FLEET_URL=https://fleet-server-agent-http.default.svc:8220 \
    --env FLEET_ENROLLMENT_TOKEN="$ENROLLMENT_TOKEN" \
    --env KIBANA_HOST=https://fleet-server-agent-http.default.svc:30002 \
    --env KIBANA_FLEET_SETUP=1 \
    --env FLEET_INSECURE=true \
    -v /usr/local/share/ca-certificates/ca.crt:/usr/share/elastic-agent/certs/ca.crt:ro \
    docker.elastic.co/elastic-agent/elastic-agent-complete:8.19.3

cat <<EOF

====================================================================
Elastic Agent (Synthetics) Docker Container Installation Complete!
====================================================================

You have just installed the Elastic Agent using the 
'docker.elastic.co/elastic-agent/elastic-agent-complete:8.18.1' image.

✅ This version supports **synthetic browser monitoring** directly from your host.

🔧 What this script did:
- Prompted you for the **Fleet enrollment token**, which securely connects the agent to Kibana and Fleet.
- Ensured the **Docker network 'elastic'** exists so the container can communicate with other services like Fleet Server.
- Started the container with:
  - **Automatic restart** on failure or system reboot
  - **TLS support** via a mounted certificate at \`/usr/share/elastic-agent/certs/ca.crt\`
  - **Fleet Server URL**: https://fleet-server-agent-http.default.svc:8220
  - **Kibana URL**: https://fleet-server-agent-http.default.svc:30002
  - \`FLEET_INSECURE=true\` to allow enrollment with a self-signed cert

🔎 To check agent status:
  docker logs -f Elastic-Agent-Synthetics

🧼 To stop and remove the container:
  docker rm -f Elastic-Agent-Synthetics

====================================================================

EOF

# Wait for user confirmation before exiting, but leave the info on screen
read -rp "Press ENTER to finish and leave this information visible on your screen..."
