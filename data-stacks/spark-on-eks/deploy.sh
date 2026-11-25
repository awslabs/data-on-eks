#!/bin/bash

set -e
set -o pipefail

# Terraform runs directly in terraform/, with no copy to a _local folder.
# The state is in S3 (see the backend block in terraform/versions.tf).

# Relative paths must work from any directory.
cd "$(dirname "${BASH_SOURCE[0]}")"

TERRAFORM_DIR="terraform"
TFVARS_FILE="$TERRAFORM_DIR/data-stack.tfvars"
KUBECONFIG_FILE="kubeconfig.yaml"

# JSON object for `aws eks update-cluster-config --kube-api-server-config`.
# The default keeps Kubernetes events for 10 minutes. The EKS default is 1 hour.
# Example:
#   KUBE_API_SERVER_CONFIG='{"eventTtl":"30m","serviceNodePortRange":{"minPort":30000,"maxPort":32767}}' ./deploy.sh
# To skip this step, set it to empty: KUBE_API_SERVER_CONFIG='' ./deploy.sh
# Limits: eventTtl 10m-60m. minPort and maxPort 10260-32767, minPort <= maxPort.
DEFAULT_KUBE_API_SERVER_CONFIG='{"eventTtl":"10m"}'
KUBE_API_SERVER_CONFIG="${KUBE_API_SERVER_CONFIG-$DEFAULT_KUBE_API_SERVER_CONFIG}"

# Dry run (--dry-run or DRY_RUN=true) runs "terraform plan" and read-only checks only.
DRY_RUN="${DRY_RUN:-false}"

usage() {
    echo "Usage: $0 [--dry-run] [--help]"
    echo "  --dry-run  Show what the script would change. Make no changes."
    echo "             Exit code: 0 = no changes, 2 = changes are pending, 1 = error."
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

if [ "$DRY_RUN" != "true" ] && [ "$DRY_RUN" != "false" ]; then
    echo "DRY_RUN must be 'true' or 'false'. Current value: '$DRY_RUN'"
    exit 1
fi
export DRY_RUN

source "$TERRAFORM_DIR/install-helpers.sh"

if [ "$DRY_RUN" = "true" ]; then
    print_warning "DRY RUN: no changes will be made to AWS, Kubernetes, or local files."
fi

print_status "Starting deployment from: $(pwd)/$TERRAFORM_DIR"
check_prerequisites

# A local state file without an S3 backend means that the state is not migrated.
# Stop here, so that "init" does not ask about the migration during a deployment.
if [ -s "$TERRAFORM_DIR/terraform.tfstate" ] \
    && ! grep -q '"type": *"s3"' "$TERRAFORM_DIR/.terraform/terraform.tfstate" 2>/dev/null; then
    print_error "Local state $TERRAFORM_DIR/terraform.tfstate is not migrated to the S3 backend."
    print_error "Run this one time, and answer 'yes' to copy the state to S3:"
    print_error "  terraform -chdir=$TERRAFORM_DIR init -migrate-state"
    print_error "Then run: ./deploy.sh --dry-run"
    exit 1
fi

# cleanup.sh uses deployment_id to find AWS resources that Kubernetes operators leave behind.
if [ -f "$TFVARS_FILE" ]; then
    if grep -qE '^[[:space:]]*deployment_id[[:space:]]*=' "$TFVARS_FILE"; then
        if grep -qE '^[[:space:]]*deployment_id[[:space:]]*=[[:space:]]*"DO-NOT-EDIT-AUTO-GENERATED"' "$TFVARS_FILE"; then
            if [ "$DRY_RUN" = "true" ]; then
                print_warning "[DRY RUN] Would replace the default deployment_id in $TFVARS_FILE. No change made."
            else
                print_status "Default deployment_id found. Generating a new random one."
                RANDOM_ID=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 8)
                sed -i.bak -E "s/^([[:space:]]*deployment_id[[:space:]]*=[[:space:]]*)\"DO-NOT-EDIT-AUTO-GENERATED\"/\1\"$RANDOM_ID\"/" "$TFVARS_FILE" && rm -f "$TFVARS_FILE.bak"
                print_status "Updated deployment_id to $RANDOM_ID in $TFVARS_FILE"
            fi
        fi
    elif [ "$DRY_RUN" = "true" ]; then
        print_warning "[DRY RUN] Would add a deployment_id to $TFVARS_FILE. No change made."
    else
        print_status "No deployment_id found in $TFVARS_FILE. Adding one."
        RANDOM_ID=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 8)
        echo "" >> "$TFVARS_FILE"
        echo "deployment_id = \"$RANDOM_ID\"" >> "$TFVARS_FILE"
        print_status "Added deployment_id = $RANDOM_ID to $TFVARS_FILE"
    fi
