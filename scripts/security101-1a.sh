# Set up environment variables
echo 'ELASTICSEARCH_USERNAME=elastic' >> /root/.env
#echo -n 'ELASTICSEARCH_PASSWORD=' >> /root/.env
kubectl get secret elasticsearch-es-elastic-user -n default -o go-template='ELASTICSEARCH_PASSWORD={{.data.elastic | base64decode}}' >> /root/.env
echo '' >> /root/.env
echo 'ELASTICSEARCH_URL="http://localhost:30920"' >> /root/.env
echo 'KIBANA_URL="http://localhost:30002"' >> /root/.env
echo 'BUILD_NUMBER="10"' >> /root/.env
echo 'ELASTIC_VERSION="9.1.0"' >> /root/.env
echo 'ELASTIC_APM_SERVER_URL=http://apm.default.svc:8200' >> /root/.env
echo 'ELASTIC_APM_SECRET_TOKEN=pkcQROVMCzYypqXs0b' >> /root/.env

# Set up environment
export $(cat /root/.env | xargs)

BASE64=$(echo -n "elastic:${ELASTICSEARCH_PASSWORD}" | base64)
KIBANA_URL_WITHOUT_PROTOCOL=$(echo $KIBANA_URL | sed -e 's#http[s]\?://##g')

# Add sdg user with superuser role
curl -X POST "http://localhost:30920/_security/user/sdg" -H "Content-Type: application/json" -u "elastic:${ELASTICSEARCH_PASSWORD}" -d '{
  "password" : "changeme",
  "roles" : [ "superuser" ],
  "full_name" : "SDG User",
  "email" : "sdg@elastic-pahlsoft.com"
}'


# Install Git
sudo apt update -y
# Install Java
sudo apt install -y git default-jre

# Verify Java installation
java_version=$(java -version 2>&1 | head -n 1)
echo "Java installed: $java_version"

# Install Gradle
sudo apt install -y gradle

# Verify Gradle installation
gradle_version=$(gradle -v | grep "Gradle " | awk '{print $2}')
echo "Gradle installed: Version $gradle_version"

# Install Simple-Data-Generator
cd /root/simple-data-generator && gradle clean; gradle build fatJar

echo
echo "Simple Data Generator installed"
echo

# Install LLM Connector
bash /opt/workshops/elastic-llm.sh -k false -m anthropic -e true

echo
echo "AI Assistant Connector configured as OpenAI"
echo

# Use Security view
bash /opt/workshops/elastic-view.sh -v classic

# Create enrich index templates
curl -X PUT "http://localhost:30920/_index_template/enrich-windows.sysmon_operational" -H "Content-Type: application/json" -u "sdg:changeme" -d @- << 'EOF'
{
  "template": {
    "settings": {
      "index": {
        "number_of_shards": "1",
        "number_of_replicas": "0"
      }
    },
	"mappings": {
    "properties": {
      "message": {
        "type": "text"
      },
      "wincode": {
        "type": "long"
      },
      "winlog": {
        "properties": {
          "event_id": {
            "type": "keyword"
          }
        }
      }
    }
  }
 },
  "index_patterns": [
    "enrich-windows.sysmon_operational*"
  ],
  "composed_of": [],
  "allow_auto_create": true
}
EOF

curl -X PUT "http://localhost:30920/_index_template/enrich-rip" -H "Content-Type: application/json" -u "sdg:changeme" -d @- << 'EOF'
{
  "template": {
    "settings": {
      "index": {
        "number_of_replicas": "0"
      }
    },
    "mappings": {
      "properties": {
        "ripcodes": {
          "type": "long"
        },
        "rip1": {
          "type": "long"
        }
      }
    }
  },
  "index_patterns": [
    "enrich-rip*"
  ],
  "composed_of": [],
  "ignore_missing_component_templates": [],
  "allow_auto_create": true
}
EOF


curl -X PUT "http://localhost:30920/_index_template/enrich-user_agents" -H "Content-Type: application/json" -u "sdg:changeme" -d @- << 'EOF'
{
  "template": {
    "settings": {
      "index": {
        "number_of_replicas": 0
      }
    },
    "mappings": {
      "properties": {
        "code": {
          "type": "long"
        },
        "user_agent": {
          "type": "object",
          "properties": {
            "os": {
              "type": "object",
              "properties": {
                "full": {
                  "type": "keyword"
                }
              }
            }
          }
        }
      }
    }
  },
  "index_patterns": [
    "enrich-user_agents*"
  ],
  "allow_auto_create": true
}
EOF

