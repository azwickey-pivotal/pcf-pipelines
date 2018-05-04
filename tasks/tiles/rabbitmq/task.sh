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
    '
    {
      ".properties.rabbitmq-server.server_admin_credentials.identity": { "value": $rmq_user },
      ".properties.rabbitmq-server.server_admin_credentials.password": { "value": $rmq_password },
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
    --argjson rabbitmq-server_instances $RMQ_SERVER_INSTANCES \
    --argjson rabbitmq-haproxy_instances $RMQ_HAPROXY_INSTANCES \
    --argjson rabbitmq-broker_instances $RMQ_BROKER_INSTANCES \
    --argjson on-demand-broker_instances $RMQ_ODB_INSTANCES \
    '
    {
        "rabbitmq-server": { "instances": $rabbitmq-server_instances },
        "rabbitmq-haproxy": { "instances": $rabbitmq-haproxy_instances },
        "rabbitmq-broker": { "instances": $rabbitmq-broker_instances },
        "on-demand-broker": { "instances": $on-demand-broker_instances }

    }
    '
)

mkdir configuration
echo $product_properties >> configuration/product_properties
echo $product_network >> configuration/product_network
echo $product_resources >> configuration/product_resources