else
    print_warning "$TFVARS_FILE not found. Skipping deployment_id update."
fi

if [ "$DRY_RUN" = "true" ]; then
    print_warning "[DRY RUN] Would run: helm registry logout public.ecr.aws"
else
    helm registry logout public.ecr.aws || true
fi

export TF_LOG=ERROR

# -var-file is relative to TERRAFORM_DIR, because -chdir changes the directory first.
TF_VAR_FILE_ARGS=()
if [ -f "$TFVARS_FILE" ]; then
    TF_VAR_FILE_ARGS=(-var-file=data-stack.tfvars)
fi

terraform_apply() {
    local label="$1"
    shift
    local log
    log=$(mktemp)

    print_status "Applying $label..."
    if terraform -chdir="$TERRAFORM_DIR" apply -auto-approve "${TF_VAR_FILE_ARGS[@]}" "$@" 2>&1 | tee "$log" \
        && grep -q "Apply complete" "$log"; then
        rm -f "$log"
        echo "SUCCESS: Terraform apply of $label completed successfully"
    else
        rm -f "$log"
        echo "FAILED: Terraform apply of $label failed"
        exit 1
    fi
}

print_status "Initializing Terraform..."
if [ "$DRY_RUN" = "true" ]; then
    # No -upgrade, and the lock file is read-only, so provider versions do not change.
    terraform -chdir="$TERRAFORM_DIR" init -input=false -lockfile=readonly
else
    # No -upgrade: versions change only on purpose.
    terraform -chdir="$TERRAFORM_DIR" init -input=false
fi

# Karpenter must be ready before the workloads. If not, wait=true workloads use all
# Terraform parallelism slots on pods that cannot schedule, and Karpenter never installs.
targets=(
    "module.vpc"
    "module.eks"
    "module.karpenter"
    "helm_release.karpenter"
    "kubectl_manifest.karpenter_resources"
    "kubectl_manifest.ec2nodeclass"
)

# Exit code of the dry run: 0 = no changes, 2 = changes are pending.
DRY_RUN_EXIT=0

if [ "$DRY_RUN" = "true" ]; then
    # One full plan shows the changes of all targeted applies and the final apply.
    print_status "[DRY RUN] Running terraform plan for all resources..."
    plan_rc=0
    terraform -chdir="$TERRAFORM_DIR" plan -input=false -detailed-exitcode "${TF_VAR_FILE_ARGS[@]}" || plan_rc=$?
    case "$plan_rc" in
        0) print_status "[DRY RUN] Terraform: no changes." ;;
        2) print_warning "[DRY RUN] Terraform: changes are pending. See the plan above."; DRY_RUN_EXIT=2 ;;
        *) print_error "[DRY RUN] terraform plan failed (exit code $plan_rc)."; exit 1 ;;
    esac
else
    for target in "${targets[@]}"; do
        terraform_apply "$target" -target="$target"
    done

    terraform_apply "all modules"

    print_status "Terraform deployment finished successfully."
fi

print_status "Running stack-specific post-deployment steps..."

# "state pull" reads the state from the S3 backend.
if [ "$DRY_RUN" = "true" ]; then
    print_warning "[DRY RUN] Would save a copy of the remote state to $TERRAFORM_DIR/terraform.tfstate.bak"
else
    terraform -chdir="$TERRAFORM_DIR" state pull > "$TERRAFORM_DIR/terraform.tfstate.bak.tmp"
    mv "$TERRAFORM_DIR/terraform.tfstate.bak.tmp" "$TERRAFORM_DIR/terraform.tfstate.bak"
    print_status "Saved a copy of the remote state to $TERRAFORM_DIR/terraform.tfstate.bak."
fi

