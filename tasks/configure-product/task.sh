#!/bin/bash

set -eu

function main() {
  local configuration_properties="$(read_json_from_file ${PRODUCT_PROPERTIES_FILE})"
  local configuration_network="$(read_json_from_file ${PRODUCT_NETWORK_FILE})"
  local configuration_resources="$(read_json_from_file ${PRODUCT_RESOURCES_FILE})"

  om-linux \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --username "${OPSMAN_USERNAME}" \
    --password "${OPSMAN_PASSWORD}" \
    --skip-ssl-validation \
    configure-product \
    --product-name "${PRODUCT_NAME}" \
    --product-properties "${configuration_properties}" \
    --product-network "${configuration_network}" \
    --product-resources "${configuration_resources}"
}

function read_json_from_file() {
  local file_contents="$(cat ${1})"
  if [[ -z "${file_contents}" ]]; then
    file_contents="{}"
  fi
  echo "${file_contents}"
}

main
