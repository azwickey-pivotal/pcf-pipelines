#!/bin/bash

set -eu

source pcf-pipelines/functions/generate_cert.sh

if [[ -z "$SSL_CERT" ]]; then
  domains=(
    "*.${SYSTEM_DOMAIN}"
    "*.${APPS_DOMAIN}"
    "*.login.${SYSTEM_DOMAIN}"
    "*.uaa.${SYSTEM_DOMAIN}"
  )

  certificates=$(generate_cert "${domains[*]}")
  SSL_CERT=`echo $certificates | jq --raw-output '.certificate'`
  SSL_PRIVATE_KEY=`echo $certificates | jq --raw-output '.key'`
fi


if [[ -z "$SAML_SSL_CERT" ]]; then
  saml_cert_domains=(
    "*.${SYSTEM_DOMAIN}"
    "*.login.${SYSTEM_DOMAIN}"
    "*.uaa.${SYSTEM_DOMAIN}"
  )

  saml_certificates=$(generate_cert "${saml_cert_domains[*]}")
  SAML_SSL_CERT=$(echo $saml_certificates | jq --raw-output '.certificate')
  SAML_SSL_PRIVATE_KEY=$(echo $saml_certificates | jq --raw-output '.key')
fi

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

function formatCredhubEncryptionKeysJson() {
    local credhub_encryption_key_name1="${1}"
    local credhub_encryption_key_secret1=${2//$'\n'/'\n'}
    local credhub_primary_encryption_name="${3}"
    credhub_encryption_keys_json="{
            \"name\": \"$credhub_encryption_key_name1\",
            \"key\":{
                \"secret\": \"$credhub_encryption_key_secret1\"
             }"
    if [[ "${credhub_primary_encryption_name}" == $credhub_encryption_key_name1 ]]; then
        credhub_encryption_keys_json="$credhub_encryption_keys_json, \"primary\": true}"
    else
        credhub_encryption_keys_json="$credhub_encryption_keys_json}"
    fi
    echo "$credhub_encryption_keys_json"
}

credhub_encryption_keys_json=$(formatCredhubEncryptionKeysJson "${CREDUB_ENCRYPTION_KEY_NAME1}" "${CREDUB_ENCRYPTION_KEY_SECRET1}" "${CREDHUB_PRIMARY_ENCRYPTION_NAME}")
if isPopulated "${CREDUB_ENCRYPTION_KEY_NAME2}"; then
    credhub_encryption_keys_json2=$(formatCredhubEncryptionKeysJson "${CREDUB_ENCRYPTION_KEY_NAME2}" "${CREDUB_ENCRYPTION_KEY_SECRET2}" "${CREDHUB_PRIMARY_ENCRYPTION_NAME}")
    credhub_encryption_keys_json="$credhub_encryption_keys_json,$credhub_encryption_keys_json2"
fi
if isPopulated "${CREDUB_ENCRYPTION_KEY_NAME3}"; then
    credhub_encryption_keys_json3=$(formatCredhubEncryptionKeysJson "${CREDUB_ENCRYPTION_KEY_NAME3}" "${CREDUB_ENCRYPTION_KEY_SECRET3}" "${CREDHUB_PRIMARY_ENCRYPTION_NAME}")
    credhub_encryption_keys_json="$credhub_encryption_keys_json,$credhub_encryption_keys_json3"
fi
credhub_encryption_keys_json="[$credhub_encryption_keys_json]"

