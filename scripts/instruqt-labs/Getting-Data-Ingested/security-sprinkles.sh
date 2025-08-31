#!/bin/bash
# Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

# Kick off Elastic Rule Loading
echo "Loading Elastic Rules"
curl -X PUT "http://localhost:30001/api/detection_engine/rules/prepackaged" -u "elastic:changme"  --header "kbn-xsrf: true" -H "Content-Type: application/json"  -d '{}'
curl -X POST "http://localhost:30001/api/detection_engine/rules/_bulk_create" -u "elastic:changeme" --header "kbn-xsrf: true" -H "Content-Type: application/json" -d @/root/simple-data-generator/detection-rules/getting-data-ingested-security-sprinkles.json
echo
echo
echo "Security sprinkles applied, Bon Appétit!!!"
echo 
echo


