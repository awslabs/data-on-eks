#!/bin/bash
# Create (or re-use) one API key per team. Keys are never printed.
#  - Secret agw-demo/agw-demo-team-keys: raw keys, mounted by demo clients
#  - ConfigMap agentgateway-system/agw-demo-api-keys: SHA-256 hashes + team
#    metadata, selected by the gateway's apiKeyAuthentication policy
# Re-running keeps existing keys (reads them back from the Secret).
set -euo pipefail
NS=agw-demo; GW_NS=agentgateway-system
tier_of() { case "$1" in team-labs) echo experimental ;; *) echo production ;; esac; }
SECRET_ARGS=(); CM_ARGS=()
for team in team-search team-support team-labs; do
  var=$(echo "$team" | tr 'a-z-' 'A-Z_')_KEY
  key=$(kubectl -n $NS get secret agw-demo-team-keys -o jsonpath="{.data.$var}" 2>/dev/null | base64 -d || true)
  [[ -n "$key" ]] || key="agw-${team#team-}-$(openssl rand -hex 16)"
  hash=$(printf '%s' "$key" | shasum -a 256 | awk '{print $1}')
  SECRET_ARGS+=(--from-literal="$var=$key")
  CM_ARGS+=(--from-literal="$team={\"keyHash\":\"sha256:$hash\",\"metadata\":{\"team\":\"$team\",\"tier\":\"$(tier_of "$team")\"}}")
done
kubectl -n $NS create secret generic agw-demo-team-keys "${SECRET_ARGS[@]}" \
  --dry-run=client -o yaml | kubectl label --local -f - project=agw-demo -o yaml | kubectl apply -f - >/dev/null
kubectl -n $GW_NS create configmap agw-demo-api-keys "${CM_ARGS[@]}" \
  --dry-run=client -o yaml | kubectl label --local -f - project=agw-demo agw-demo/apikeys=true -o yaml | kubectl apply -f - >/dev/null
echo "team keys ready: secret $NS/agw-demo-team-keys, configmap $GW_NS/agw-demo-api-keys (hashes only)"