if [[ "${IAAS}" == "aws" ]]; then
  if [[ ${POE_SSL_NAME1} == "" || ${POE_SSL_NAME1} == "null" ]]; then
    domains=(
        "*.${SYSTEM_DOMAIN}"
        "*.${APPS_DOMAIN}"
        "*.login.${SYSTEM_DOMAIN}"
        "*.uaa.${SYSTEM_DOMAIN}"
    )

    certificate=$(generate_cert "${domains[*]}")
    pcf_ert_ssl_cert=`echo $certificate | jq '.certificate'`
    pcf_ert_ssl_key=`echo $certificate | jq '.key'`
    networking_poe_ssl_certs_json="[
      {
        \"name\": \"Certificate 1\",
        \"certificate\": {
          \"cert_pem\": $pcf_ert_ssl_cert,
          \"private_key_pem\": $pcf_ert_ssl_key
        }
      }
    ]"
  else
    cert=${POE_SSL_CERT1//$'\n'/'\n'}
    key=${POE_SSL_KEY1//$'\n'/'\n'}
    networking_poe_ssl_certs_json="[{
      \"name\": \"$POE_SSL_NAME1\",
      \"certificate\": {
        \"cert_pem\": \"$cert\",
        \"private_key_pem\": \"$key\"
      }
    }]"
  fi

  cd terraform-state
    output_json=$(terraform output --json -state *.tfstate)
    db_host=$(echo $output_json | jq --raw-output '.db_host.value')
    aws_region=$(echo $output_json | jq --raw-output '.region.value')
    aws_access_key=`terraform state show aws_iam_access_key.pcf_iam_user_access_key | grep ^id | awk '{print $3}'`
    aws_secret_key=`terraform state show aws_iam_access_key.pcf_iam_user_access_key | grep ^secret | awk '{print $3}'`
  cd -
elif [[ "${IAAS}" == "gcp" ]]; then
  cd terraform-state
    db_host=$(terraform output --json -state *.tfstate | jq --raw-output '.sql_instance_ip.value')
    pcf_ert_ssl_cert="$(terraform output -json ert_certificate | jq .value)"
    pcf_ert_ssl_key="$(terraform output -json ert_certificate_key | jq .value)"
  cd -

  if [ -z "$db_host" ]; then
    echo Failed to get SQL instance IP from Terraform state file
    exit 1
  fi
  networking_poe_ssl_certs_json="[
    {
      \"name\": \"Certificate 1\",
      \"certificate\": {
        \"cert_pem\": $pcf_ert_ssl_cert,
        \"private_key_pem\": $pcf_ert_ssl_key
      }
    }
  ]"
fi