# Clear the screen
clear

echo
echo "Enrichment index templates loaded"
echo
sleep 2

# Load enrichment data sources
curl -X POST "http://localhost:30920/enrich-windows.sysmon_operational/_bulk" -H "Content-Type: application/x-ndjson" -u "sdg:changeme" --data-binary @/root/simple-data-generator/enrich-windows.sysmon_operational.ndjson
curl -X POST "http://localhost:30920/enrich-rip/_bulk" -H "Content-Type: application/x-ndjson" -u "sdg:changeme" --data-binary @/root/simple-data-generator/enrich-rip.ndjson
curl -X POST "http://localhost:30920/enrich-user_agents/_bulk" -H "Content-Type: application/x-ndjson" -u "sdg:changeme" --data-binary @/root/simple-data-generator/enrich-user_agents.ndjson

# Clear the screen
clear

echo
echo "Enrichment data sources loaded"
echo
sleep 2

# Create enrichment policies
curl -X PUT "http://localhost:30920/_enrich/policy/enrich-windows.sysmon_operational" -H "Content-Type: application/json" -u "sdg:changeme" -d @- << 'EOF'
{
  "match": {
    "indices": "enrich-windows.sysmon_operational",
    "match_field": "wincode",
    "enrich_fields": ["winlog.event_id", "message"]
  }
}
EOF

curl -X PUT "http://localhost:30920/_enrich/policy/remote-ips" -H "Content-Type: application/json" -u "sdg:changeme" -d @- << 'EOF'
{
  "match": {
    "indices": "enrich-rip",
    "match_field": "ripcodes",
    "enrich_fields": ["rip1"]
  }
}
EOF

curl -X PUT "http://localhost:30920/_enrich/policy/user-agents" -H "Content-Type: application/json" -u "sdg:changeme" -d @- << 'EOF'
{
  "match": {
    "indices": "enrich-user_agents",
    "match_field": "code",
    "enrich_fields": ["user_agent.os.full"]
  }
}
EOF

# Clear the screen
clear

echo
echo "Enrichment policies loaded"
echo
sleep 2

# Execute enrichment policies
curl -X POST "http://localhost:30920/_enrich/policy/enrich-windows.sysmon_operational/_execute" -u "sdg:changeme"
curl -X POST "http://localhost:30920/_enrich/policy/remote-ips/_execute" -u "sdg:changeme"
curl -X POST "http://localhost:30920/_enrich/policy/user-agents/_execute" -u "sdg:changeme"

# Clear the screen
clear

echo
echo "Enrichment policies executed"
echo
sleep 2

# Creat ingest pipelines
curl -X PUT "http://localhost:30920/_ingest/pipeline/logs-windows.sysmon_operational" -H "Content-Type: application/x-ndjson" -u "sdg:changeme" -d @/root/simple-data-generator/logs-windows.sysmon_operational.json
curl -X PUT "http://localhost:30920/_ingest/pipeline/enrich-logs-network_traffic" -H "Content-Type: application/x-ndjson" -u "sdg:changeme" -d @/root/simple-data-generator/enrich-logs-network_traffic.json
curl -X PUT "http://localhost:30920/_ingest/pipeline/enrich-logs-network_traffic-dns" -H "Content-Type: application/x-ndjson" -u "sdg:changeme" -d @/root/simple-data-generator/enrich-logs-network_traffic-dns.json
curl -X PUT "http://localhost:30920/_ingest/pipeline/logs-network_traffic-cleanup" -H "Content-Type: application/x-ndjson" -u "sdg:changeme" -d @/root/simple-data-generator/logs-network_traffic-cleanup.json
curl -X PUT "http://localhost:30920/_ingest/pipeline/timestamp-cleanup" -H "Content-Type: application/x-ndjson" -u "sdg:changeme" -d @/root/simple-data-generator/timestamp-cleanup.json


# Clear the screen
clear

echo
echo "Ingest pipelines loaded"
echo
sleep 2

