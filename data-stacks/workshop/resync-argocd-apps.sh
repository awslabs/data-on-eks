#!/bin/bash

set -e

# --- Configuration ---
ARGOCD_SERVER="${ARGOCD_SERVER:-https://localhost:8081}"
ARGOCD_TOKEN="${ARGOCD_TOKEN:-}"
KUBECONFIG_FILE="$(dirname "$0")/kubeconfig"
TERRAFORM_DIR="$(dirname "$0")/terraform"
port_forward_pid=""

# --- Default options ---
TERMINATE_ONLY=false

# --- Usage message ---
usage() {
    echo "Usage: $0 [--terminate-only]"
    echo "  --terminate-only: Only terminate running syncs, do not re-sync."
}

# --- Parse command-line arguments ---
for arg in "$@"; do
  case $arg in
    --terminate-only)
      TERMINATE_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

# --- Cleanup on exit ---
cleanup() {
    echo "[INFO] Cleaning up..."
    if [ -n "$port_forward_pid" ]; then
        kill "$port_forward_pid" > /dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# --- Helper Functions ---

setup_kubeconfig() {
    echo "[INFO] Setting up kubeconfig..."
    
    local cluster_name
    cluster_name=$(terraform -chdir="$TERRAFORM_DIR/_local" output -raw cluster_name)
    
    if [ -z "$cluster_name" ]; then
        echo "[ERROR] Could not get cluster name from terraform output."
        exit 1
    fi
    
    echo "[INFO] Found cluster: $cluster_name"
    
    aws eks update-kubeconfig --name "$cluster_name" --region "${AWS_REGION:-us-east-1}" --kubeconfig "$KUBECONFIG_FILE"
    export KUBECONFIG="$KUBECONFIG_FILE"
    
    echo "[INFO] Kubeconfig created at $KUBECONFIG_FILE"
}

start_port_forward() {
    echo "[INFO] Checking ArgoCD server pod status..."
    if ! kubectl -n argocd get pod -l app.kubernetes.io/name=argocd-server | grep -q "Running"; then
        echo "[ERROR] ArgoCD server pod is not in a running state."
        kubectl -n argocd get pods
        exit 1
    fi

    echo "[INFO] Starting port-forward to ArgoCD server"
    kubectl port-forward svc/argocd-server -n argocd 8081:443 2>&1 &
    port_forward_pid=$!

    echo "[INFO] Waiting for port-forward to be ready (up to 30 seconds)..."
    for ((i=0; i<30; i++)); do
        if curl -sSk "$ARGOCD_SERVER/healthz" | grep -q 'ok'; then
            echo "[INFO] Port-forward is ready."
            return
        fi
        sleep 1
    done

    echo "[ERROR] Timeout waiting for port-forward to be ready."
    exit 1
}

prompt_for_config() {
    if [ -z "$ARGOCD_TOKEN" ]; then
        echo "[INFO] Getting ArgoCD admin password from Kubernetes secret..."
        local argocd_password
        argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
        
        if [ -z "$argocd_password" ]; then
            echo "[ERROR] Could not get ArgoCD admin password."
            exit 1
        fi

        echo "[INFO] Obtaining ArgoCD auth token..."
        local response
        response=$(curl -sS -k -X POST -H "Content-Type: application/json" -d '{"username":"admin","password":"'"$argocd_password"'"}' "$ARGOCD_SERVER/api/v1/session")
        
        ARGOCD_TOKEN=$(echo "$response" | jq -r .token)

        if [ -z "$ARGOCD_TOKEN" ] || [ "$ARGOCD_TOKEN" == "null" ]; then
            echo "[ERROR] Could not obtain ArgoCD auth token."
            exit 1
        fi
    fi
}

# --- API Functions ---

get_all_app_names() {
    local response
    response=$(curl -s -k -H "Authorization: Bearer $ARGOCD_TOKEN" "$ARGOCD_SERVER/api/v1/applications")
    
    if echo "$response" | jq -e '.items' > /dev/null; then
        echo "$response" | jq -r '.items[].metadata.name'
    else
        echo "[ERROR] Could not retrieve applications. Please check your ArgoCD server URL and token."
        exit 1
    fi
}

terminate_app_sync() {
    local app_name=$1
    echo "[INFO] Terminating sync for application: $app_name"
    curl -k -X DELETE -H "Authorization: Bearer $ARGOCD_TOKEN"  -H "Content-Type: application/json" "$ARGOCD_SERVER/api/v1/applications/$app_name/operation"
}

is_app_syncing() {
    local app_name=$1
    local response
    response=$(curl -sS -k -H "Authorization: Bearer $ARGOCD_TOKEN" "$ARGOCD_SERVER/api/v1/applications/$app_name")
    
    local phase
    phase=$(echo "$response" | jq -r '.status.operationState.phase // "Succeeded"')
    
    if [ "$phase" == "Running" ]; then
        return 0 # 0 is true in bash
    else
        return 1 # 1 is false in bash
    fi
}

sync_app() {
    local app_name=$1
    echo "[INFO] Triggering sync for application: $app_name"
    curl -sS -k -X POST -H "Authorization: Bearer $ARGOCD_TOKEN" -H "Content-Type: application/json" --data '{}' "$ARGOCD_SERVER/api/v1/applications/$app_name/sync" > /dev/null
}

# --- Main Logic ---
main() {
    setup_kubeconfig
    start_port_forward
    prompt_for_config

    echo "[INFO] Getting all ArgoCD applications..."
    local app_names
    app_names=$(get_all_app_names)

    if [ -z "$app_names" ]; then
        echo "[WARN] No applications found."
        exit 0
    fi

    echo "[INFO] --- Step 1: Terminating all sync operations ---"
    for app in $app_names; do
        terminate_app_sync "$app"
    done

    echo "[INFO] --- Step 2: Waiting for sync operations to terminate ---"
    local all_terminated=false
    for ((i=0; i<30; i++)); do
        all_terminated=true
        local syncing_apps=""
        for app in $app_names; do
            if is_app_syncing "$app"; then
                all_terminated=false
                syncing_apps="$syncing_apps $app"
            fi
        done

        if $all_terminated; then
            echo "[INFO] All sync operations have been terminated."
            break
        else
            echo "[INFO] Waiting for applications to terminate sync:$syncing_apps"
            sleep 5
        fi
    done

    if ! $all_terminated; then
        echo "[ERROR] Timeout waiting for sync operations to terminate."
        exit 1
    fi

    if [ "$TERMINATE_ONLY" = true ]; then
        echo "[INFO] --terminate-only flag is set. Skipping sync."
        exit 0
    fi

    echo "[INFO] --- Step 3: Syncing all applications ---"
    for app in $app_names; do
        sync_app "$app"
    done

    echo "[INFO] All applications have been queued for sync."
}

main