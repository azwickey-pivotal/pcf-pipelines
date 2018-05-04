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
    --arg az "$SINGLETON_JOB_AZ" \
    '
    {
      ".properties.syslog_selector.inactive": { "value": "enabled" },
      ".properties.small_plan_selector.active.az_single_select": { "value": $az },
      ".properties.medium_plan_selector.active.az_single_select": { "value": $az },
      ".properties.large_plan_selector.active.az_single_select": { "value": $az },
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