# The terraform-aws-modules/eks module does not support kube_api_server_config yet.
# Remove this function when the module supports it.
# Terraform does not track this setting. An empty value does not reset the cluster.
apply_kube_api_server_config() {
    if [ -z "$KUBE_API_SERVER_CONFIG" ]; then
        print_status "KUBE_API_SERVER_CONFIG is empty. Skipping API server configuration."
        return 0
    fi

    command -v jq >/dev/null 2>&1 || { print_error "jq is required to apply KUBE_API_SERVER_CONFIG."; exit 1; }

    local requested
    requested=$(jq -ce 'select(type == "object")' <<< "$KUBE_API_SERVER_CONFIG" 2>/dev/null) \
        || { print_error "KUBE_API_SERVER_CONFIG must be a JSON object."; exit 1; }

    local cluster_name region
    if [ "$DRY_RUN" = "true" ]; then
        # On a new deployment, the cluster and the outputs do not exist yet.
        cluster_name=$(terraform -chdir="$TERRAFORM_DIR" output -raw cluster_name 2>/dev/null || true)
        region=$(terraform -chdir="$TERRAFORM_DIR" output -raw region 2>/dev/null || true)
        if [ -z "$cluster_name" ] || [ -z "$region" ] \
            || ! aws eks describe-cluster --name "$cluster_name" --region "$region" >/dev/null 2>&1; then
            print_warning "[DRY RUN] Cluster not found. Would set API server configuration after create: $requested"
            DRY_RUN_EXIT=2
            return 0
        fi
    else
        cluster_name=$(terraform -chdir="$TERRAFORM_DIR" output -raw cluster_name)
        region=$(terraform -chdir="$TERRAFORM_DIR" output -raw region)
    fi

    # EKS allows one cluster update at a time.
    aws eks wait cluster-active --name "$cluster_name" --region "$region"

    # EKS can reject an update that changes nothing.
    local current
    current=$(aws eks describe-cluster --name "$cluster_name" --region "$region" \
        --query 'cluster.kubeApiServerConfig' --output json)
    if jq -ne --argjson cur "$current" --argjson req "$requested" \
        '[$req | paths(scalars)] | all(. as $p | ($cur | getpath($p)) == ($req | getpath($p)))' >/dev/null; then
        print_status "API server configuration is already set on $cluster_name. Skipping update."
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "[DRY RUN] Would update API server configuration on $cluster_name."
        print_warning "[DRY RUN]   Current:   $(jq -c . <<< "$current")"
        print_warning "[DRY RUN]   Requested: $requested"
        DRY_RUN_EXIT=2
        return 0
    fi

    print_status "Updating API server configuration on $cluster_name: $requested"
    local update_id
    update_id=$(aws eks update-cluster-config --name "$cluster_name" --region "$region" \
        --kube-api-server-config "$requested" --query 'update.id' --output text)

    local status attempt
    for attempt in $(seq 1 60); do
        status=$(aws eks describe-update --name "$cluster_name" --region "$region" \
            --update-id "$update_id" --query 'update.status' --output text)
        case "$status" in
            Successful)
                print_status "API server configuration update $update_id is complete."
                return 0
                ;;
            Failed|Cancelled)
                print_error "API server configuration update $update_id status: $status"
                aws eks describe-update --name "$cluster_name" --region "$region" \
                    --update-id "$update_id" --query 'update.errors' --output json
                exit 1
                ;;
        esac
        print_status "Update $update_id status: $status (check $attempt/60)"
        sleep 20
    done

    print_error "API server configuration update $update_id did not finish in 20 minutes."
    exit 1
}

apply_kube_api_server_config

if [ "$DRY_RUN" = "true" ]; then
    print_warning "[DRY RUN] Would write $KUBECONFIG_FILE and add a refresh annotation to all ArgoCD applications."
    if [ "$DRY_RUN_EXIT" -eq 0 ]; then
        print_status "[DRY RUN] Complete. No changes are pending."
    else
        print_warning "[DRY RUN] Complete. Changes are pending. See the messages above."
    fi
    exit "$DRY_RUN_EXIT"
fi

setup_kubeconfig
refresh_argocd_apps

export KUBECONFIG=$KUBECONFIG_FILE
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

print_next_steps