cf_properties=$(
  jq -n \
    --arg iaas $IAAS \
    --arg terraform_prefix $terraform_prefix \
    --arg tcp_routing "$TCP_ROUTING" \
    --arg tcp_routing_ports "$TCP_ROUTING_PORTS" \
    --arg loggregator_endpoint_port "$LOGGREGATOR_ENDPOINT_PORT" \
    --arg route_services "$ROUTE_SERVICES" \
    --arg ignore_ssl_cert "$IGNORE_SSL_CERT" \
    --arg security_acknowledgement "$SECURITY_ACKNOWLEDGEMENT" \
    --arg system_domain "$SYSTEM_DOMAIN" \
    --arg apps_domain "$APPS_DOMAIN" \
    --arg default_quota_memory_limit_in_mb "$DEFAULT_QUOTA_MEMORY_LIMIT_IN_MB" \
    --arg default_quota_max_services_count "$DEFAULT_QUOTA_MAX_SERVICES_COUNT" \
    --arg allow_app_ssh_access "$ALLOW_APP_SSH_ACCESS" \
    --arg ha_proxy_ips "$HA_PROXY_IPS" \
    --arg skip_cert_verify "$SKIP_CERT_VERIFY" \
    --arg router_static_ips "$ROUTER_STATIC_IPS" \
    --arg disable_insecure_cookies "$DISABLE_INSECURE_COOKIES" \
    --arg router_request_timeout_seconds "$ROUTER_REQUEST_TIMEOUT_IN_SEC" \
    --arg mysql_monitor_email "$MYSQL_MONITOR_EMAIL" \
    --arg tcp_router_static_ips "$TCP_ROUTER_STATIC_IPS" \
    --arg company_name "$COMPANY_NAME" \
    --arg ssh_static_ips "$SSH_STATIC_IPS" \
    --arg mysql_static_ips "$MYSQL_STATIC_IPS" \
    --arg cert_pem "$SSL_CERT" \
    --arg private_key_pem "$SSL_PRIVATE_KEY" \
    --arg haproxy_forward_tls "$HAPROXY_FORWARD_TLS" \
    --arg haproxy_backend_ca "$HAPROXY_BACKEND_CA" \
    --arg router_tls_ciphers "$ROUTER_TLS_CIPHERS" \
    --arg haproxy_tls_ciphers "$HAPROXY_TLS_CIPHERS" \
    --arg disable_http_proxy "$DISABLE_HTTP_PROXY" \
    --arg smtp_from "$SMTP_FROM" \
    --arg smtp_address "$SMTP_ADDRESS" \
    --arg smtp_port "$SMTP_PORT" \
    --arg smtp_user "$SMTP_USER" \
    --arg smtp_password "$SMTP_PWD" \
    --arg smtp_enable_starttls_auto "$SMTP_ENABLE_STARTTLS_AUTO" \
    --arg smtp_auth_mechanism "$SMTP_AUTH_MECHANISM" \
    --arg enable_security_event_logging "$ENABLE_SECURITY_EVENT_LOGGING" \
    --arg syslog_host "$SYSLOG_HOST" \
    --arg syslog_drain_buffer_size "$SYSLOG_DRAIN_BUFFER_SIZE" \
    --arg syslog_port "$SYSLOG_PORT" \
    --arg syslog_protocol "$SYSLOG_PROTOCOL" \
    --arg authentication_mode "$AUTHENTICATION_MODE" \
    --arg ldap_url "$LDAP_URL" \
    --arg ldap_user "$LDAP_USER" \
    --arg ldap_password "$LDAP_PWD" \
    --arg ldap_search_base "$SEARCH_BASE" \
    --arg ldap_search_filter "$SEARCH_FILTER" \
    --arg ldap_group_search_base "$GROUP_SEARCH_BASE" \
    --arg ldap_group_search_filter "$GROUP_SEARCH_FILTER" \
    --arg ldap_mail_attr_name "$MAIL_ATTR_NAME" \
    --arg ldap_first_name_attr "$FIRST_NAME_ATTR" \
    --arg ldap_last_name_attr "$LAST_NAME_ATTR" \
    --arg saml_cert_pem "$SAML_SSL_CERT" \
    --arg saml_key_pem "$SAML_SSL_PRIVATE_KEY" \
    --arg mysql_backups "$MYSQL_BACKUPS" \
    --arg mysql_backups_s3_endpoint_url "$MYSQL_BACKUPS_S3_ENDPOINT_URL" \
    --arg mysql_backups_s3_bucket_name "$MYSQL_BACKUPS_S3_BUCKET_NAME" \
    --arg mysql_backups_s3_bucket_path "$MYSQL_BACKUPS_S3_BUCKET_PATH" \
    --arg mysql_backups_s3_access_key_id "$MYSQL_BACKUPS_S3_ACCESS_KEY_ID" \
    --arg mysql_backups_s3_secret_access_key "$MYSQL_BACKUPS_S3_SECRET_ACCESS_KEY" \
    --arg mysql_backups_s3_cron_schedule "$MYSQL_BACKUPS_S3_CRON_SCHEDULE" \
    --arg mysql_backups_scp_server "$MYSQL_BACKUPS_SCP_SERVER" \
    --arg mysql_backups_scp_port "$MYSQL_BACKUPS_SCP_PORT" \
    --arg mysql_backups_scp_user "$MYSQL_BACKUPS_SCP_USER" \
    --arg mysql_backups_scp_key "$MYSQL_BACKUPS_SCP_KEY" \
    --arg mysql_backups_scp_destination "$MYSQL_BACKUPS_SCP_DESTINATION" \
    --arg mysql_backups_scp_cron_schedule "$MYSQL_BACKUPS_SCP_CRON_SCHEDULE" \
    --arg container_networking_nw_cidr "$CONTAINER_NETWORKING_NW_CIDR" \
    --arg db_host "$db_host" \
    --arg db_locket_username "$db_locket_username" \
    --arg db_locket_password "$db_locket_password" \
    --arg db_silk_username "$db_silk_username" \
    --arg db_silk_password "$db_silk_password" \
    --arg db_app_usage_service_username "$db_app_usage_service_username" \
    --arg db_app_usage_service_password "$db_app_usage_service_password" \
    --arg db_autoscale_username "$db_autoscale_username" \
    --arg db_autoscale_password "$db_autoscale_password" \
    --arg db_diego_username "$db_diego_username" \
    --arg db_diego_password "$db_diego_password" \
    --arg db_notifications_username "$db_notifications_username" \
    --arg db_notifications_password "$db_notifications_password" \
    --arg db_routing_username "$db_routing_username" \
    --arg db_routing_password "$db_routing_password" \
    --arg db_uaa_username "$db_uaa_username" \
    --arg db_uaa_password "$db_uaa_password" \
    --arg db_ccdb_username "$db_ccdb_username" \
    --arg db_ccdb_password "$db_ccdb_password" \
    --arg db_accountdb_username "$db_accountdb_username" \
    --arg db_accountdb_password "$db_accountdb_password" \
    --arg db_networkpolicyserverdb_username "$db_networkpolicyserverdb_username" \
    --arg db_networkpolicyserverdb_password "$db_networkpolicyserverdb_password" \
    --arg db_nfsvolumedb_username "$db_nfsvolumedb_username" \
    --arg db_nfsvolumedb_password "$db_nfsvolumedb_password" \
    --arg s3_endpoint "$S3_ENDPOINT" \
    --arg aws_access_key "${aws_access_key:-''}" \
    --arg aws_secret_key "${aws_secret_key:-''}" \
    --arg aws_region "${aws_region:-''}" \
    --arg gcp_storage_access_key "${gcp_storage_access_key:-''}" \
    --arg gcp_storage_secret_key "${gcp_storage_secret_key:-''}" \
    --argjson credhub_encryption_keys "$credhub_encryption_keys_json" \
    --argjson networking_poe_ssl_certs "$networking_poe_ssl_certs_json" \
    --arg container_networking_nw_cidr "$CONTAINER_NETWORKING_NW_CIDR" \
    '
    {
      ".properties.system_blobstore": {
        "value": "internal"
      },
      ".properties.logger_endpoint_port": {
        "value": $loggregator_endpoint_port
      },
      ".properties.container_networking_interface_plugin.silk.network_cidr": {
        "value": $container_networking_nw_cidr
      },
      ".properties.security_acknowledgement": {
        "value": $security_acknowledgement
      },
      ".properties.push_apps_manager_company_name.": {
        "value": $company_name
      },
      ".cloud_controller.system_domain": {
        "value": $system_domain
      },
      ".cloud_controller.apps_domain": {
        "value": $apps_domain
      },
      ".cloud_controller.default_quota_memory_limit_mb": {
        "value": $default_quota_memory_limit_in_mb
      },
      ".cloud_controller.default_quota_max_number_services": {
        "value": $default_quota_max_services_count
      },
      ".cloud_controller.allow_app_ssh_access": {
        "value": $allow_app_ssh_access
      },
      ".ha_proxy.static_ips": {
        "value": $ha_proxy_ips
      },
      ".ha_proxy.skip_cert_verify": {
        "value": $skip_cert_verify
      },
      ".router.static_ips": {
        "value": $router_static_ips
      },
      ".router.disable_insecure_cookies": {
        "value": $disable_insecure_cookies
      },
      ".router.request_timeout_in_seconds": {
        "value": $router_request_timeout_seconds
      },
      ".mysql_monitor.recipient_email": {
        "value": $mysql_monitor_email
      },
      ".tcp_router.static_ips": {
        "value": $tcp_router_static_ips
      },
      ".diego_brain.static_ips": {
        "value": $ssh_static_ips
      },
      ".mysql_proxy.static_ips": {
        "value": $mysql_static_ips
      },
      ".properties.system_database": { "value": "external" },
      ".properties.system_database.external.port": { "value": "3306" },
      ".properties.system_database.external.host": { "value": $db_host },
      ".properties.system_database.external.app_usage_service_username": { "value": $db_app_usage_service_username },
      ".properties.system_database.external.app_usage_service_password": { "value": { "secret": $db_app_usage_service_password } },
      ".properties.system_database.external.autoscale_username": { "value": $db_autoscale_username },
      ".properties.system_database.external.autoscale_password": { "value": { "secret": $db_autoscale_password } },
      ".properties.system_database.external.diego_username": { "value": $db_diego_username },
      ".properties.system_database.external.diego_password": { "value": { "secret": $db_diego_password } },
      ".properties.system_database.external.notifications_username": { "value": $db_notifications_username },
      ".properties.system_database.external.notifications_password": { "value": { "secret": $db_notifications_password } },
      ".properties.system_database.external.routing_username": { "value": $db_routing_username },
      ".properties.system_database.external.routing_password": { "value": { "secret": $db_routing_password } },
      ".properties.system_database.external.ccdb_username": { "value": $db_ccdb_username },
      ".properties.system_database.external.ccdb_password": { "value": { "secret": $db_ccdb_password } },
      ".properties.system_database.external.account_username": { "value": $db_accountdb_username },
      ".properties.system_database.external.account_password": { "value": { "secret": $db_accountdb_password } },
      ".properties.system_database.external.networkpolicyserver_username": { "value": $db_networkpolicyserverdb_username },
      ".properties.system_database.external.networkpolicyserver_password": { "value": { "secret": $db_networkpolicyserverdb_password } },
      ".properties.system_database.external.nfsvolume_username": { "value": $db_nfsvolumedb_username },
      ".properties.system_database.external.nfsvolume_password": { "value": { "secret": $db_nfsvolumedb_password } },
      ".properties.system_database.external.locket_username": { "value": $db_locket_username },
      ".properties.system_database.external.locket_password": { "value": { "secret": $db_locket_password } },
      ".properties.system_database.external.silk_username": { "value": $db_silk_username },
      ".properties.system_database.external.silk_password": { "value": { "secret": $db_silk_password } },
      ".properties.uaa_database": { "value": "external" },
      ".properties.uaa_database.external.host": { "value": $db_host },
      ".properties.uaa_database.external.port": { "value": "3306" },
      ".properties.uaa_database.external.uaa_username": { "value": $db_uaa_username },
      ".properties.uaa_database.external.uaa_password": { "value": { "secret": $db_uaa_password } },
    }

    +

    # Route Services
    if $route_services == "enable" then
     {
       ".properties.route_services": {
         "value": "enable"
       },
       ".properties.route_services.enable.ignore_ssl_cert_verification": {
         "value": $ignore_ssl_cert
       }
     }
    else
     {
       ".properties.route_services": {
         "value": "disable"
       }
     }
    end

    +

    # TCP Routing
    if $tcp_routing == "enable" then
     {
       ".properties.tcp_routing": {
          "value": "enable"
        },
        ".properties.tcp_routing.enable.reservable_ports": {
          "value": $tcp_routing_ports
        }
      }
    else
      {
        ".properties.tcp_routing": {
          "value": "disable"
        }
      }
    end

    +

    # Blobstore

    if $iaas == "aws" then
      {
        ".properties.system_blobstore": { "value": "external" },
        ".properties.system_blobstore.external.buildpacks_bucket": { "value": "\($terraform_prefix)-buildpacks" },
        ".properties.system_blobstore.external.droplets_bucket": { "value": "\($terraform_prefix)-droplets" },
        ".properties.system_blobstore.external.packages_bucket": { "value": "\($terraform_prefix)-packages" },
        ".properties.system_blobstore.external.resources_bucket": { "value": "\($terraform_prefix)-resources" },
        ".properties.system_blobstore.external.access_key": { "value": $aws_access_key },
        ".properties.system_blobstore.external.secret_key": { "value": { "secret": $aws_secret_key } },
        ".properties.system_blobstore.external.signature_version.value": { "value": "4" },
        ".properties.system_blobstore.external.region": { "value": $aws_region },
        ".properties.system_blobstore.external.endpoint": { "value": $s3_endpoint }
      }
    elif $iaas == "gcp" then
      {
        ".properties.system_blobstore": { "value": "external_gcs" },
        ".properties.system_blobstore.external_gcs.buildpacks_bucket": { "value": "\($terraform_prefix)-buildpacks" },
        ".properties.system_blobstore.external_gcs.droplets_bucket": { "value": "\($terraform_prefix)-droplets" },
        ".properties.system_blobstore.external_gcs.packages_bucket": { "value": "\($terraform_prefix)-packages" },
        ".properties.system_blobstore.external_gcs.resources_bucket": { "value": "\($terraform_prefix)-resources" },
        ".properties.system_blobstore.external_gcs.access_key": { "value": $gcp_storage_access_key },
        ".properties.system_blobstore.external_gcs.secret_key": { "value": { "secret": $gcp_storage_secret_key } }
      }
    else
      .
    end

    +

    # SSL Termination
    {
      ".properties.networking_poe_ssl_certs": {
        "value": [
          {
            "certificate": {
              "cert_pem": $cert_pem,
              "private_key_pem": $private_key_pem
            },
            "name": "Certificate"
          }
        ]
      }
    }

    +

    # HAProxy Forward TLS
    if $haproxy_forward_tls == "enable" then
      {
        ".properties.haproxy_forward_tls": {
          "value": "enable"
        },
        ".properties.haproxy_forward_tls.enable.backend_ca": {
          "value": $haproxy_backend_ca
        }
      }
    else
      {
        ".properties.haproxy_forward_tls": {
          "value": "disable"
        }
      }
    end

    +

    {
      ".properties.routing_disable_http": {
        "value": $disable_http_proxy
      }
    }

    +

    # TLS Cipher Suites
    {
      ".properties.gorouter_ssl_ciphers": {
        "value": $router_tls_ciphers
      },
      ".properties.haproxy_ssl_ciphers": {
        "value": $haproxy_tls_ciphers
      }
    }

    +

    # SMTP Configuration
    if $smtp_address != "" then
      {
        ".properties.smtp_from": {
          "value": $smtp_from
        },
        ".properties.smtp_address": {
          "value": $smtp_address
        },
        ".properties.smtp_port": {
          "value": $smtp_port
        },
        ".properties.smtp_credentials": {
          "value": {
            "identity": $smtp_user,
            "password": $smtp_password
          }
        },
        ".properties.smtp_enable_starttls_auto": {
          "value": $smtp_enable_starttls_auto
        },
        ".properties.smtp_auth_mechanism": {
          "value": $smtp_auth_mechanism
        }
      }
    else
      .
    end

    +

    # Syslog
    if $syslog_host != "" then
      {
        ".doppler.message_drain_buffer_size": {
          "value": $syslog_drain_buffer_size
        },
        ".cloud_controller.security_event_logging_enabled": {
          "value": $enable_security_event_logging
        },
        ".properties.syslog_host": {
          "value": $syslog_host
        },
        ".properties.syslog_port": {
          "value": $syslog_port
        },
        ".properties.syslog_protocol": {
          "value": $syslog_protocol
        }
      }
    else
      .
    end

    +

    # Authentication
    if $authentication_mode == "internal" then
      {
        ".properties.uaa": {
          "value": "internal"
        }
      }
    elif $authentication_mode == "ldap" then
      {
        ".properties.uaa": {
          "value": "ldap"
        },
        ".properties.uaa.ldap.url": {
          "value": $ldap_url
        },
        ".properties.uaa.ldap.credentials": {
          "value": {
            "identity": $ldap_user,
            "password": $ldap_password
          }
        },
        ".properties.uaa.ldap.search_base": {
          "value": $ldap_search_base
        },
        ".properties.uaa.ldap.search_filter": {
          "value": $ldap_search_filter
        },
        ".properties.uaa.ldap.group_search_base": {
          "value": $ldap_group_search_base
        },
        ".properties.uaa.ldap.group_search_filter": {
          "value": $ldap_group_search_filter
        },
        ".properties.uaa.ldap.mail_attribute_name": {
          "value": $ldap_mail_attr_name
        },
        ".properties.uaa.ldap.first_name_attribute": {
          "value": $ldap_first_name_attr
        },
        ".properties.uaa.ldap.last_name_attribute": {
          "value": $ldap_last_name_attr
        }
      }
    else
      .
    end

    +

    # UAA SAML Credentials
    {
      ".uaa.service_provider_key_credentials": {
        value: {
          "cert_pem": $saml_cert_pem,
          "private_key_pem": $saml_key_pem
        }
      }
    }

    +

    # MySQL Backups
    if $mysql_backups == "s3" then
      {
        ".properties.mysql_backups": {
          "value": "s3"
        },
        ".properties.mysql_backups.s3.endpoint_url":  {
          "value": $mysql_backups_s3_endpoint_url
        },
        ".properties.mysql_backups.s3.bucket_name":  {
          "value": $mysql_backups_s3_bucket_name
        },
        ".properties.mysql_backups.s3.bucket_path":  {
          "value": $mysql_backups_s3_bucket_path
        },
        ".properties.mysql_backups.s3.access_key_id":  {
          "value": $mysql_backups_s3_access_key_id
        },
        ".properties.mysql_backups.s3.secret_access_key":  {
          "value": $mysql_backups_s3_secret_access_key
        },
        ".properties.mysql_backups.s3.cron_schedule":  {
          "value": $mysql_backups_s3_cron_schedule
        }
      }
    elif $mysql_backups == "scp" then
      {
        ".properties.mysql_backups": {
          "value": "scp"
        },
        ".properties.mysql_backups.scp.server": {
          "value": $mysql_backups_scp_server
        },
        ".properties.mysql_backups.scp.port": {
          "value": $mysql_backups_scp_port
        },
        ".properties.mysql_backups.scp.user": {
          "value": $mysql_backups_scp_user
        },
        ".properties.mysql_backups.scp.key": {
          "value": $mysql_backups_scp_key
        },
        ".properties.mysql_backups.scp.destination": {
          "value": $mysql_backups_scp_destination
        },
        ".properties.mysql_backups.scp.cron_schedule" : {
          "value": $mysql_backups_scp_cron_schedule
        }
      }
    else
      .
    end
    '
)