# Create index templates for data ingestion for tracks
curl -X PUT "http://localhost:30920/_index_template/winlogbeat" -H "Content-Type: application/json" -u "sdg:changeme" -d @- << 'EOF'
{
  "template": {
    "settings": {
      "index": {
        "number_of_replicas": "0",
        "default_pipeline": "logs-windows.sysmon_operational"
      }
    },
    "mappings": {
      "properties": {
        "data_stream": {
          "type": "object",
          "properties": {
            "dataset": {
              "type": "keyword"
            },
            "type": {
              "type": "keyword"
            }
          }
        },
        "event": {
          "type": "object",
          "properties": {
            "category": {
              "type": "keyword"
            },
            "dataset": {
              "type": "keyword"
            },
            "ingested": {
              "type": "date"
            },
            "module": {
              "type": "keyword"
            },
            "type": {
              "type": "keyword"
            }
          }
        },
        "host": {
          "type": "object",
          "properties": {
            "ip": {
              "type": "ip"
            },
            "os": {
              "type": "object",
              "properties": {
                "type": {
                  "type": "keyword"
                }
              }
            }
          }
        },
        "message": {
          "type": "text",
          "index": true,
          "index_options": "positions",
          "eager_global_ordinals": false,
          "index_phrases": false,
          "norms": true,
          "fielddata": false,
          "store": false
        },
        "parent": {
          "type": "object",
          "properties": {
            "process": {
              "type": "object",
              "properties": {
                "name": {
                  "type": "keyword"
                }
              }
            }
          }
        },
        "process": {
          "type": "object",
          "properties": {
            "name": {
              "type": "keyword"
            },
            "parent": {
              "type": "object",
              "properties": {
                "name": {
                  "type": "keyword"
                }
              }
            },
            "pe": {
              "type": "object",
              "properties": {
                "original_file_name": {
                  "type": "keyword"
                }
              }
            },
            "args": {
              "type": "keyword"
            }
          }
        },
        "winlog": {
          "type": "object",
          "properties": {
            "api": {
              "type": "keyword"
            },
            "channel": {
              "type": "keyword"
            },
            "event_id": {
              "type": "keyword"
            },
            "provider_name": {
              "type": "keyword"
            }
          }
        },
        "registry": {
          "type": "object",
          "properties": {
            "path": {
              "type": "keyword"
            }
          }
        }
      }
    }
  },
  "index_patterns": [
    "winlogbeat*",
    "logs-windows.sysmon_operational*"
  ],
  "allow_auto_create": true
}
EOF

