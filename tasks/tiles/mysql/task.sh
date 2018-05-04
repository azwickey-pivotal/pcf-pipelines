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
    --arg azs "$DEPLOYMENT_NW_AZS" \
    '
    {
      ".properties.syslog_selector": { "value": "No" },
      ".properties.plan1_selector.active.az_multi_select": { "value": ($azs | split(",") | map("\(.)")) },
      ".properties.plan2_selector.active.az_multi_select": { "value": ($azs | split(",") | map("\(.)")) },
      ".properties.plan3_selector.active.az_multi_select": { "value": ($azs | split(",") | map("\(.)")) },

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
    --argjson dedicated_broker_instances $MYSQL_DEDICATED_BROKER_INSTANCES \
    '
    {
        "dedicated-mysql-broker": { "instances": $dedicated_broker_instances },
    }
    '
)
echo $product_properties
echo $product_network
echo $product_resources
echo $product_properties >> configuration/product_properties
echo $product_network >> configuration/product_network
echo $product_resources >> configuration/product_resources
