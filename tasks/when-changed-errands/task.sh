#!/bin/bash

set -eu

if [[ -z "$ERRANDS_TO_CHANGE" ]] || [[ "$ERRANDS_TO_CHANGE" == "none" ]]; then
  echo Nothing to do.
  exit 0
fi

enabled_errands=$(
  om-linux \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --skip-ssl-validation \
    --client-id "${OPSMAN_CLIENT_ID}" \
    --client-secret "${OPSMAN_CLIENT_SECRET}" \
    --username "$OPSMAN_USERNAME" \
    --password "$OPSMAN_PASSWORD" \
    errands \
    --product-name "$PRODUCT_NAME" |
  tail -n+4 | head -n-1 | grep -v false | cut -d'|' -f2 | tr -d ' '
)

if [[ "$ERRANDS_TO_CHANGE" == "all" ]]; then
  errands_to_change="${enabled_errands[@]}"
else
  errands_to_change=$(echo "$ERRANDS_TO_CHANGE" | tr ',' '\n')
fi

will_change=$(
  echo $enabled_errands |
  jq \
    --arg to_change "${errands_to_change[@]}" \
    --raw-input \
    --raw-output \
    'split(" ")
    | reduce .[] as $errand ([];
       if $to_change | contains($errand) then
         . + [$errand]
       else
         .
       end)
    | join("\n")'
)

if [ -z "$will_change" ]; then
  echo Nothing to do.
  exit 0
fi

while read errand; do
  echo -n Changing $errand...
  om-linux \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --skip-ssl-validation \
    --client-id "${OPSMAN_CLIENT_ID}" \
    --client-secret "${OPSMAN_CLIENT_SECRET}" \
    --username "$OPSMAN_USERNAME" \
    --password "$OPSMAN_PASSWORD" \
    set-errand-state \
    --product-name "$PRODUCT_NAME" \
    --errand-name $errand \
    --post-deploy-state "when-changed"
  echo done
done < <(echo "$will_change")
