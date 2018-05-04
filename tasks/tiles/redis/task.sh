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
      ".properties.syslog_selector": { "value": "No" },
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
    --argjson odb_instances $REDIS_ODB_INSTANCES \
    --argjson dedicated_node_instances $REDIS_DEDICATED_INSTANCES \
    '
    {
        "redis-on-demand-broker": { "instances": $odb_instances },
        "dedicated-node": { "instances": $dedicated_node_instances },
    }
    '
)
echo $product_properties
echo $product_network
echo $product_resources
echo $product_properties >> configuration/product_properties
echo $product_network >> configuration/product_network
echo $product_resources >> configuration/product_resources