cf_network=$(
  jq -n \
    --arg network_name "$NETWORK_NAME" \
    --arg other_azs "$DEPLOYMENT_NW_AZS" \
    --arg singleton_az "$ERT_SINGLETON_JOB_AZ" \
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

cf_resources=$(
  jq -n \
    --arg terraform_prefix $terraform_prefix \
    --arg iaas $IAAS \
    --argjson internet_connected $INTERNET_CONNECTED \
    --argjson database_instances $DATABASE_INSTANCES \
    --argjson blobstore_instances $BLOBSTORE_INSTANCES \
    --argjson control_instances $CONTROL_INSTANCES \
    --argjson compute_instances $COMPUTE_INSTANCES \
    --argjson backup_prepare_instances $BACKUP_PREPARE_INSTANCES \
    --argjson ha_proxy_instances $HA_PROXY_INSTANCES \
    --argjson router_instances $ROUTER_INSTANCES \
    --argjson mysql_monitor_instances $MYSQL_MONITOR_INSTANCES \
    --argjson tcp_router_instances $TCP_ROUTER_INSTANCES \
    --arg ha_proxy_elb_name "$HA_PROXY_LB_NAME" \
    --arg ha_proxy_floating_ips "$HAPROXY_FLOATING_IPS" \
    '
    {
        "database": { "instances": $database_instances },
        "blobstore": { "instances": $blobstore_instances },
        "control": { "instances": $control_instances },
        "compute": { "instances": $compute_instances },
        "backup-prepare": { "instances": $backup_prepare_instances },
        "ha_proxy": { "instances": $ha_proxy_instances },
        "router": { "instances": $router_instances },
        "mysql_monitor": { "instances": $mysql_monitor_instances },
        "tcp_router": { "instances": $tcp_router_instances }

    }

    +

    if $iaas == "azure" then

    {
        "database": {"internet_connected": $internet_connected},
        "blobstore": {"internet_connected": $internet_connected},
        "control": {"internet_connected": $internet_connected},
        "compute": {"internet_connected": $internet_connected},
        "backup-prepare": {"internet_connected": $internet_connected},
        "router": {"internet_connected": $internet_connected},
        "mysql_monitor": {"internet_connected": $internet_connected},
        "tcp_router": {"internet_connected": $internet_connected},
        "smoke-tests": {"internet_connected": $internet_connected},
        "push-apps-manager": {"internet_connected": $internet_connected},
        "push-usage-service": {"internet_connected": $internet_connected},
        "notifications": {"internet_connected": $internet_connected},
        "notifications-ui": {"internet_connected": $internet_connected},
        "push-pivotal-account": {"internet_connected": $internet_connected},
        "autoscaling": {"internet_connected": $internet_connected},
        "autoscaling-register-broker": {"internet_connected": $internet_connected},
        "nfsbrokerpush": {"internet_connected": $internet_connected},
        "bootstrap": {"internet_connected": $internet_connected},
        "mysql-rejoin-unsafe": {"internet_connected": $internet_connected}
    }

    else
      .
    end

    |

    if $ha_proxy_elb_name != "" then
      .ha_proxy |= . + { "elb_names": [ $ha_proxy_elb_name ] }
    else
      .
    end

    |

    if $ha_proxy_floating_ips != "" then
      .ha_proxy |= . + { "floating_ips": $ha_proxy_floating_ips }
    else
      .
    end

    |

    # ELBs

    if $iaas == "aws" then
      .router |= . + { "elb_names": ["\($terraform_prefix)-Pcf-Http-Elb"] }
      | .control |= . + { "elb_names": ["\($terraform_prefix)-Pcf-Ssh-Elb"] }
    elif $iaas == "gcp" then
      .router |= . + { "elb_names": ["http:\($terraform_prefix)-http-lb-backend","tcp:\($terraform_prefix)-wss-logs"] }
      | .control |= . + { "elb_names": ["tcp:\($terraform_prefix)-ssh-proxy"] }
    else
      .
    end
    '
)

om-linux \
  --target https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  --client-id "${OPSMAN_CLIENT_ID}" \
  --client-secret "${OPSMAN_CLIENT_SECRET}" \
  --username "$OPS_MGR_USR" \
  --password "$OPS_MGR_PWD" \
  --skip-ssl-validation \
  configure-product \
  --product-name cf \
  --product-properties "$cf_properties" \
  --product-network "$cf_network" \
  --product-resources "$cf_resources"