curl -X PUT "http://localhost:30920/_component_template/logs-network_traffic.dns@package" -H "Content-Type: application/json" -u "sdg:changeme" -d @- << 'EOF'
{
  "template": {
    "settings": {
      "index": {
        "lifecycle": {
          "name": "logs"
        },
        "mapping": {
          "total_fields": {
            "limit": "1000"
          }
        }
      }
    },
    "mappings": {
      "dynamic_templates": [
        {
          "container.labels": {
            "path_match": "container.labels.*",
            "mapping": {
              "type": "keyword"
            },
            "match_mapping_type": "string"
          }
        },
        {
          "_embedded_ecs-ecs_timestamp": {
            "path_match": "@timestamp",
            "mapping": {
              "ignore_malformed": false,
              "type": "date"
            }
          }
        },
        {
          "_embedded_ecs-data_stream_to_constant": {
            "path_match": "data_stream.*",
            "mapping": {
              "type": "constant_keyword"
            }
          }
        },
        {
          "_embedded_ecs-resolved_ip_to_ip": {
            "mapping": {
              "type": "ip"
            },
            "match": "resolved_ip"
          }
        },
        {
          "_embedded_ecs-forwarded_ip_to_ip": {
            "mapping": {
              "type": "ip"
            },
            "match_mapping_type": "string",
            "match": "forwarded_ip"
          }
        },
        {
          "_embedded_ecs-ip_to_ip": {
            "mapping": {
              "type": "ip"
            },
            "match_mapping_type": "string",
            "match": "ip"
          }
        },
        {
          "_embedded_ecs-x509_public_key_exponent_non_indexed_long": {
            "path_match": "*.x509.public_key_exponent",
            "mapping": {
              "index": false,
              "type": "long",
              "doc_values": false
            }
          }
        },
        {
          "_embedded_ecs-port_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "port"
          }
        },
        {
          "_embedded_ecs-thread_id_to_long": {
            "path_match": "*.thread.id",
            "mapping": {
              "type": "long"
            }
          }
        },
        {
          "_embedded_ecs-status_code_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "status_code"
          }
        },
        {
          "_embedded_ecs-line_to_long": {
            "path_match": "*.file.line",
            "mapping": {
              "type": "long"
            }
          }
        },
        {
          "_embedded_ecs-priority_to_long": {
            "path_match": "log.syslog.priority",
            "mapping": {
              "type": "long"
            }
          }
        },
        {
          "_embedded_ecs-code_to_long": {
            "path_match": "*.facility.code",
            "mapping": {
              "type": "long"
            }
          }
        },
        {
          "_embedded_ecs-bytes_to_long": {
            "mapping": {
              "type": "long"
            },
            "path_unmatch": "*.data.bytes",
            "match": "bytes"
          }
        },
        {
          "_embedded_ecs-packets_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "packets"
          }
        },
        {
          "_embedded_ecs-public_key_exponent_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "public_key_exponent"
          }
        },
        {
          "_embedded_ecs-severity_to_long": {
            "path_match": "event.severity",
            "mapping": {
              "type": "long"
            }
          }
        },
        {
          "_embedded_ecs-duration_to_long": {
            "path_match": "event.duration",
            "mapping": {
              "type": "long"
            }
          }
        },
        {
          "_embedded_ecs-pid_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "pid"
          }
        },
        {
          "_embedded_ecs-uptime_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "uptime"
          }
        },
        {
          "_embedded_ecs-sequence_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "sequence"
          }
        },
        {
          "_embedded_ecs-entropy_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "*entropy"
          }
        },
        {
          "_embedded_ecs-size_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "*size"
          }
        },
        {
          "_embedded_ecs-entrypoint_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "entrypoint"
          }
        },
        {
          "_embedded_ecs-ttl_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "ttl"
          }
        },
        {
          "_embedded_ecs-major_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "major"
          }
        },
        {
          "_embedded_ecs-minor_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "minor"
          }
        },
        {
          "_embedded_ecs-as_number_to_long": {
            "path_match": "*.as.number",
            "mapping": {
              "type": "long"
            }
          }
        },
        {
          "_embedded_ecs-pgid_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "pgid"
          }
        },
        {
          "_embedded_ecs-exit_code_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "exit_code"
          }
        },
        {
          "_embedded_ecs-chi_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "chi2"
          }
        },
        {
          "_embedded_ecs-args_count_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "args_count"
          }
        },
        {
          "_embedded_ecs-virtual_address_to_long": {
            "mapping": {
              "type": "long"
            },
            "match": "virtual_address"
          }
        },
        {
          "_embedded_ecs-io_text_to_wildcard": {
            "path_match": "*.io.text",
            "mapping": {
              "type": "wildcard"
            }
          }
        },
        {
          "_embedded_ecs-strings_to_wildcard": {
            "path_match": "registry.data.strings",
            "mapping": {
              "type": "wildcard"
            }
          }
        },
        {
          "_embedded_ecs-path_to_wildcard": {
            "path_match": "*url.path",
            "mapping": {
              "type": "wildcard"
            }
          }
        },
        {
          "_embedded_ecs-message_id_to_wildcard": {
            "mapping": {
              "type": "wildcard"
            },
            "match": "message_id"
          }
        },
        {
          "_embedded_ecs-command_line_to_multifield": {
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "wildcard"
            },
            "match": "command_line"
          }
        },
        {
          "_embedded_ecs-error_stack_trace_to_multifield": {
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "wildcard"
            },
            "match": "stack_trace"
          }
        },
        {
          "_embedded_ecs-http_content_to_multifield": {
            "path_match": "*.body.content",
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "wildcard"
            }
          }
        },
        {
          "_embedded_ecs-url_full_to_multifield": {
            "path_match": "*.url.full",
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "wildcard"
            }
          }
        },
        {
          "_embedded_ecs-url_original_to_multifield": {
            "path_match": "*.url.original",
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "wildcard"
            }
          }
        },
        {
          "_embedded_ecs-user_agent_original_to_multifield": {
            "path_match": "user_agent.original",
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "wildcard"
            }
          }
        },
        {
          "_embedded_ecs-error_message_to_match_only": {
            "path_match": "error.message",
            "mapping": {
              "type": "match_only_text"
            }
          }
        },
        {
          "_embedded_ecs-message_match_only_text": {
            "path_match": "message",
            "mapping": {
              "type": "match_only_text"
            }
          }
        },
        {
          "_embedded_ecs-event_original_non_indexed_keyword": {
            "path_match": "event.original",
            "mapping": {
              "index": false,
              "type": "keyword",
              "doc_values": false
            }
          }
        },
        {
          "_embedded_ecs-agent_name_to_keyword": {
            "path_match": "agent.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-service_name_to_keyword": {
            "path_match": "*.service.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-sections_name_to_keyword": {
            "path_match": "*.sections.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-resource_name_to_keyword": {
            "path_match": "*.resource.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-observer_name_to_keyword": {
            "path_match": "observer.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-question_name_to_keyword": {
            "path_match": "*.question.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-group_name_to_keyword": {
            "path_match": "*.group.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-geo_name_to_keyword": {
            "path_match": "*.geo.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-host_name_to_keyword": {
            "path_match": "host.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-severity_name_to_keyword": {
            "path_match": "*.severity.name",
            "mapping": {
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-title_to_multifield": {
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "keyword"
            },
            "match": "title"
          }
        },
        {
          "_embedded_ecs-executable_to_multifield": {
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "keyword"
            },
            "match": "executable"
          }
        },
        {
          "_embedded_ecs-file_path_to_multifield": {
            "path_match": "*.file.path",
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-file_target_path_to_multifield": {
            "path_match": "*.file.target_path",
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-name_to_multifield": {
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "keyword"
            },
            "match": "name"
          }
        },
        {
          "_embedded_ecs-full_name_to_multifield": {
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "keyword"
            },
            "match": "full_name"
          }
        },
        {
          "_embedded_ecs-os_full_to_multifield": {
            "path_match": "*.os.full",
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "keyword"
            }
          }
        },
        {
          "_embedded_ecs-working_directory_to_multifield": {
            "mapping": {
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              },
              "type": "keyword"
            },
            "match": "working_directory"
          }
        },
        {
          "_embedded_ecs-timestamp_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "timestamp"
          }
        },
        {
          "_embedded_ecs-delivery_timestamp_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "delivery_timestamp"
          }
        },
        {
          "_embedded_ecs-not_after_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "not_after"
          }
        },
        {
          "_embedded_ecs-not_before_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "not_before"
          }
        },
        {
          "_embedded_ecs-accessed_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "accessed"
          }
        },
        {
          "_embedded_ecs-origination_timestamp_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "origination_timestamp"
          }
        },
        {
          "_embedded_ecs-created_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "created"
          }
        },
        {
          "_embedded_ecs-installed_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "installed"
          }
        },
        {
          "_embedded_ecs-creation_date_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "creation_date"
          }
        },
        {
          "_embedded_ecs-ctime_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "ctime"
          }
        },
        {
          "_embedded_ecs-mtime_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "mtime"
          }
        },
        {
          "_embedded_ecs-ingested_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "ingested"
          }
        },
        {
          "_embedded_ecs-start_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "start"
          }
        },
        {
          "_embedded_ecs-end_to_date": {
            "mapping": {
              "type": "date"
            },
            "match": "end"
          }
        },
        {
          "_embedded_ecs-score_base_to_float": {
            "path_match": "*.score.base",
            "mapping": {
              "type": "float"
            }
          }
        },
        {
          "_embedded_ecs-score_temporal_to_float": {
            "path_match": "*.score.temporal",
            "mapping": {
              "type": "float"
            }
          }
        },
        {
          "_embedded_ecs-score_to_float": {
            "mapping": {
              "type": "float"
            },
            "match": "*_score"
          }
        },
        {
          "_embedded_ecs-score_norm_to_float": {
            "mapping": {
              "type": "float"
            },
            "match": "*_score_norm"
          }
        },
        {
          "_embedded_ecs-usage_to_float": {
            "mapping": {
              "scaling_factor": 1000,
              "type": "scaled_float"
            },
            "match": "usage"
          }
        },
        {
          "_embedded_ecs-location_to_geo_point": {
            "mapping": {
              "type": "geo_point"
            },
            "match": "location"
          }
        },
        {
          "_embedded_ecs-same_as_process_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "same_as_process"
          }
        },
        {
          "_embedded_ecs-established_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "established"
          }
        },
        {
          "_embedded_ecs-resumed_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "resumed"
          }
        },
        {
          "_embedded_ecs-max_bytes_per_process_exceeded_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "max_bytes_per_process_exceeded"
          }
        },
        {
          "_embedded_ecs-interactive_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "interactive"
          }
        },
        {
          "_embedded_ecs-exists_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "exists"
          }
        },
        {
          "_embedded_ecs-trusted_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "trusted"
          }
        },
        {
          "_embedded_ecs-valid_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "valid"
          }
        },
        {
          "_embedded_ecs-go_stripped_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "go_stripped"
          }
        },
        {
          "_embedded_ecs-coldstart_to_boolean": {
            "mapping": {
              "type": "boolean"
            },
            "match": "coldstart"
          }
        },
        {
          "_embedded_ecs-exports_to_flattened": {
            "mapping": {
              "type": "flattened"
            },
            "match": "exports"
          }
        },
        {
          "_embedded_ecs-structured_data_to_flattened": {
            "mapping": {
              "type": "flattened"
            },
            "match": "structured_data"
          }
        },
        {
          "_embedded_ecs-imports_to_flattened": {
            "mapping": {
              "type": "flattened"
            },
            "match": "*imports"
          }
        },
        {
          "_embedded_ecs-attachments_to_nested": {
            "mapping": {
              "type": "nested"
            },
            "match": "attachments"
          }
        },
        {
          "_embedded_ecs-segments_to_nested": {
            "mapping": {
              "type": "nested"
            },
            "match": "segments"
          }
        },
        {
          "_embedded_ecs-elf_sections_to_nested": {
            "path_match": "*.elf.sections",
            "mapping": {
              "type": "nested"
            }
          }
        },
        {
          "_embedded_ecs-pe_sections_to_nested": {
            "path_match": "*.pe.sections",
            "mapping": {
              "type": "nested"
            }
          }
        },
        {
          "_embedded_ecs-macho_sections_to_nested": {
            "path_match": "*.macho.sections",
            "mapping": {
              "type": "nested"
            }
          }
        }
      ],
      "properties": {
        "container": {
          "dynamic": true,
          "type": "object",
          "properties": {
            "image": {
              "properties": {
                "name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "name": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "id": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "labels": {
              "dynamic": true,
              "type": "object"
            }
          }
        },
        "request": {
          "type": "text"
        },
        "server": {
          "properties": {
            "geo": {
              "properties": {
                "continent_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "region_iso_code": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "city_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "country_iso_code": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "country_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "location": {
                  "type": "geo_point"
                },
                "region_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "process": {
              "properties": {
                "args": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "start": {
                  "type": "date"
                },
                "working_directory": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "executable": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "port": {
              "type": "long"
            },
            "bytes": {
              "type": "long"
            },
            "ip": {
              "type": "ip"
            }
          }
        },
        "destination": {
          "properties": {
            "geo": {
              "properties": {
                "continent_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "region_iso_code": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "city_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "country_iso_code": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "country_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "location": {
                  "type": "geo_point"
                },
                "region_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "port": {
              "type": "long"
            },
            "bytes": {
              "type": "long"
            },
            "ip": {
              "type": "ip"
            }
          }
        },
        "network_traffic": {
          "properties": {
            "dns": {
              "properties": {
                "additionals": {
                  "type": "flattened"
                },
                "opt": {
                  "properties": {
                    "ext_rcode": {
                      "ignore_above": 1024,
                      "type": "keyword"
                    },
                    "udp_size": {
                      "type": "long"
                    },
                    "do": {
                      "type": "boolean"
                    },
                    "version": {
                      "ignore_above": 1024,
                      "type": "keyword"
                    }
                  }
                },
                "method": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "question": {
                  "properties": {
                    "etld_plus_one": {
                      "ignore_above": 1024,
                      "type": "keyword"
                    }
                  }
                },
                "resource": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "answers_count": {
                  "type": "long"
                },
                "query": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "authorities_count": {
                  "type": "long"
                },
                "flags": {
                  "properties": {
                    "authoritative": {
                      "type": "boolean"
                    },
                    "truncated_response": {
                      "type": "boolean"
                    },
                    "recursion_available": {
                      "type": "boolean"
                    },
                    "recursion_desired": {
                      "type": "boolean"
                    },
                    "checking_disabled": {
                      "type": "boolean"
                    },
                    "authentic_data": {
                      "type": "boolean"
                    }
                  }
                },
                "additionals_count": {
                  "type": "long"
                },
                "authorities": {
                  "type": "flattened"
                }
              }
            },
            "status": {
              "ignore_above": 1024,
              "type": "keyword"
            }
          }
        },
        "source": {
          "properties": {
            "geo": {
              "properties": {
                "continent_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "region_iso_code": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "city_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "country_iso_code": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "country_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "location": {
                  "type": "geo_point"
                },
                "region_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "port": {
              "type": "long"
            },
            "bytes": {
              "type": "long"
            },
            "ip": {
              "type": "ip"
            }
          }
        },
        "type": {
          "ignore_above": 1024,
          "type": "keyword"
        },
        "network": {
          "properties": {
            "community_id": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "forwarded_ip": {
              "type": "ip"
            },
            "protocol": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "bytes": {
              "type": "long"
            },
            "transport": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "type": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "direction": {
              "ignore_above": 1024,
              "type": "keyword"
            }
          }
        },
        "cloud": {
          "properties": {
            "availability_zone": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "image": {
              "properties": {
                "id": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "instance": {
              "properties": {
                "name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "id": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "provider": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "machine": {
              "properties": {
                "type": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "project": {
              "properties": {
                "id": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "region": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "account": {
              "properties": {
                "id": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            }
          }
        },
        "path": {
          "ignore_above": 1024,
          "type": "keyword"
        },
        "observer": {
          "properties": {
            "hostname": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "ip": {
              "type": "ip"
            },
            "name": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "mac": {
              "ignore_above": 1024,
              "type": "keyword"
            }
          }
        },
        "ecs": {
          "properties": {
            "version": {
              "ignore_above": 1024,
              "type": "keyword"
            }
          }
        },
        "related": {
          "properties": {
            "hosts": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "ip": {
              "type": "ip"
            }
          }
        },
        "host": {
          "properties": {
            "hostname": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "os": {
              "properties": {
                "build": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "kernel": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "codename": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "name": {
                  "ignore_above": 1024,
                  "type": "keyword",
                  "fields": {
                    "text": {
                      "type": "text"
                    }
                  }
                },
                "family": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "version": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "platform": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "domain": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "ip": {
              "type": "ip"
            },
            "containerized": {
              "type": "boolean"
            },
            "name": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "id": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "type": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "mac": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "architecture": {
              "ignore_above": 1024,
              "type": "keyword"
            }
          }
        },
        "client": {
          "properties": {
            "geo": {
              "properties": {
                "continent_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "region_iso_code": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "city_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "country_iso_code": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "country_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "location": {
                  "type": "geo_point"
                },
                "region_name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "process": {
              "properties": {
                "args": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "start": {
                  "type": "date"
                },
                "working_directory": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "executable": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "port": {
              "type": "long"
            },
            "bytes": {
              "type": "long"
            },
            "ip": {
              "type": "ip"
            }
          }
        },
        "event": {
          "properties": {
            "duration": {
              "type": "long"
            },
            "kind": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "module": {
              "type": "constant_keyword",
              "value": "network_traffic"
            },
            "start": {
              "type": "date"
            },
            "end": {
              "type": "date"
            },
            "category": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "type": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "dataset": {
              "ignore_above": 1024,
              "type": "keyword"
            }
          }
        },
        "flow": {
          "properties": {
            "vlan": {
              "type": "long"
            },
            "final": {
              "type": "boolean"
            },
            "id": {
              "ignore_above": 1024,
              "type": "keyword"
            }
          }
        },
        "process": {
          "properties": {
            "args": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "name": {
              "ignore_above": 1024,
              "type": "keyword",
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              }
            },
            "start": {
              "type": "date"
            },
            "working_directory": {
              "ignore_above": 1024,
              "type": "keyword",
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              }
            },
            "executable": {
              "ignore_above": 1024,
              "type": "keyword",
              "fields": {
                "text": {
                  "type": "match_only_text"
                }
              }
            }
          }
        },
        "method": {
          "ignore_above": 1024,
          "type": "keyword"
        },
        "resource": {
          "ignore_above": 1024,
          "type": "keyword"
        },
        "query": {
          "ignore_above": 1024,
          "type": "keyword"
        },
        "dns": {
          "properties": {
            "resolved_ip": {
              "type": "ip"
            },
            "response_code": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "question": {
              "properties": {
                "registered_domain": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "top_level_domain": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "etld_plus_one": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "subdomain": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "type": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "class": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "answers": {
              "properties": {
                "data": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "name": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "type": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "class": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "ttl": {
                  "type": "long"
                }
              }
            },
            "flags": {
              "properties": {
                "authoritative": {
                  "type": "boolean"
                },
                "truncated_response": {
                  "type": "boolean"
                },
                "recursion_available": {
                  "type": "boolean"
                },
                "recursion_desired": {
                  "type": "boolean"
                },
                "checking_disabled": {
                  "type": "boolean"
                },
                "authentic_data": {
                  "type": "boolean"
                }
              }
            },
            "additionals_count": {
              "type": "long"
            },
            "header_flags": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "type": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "authorities": {
              "type": "flattened"
            },
            "op_code": {
              "ignore_above": 1024,
              "type": "keyword"
            },
            "additionals": {
              "type": "flattened"
            },
            "opt": {
              "properties": {
                "ext_rcode": {
                  "ignore_above": 1024,
                  "type": "keyword"
                },
                "udp_size": {
                  "type": "long"
                },
                "do": {
                  "type": "boolean"
                },
                "version": {
                  "ignore_above": 1024,
                  "type": "keyword"
                }
              }
            },
            "answers_count": {
              "type": "long"
            },
            "authorities_count": {
              "type": "long"
            },
            "id": {
              "ignore_above": 1024,
              "type": "keyword"
            }
          }
        },
        "params": {
          "type": "text"
        },
        "tags": {
          "ignore_above": 1024,
          "type": "keyword"
        },
        "@timestamp": {
          "ignore_malformed": false,
          "type": "date"
        },
        "data_stream": {
          "properties": {
            "namespace": {
              "type": "constant_keyword"
            },
            "type": {
              "type": "constant_keyword"
            },
            "dataset": {
              "type": "constant_keyword"
            }
          }
        },
        "response": {
          "type": "text"
        },
        "status": {
          "ignore_above": 1024,
          "type": "keyword"
        }
      }
    }
  },
  "_meta": {
    "package": {
      "name": "network_traffic"
    },
    "managed_by": "fleet",
    "managed": true
  }
}
EOF

curl -X PUT "http://localhost:30920/_index_template/logs-network_traffic.dns" -H "Content-Type: application/json" -u "sdg:changeme" -d @- << 'EOF'
{
  "priority": 200,
  "template": {
    "settings": {
      "index": {
          "default_pipeline": "enrich-logs-network_traffic",
          "number_of_shards": "1",
          "number_of_replicas": "0"
      }
    },
    "mappings": {
      "_meta": {
        "package": {
          "name": "network_traffic"
        },
        "managed_by": "fleet",
        "managed": true
      }
    }
  },
  "index_patterns": [
    "logs-network_traffic.dns*"
  ],
  "composed_of": [
    "logs@mappings",
    "logs@settings",
    "logs-network_traffic.dns@package",
    "ecs@mappings",
    ".fleet_globals-1",
    ".fleet_agent_id_verification-1",
    "logs@custom"
  ],
  "ignore_missing_component_templates": [
    "logs@custom",
    "logs-network_traffic.dns@custom"
  ],
  "allow_auto_create": true,
  "_meta": {
    "package": {
      "name": "network_traffic"
    },
    "managed_by": "fleet",
    "managed": true
  }
}
EOF

# Clear the screen
clear

echo
echo "Index templates for tracks loaded"
echo
sleep 2

# Clear the screen
clear

# Clear the screen
clear
echo
echo
echo "Accessing SecOps archive, historical records loading..."
echo
echo
sleep 2
curl -X POST "http://localhost:30001/api/cases" -u "sdg:changeme" --header "kbn-xsrf: true" -H "Content-Type: application/json" -d @/root/simple-data-generator/cases/101-1-case-1.json
curl -X POST "http://localhost:30001/api/cases" -u "sdg:changeme" --header "kbn-xsrf: true" -H "Content-Type: application/json" -d @/root/simple-data-generator/cases/101-1-case-2.json
curl -X POST "http://localhost:30001/api/cases" -u "sdg:changeme" --header "kbn-xsrf: true" -H "Content-Type: application/json" -d @/root/simple-data-generator/cases/101-1-case-3.json
curl -X POST "http://localhost:30001/api/cases" -u "sdg:changeme" --header "kbn-xsrf: true" -H "Content-Type: application/json" -d @/root/simple-data-generator/cases/101-1-case-4.json
curl -X POST "http://localhost:30001/api/cases" -u "sdg:changeme" --header "kbn-xsrf: true" -H "Content-Type: application/json" -d @/root/simple-data-generator/cases/101-1-case-5.json
clear
 
echo "Loading Elastic Rules, this will take a moment."
echo
echo
curl -X PUT "http://localhost:30001/api/detection_engine/rules/prepackaged" -u "sdg:changme"  --header "kbn-xsrf: true" -H "Content-Type: application/json"  -d '{}'
curl -X POST "http://localhost:30001/api/detection_engine/rules/_bulk_create" -u "sdg:changeme" --header "kbn-xsrf: true" -H "Content-Type: application/json" -d @/root/simple-data-generator/detection-rules/101-1.json
clear


echo 
echo
echo 
echo
echo "Starting data ingestion, you may begin the assignment"
java -jar /root/simple-data-generator/build/libs/simple-data-generator-1.0.0-SNAPSHOT.jar /root/simple-data-generator/tracks/security-101-1.yml
