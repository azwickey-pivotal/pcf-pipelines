#!/bin/bash

set -eu

function isPopulated() {
    local true=0
    local false=1
    local envVar="${1}"

    if [[ "${envVar}" == "" ]]; then
        return ${false}
    elif [[ "${envVar}" == null ]]; then
        return ${false}
    else
        return ${true}
    fi
}

product_properties=$(
  jq -n \
    --arg rmq_user $RMQ_USER \
    --arg rmq_password $RMQ_PASSWORD \
    --arg azs "$DEPLOYMENT_NW_AZS" \
    '
    {
      ".properties.disk_alarm_threshold": { "value": "mem_relative_1_0" },
      ".properties.syslog_selector": { "value": "disabled" },
      ".properties.on_demand_broker_plan_1_rabbitmq_az_placement": { "value": ($azs | split(",") | map("\(.)")) },
      ".properties.on_demand_broker_plan_1_disk_limit_acknowledgement": { "value": [ "acknowledge" ] },
      ".properties.on_demand_broker_plan_1_cf_service_access": { "value": "enable" },
      ".properties.on_demand_broker_plan_6_rabbitmq_az_placement": { "value": ($azs | split(",") | map("\(.)")) },
      ".properties.on_demand_broker_plan_6_disk_limit_acknowledgement": { "value": [ "acknowledge" ] },
      ".properties.on_demand_broker_plan_6_cf_service_access": { "value": "enable" },
      ".rabbitmq-server.server_admin_credentials": {
        "value": {
          "identity": $rmq_user,
          "password": $rmq_password
        }
      },
    }
    '
)

product_network=$(
  jq -n \
    --arg network_name "$NETWORK_NAME" \
    --arg other_azs "$DEPLOYMENT_NW_AZS" \
    --arg singleton_az "$SINGLETON_JOB_AZ" \
    '
    {
      "network": {
        "name": $network_name
      },
      "service_network": {
        "name": $network_name
      },
      "other_availability_zones": ($other_azs | split(",") | map({name: .})),
      "singleton_availability_zone": {
        "name": $singleton_az
      }
    }
    '
)

product_resources=$(
  jq -n \
    --argjson internet_connected $INTERNET_CONNECTED \
    --argjson rabbitmq_server_instances $RMQ_SERVER_INSTANCES \
    --argjson rabbitmq_haproxy_instances $RMQ_HAPROXY_INSTANCES \
    --argjson rabbitmq_broker_instances $RMQ_BROKER_INSTANCES \
    --argjson on_demand_broker_instances $RMQ_ODB_INSTANCES \
    '
    {
        "rabbitmq-server": { "instances": $rabbitmq_server_instances },
        "rabbitmq-haproxy": { "instances": $rabbitmq_haproxy_instances },
        "rabbitmq-broker": { "instances": $rabbitmq_broker_instances },
        "on-demand-broker": { "instances": $on_demand_broker_instances }

    }
    '
)
echo $product_properties
echo $product_network
echo $product_resources
echo $product_properties >> configuration/product_properties
echo $product_network >> configuration/product_network
echo $product_resources >> configuration/product_resources
