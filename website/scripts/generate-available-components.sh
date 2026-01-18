#!/bin/bash
# Generate available-components.md from Terraform source code
# This script parses infra/terraform/variables.tf to extract all enable_* variables
# and generates documentation at website/docs/datastacks/available-components.md
#
# Usage: ./website/scripts/generate-available-components.sh
#
# The generated documentation helps users discover what components are available
# in Data on EKS and how to enable them in their data stacks.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
TERRAFORM_DIR="$REPO_ROOT/infra/terraform"
OUTPUT_FILE="$REPO_ROOT/website/docs/datastacks/available-components.md"

# Extract enable_* variables from variables.tf
parse_variables() {
    awk '
    /^variable "enable_/ {
        var_name = $2
        gsub(/"/, "", var_name)
        in_var = 1
        description = ""
        default_val = ""
        next
    }

    in_var && /description/ {
        # Extract description text between quotes
        match($0, /description[[:space:]]*=[[:space:]]*"([^"]*)"/, arr)
        if (arr[1]) {
            description = arr[1]
        } else {
            # Handle multi-line descriptions with <<DESC
            getline
            while ($0 !~ /DESC$/ && $0 !~ /^[[:space:]]*}/) {
                if (description) description = description " "
                gsub(/^[[:space:]]+/, "", $0)
                description = description $0
                getline
            }
        }
    }

    in_var && /default[[:space:]]*=/ {
        if ($0 ~ /true/) default_val = "true"
        else if ($0 ~ /false/) default_val = "false"
    }

    in_var && /^}/ {
        if (var_name && description) {
            # Clean up description
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", description)
            # Extract component name from variable
            component = var_name
            gsub(/^enable_/, "", component)
            gsub(/_/, " ", component)
            # Capitalize first letter of each word
            cmd = "echo \"" component "\" | awk '"'"'{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1'"'"'"
            cmd | getline component
            close(cmd)

            default_icon = (default_val == "true") ? "✅" : "❌"

            print component "|" description "|" var_name "|" default_icon
        }
        in_var = 0
        var_name = ""
        description = ""
        default_val = ""
    }
    ' "$TERRAFORM_DIR/variables.tf"
}

# Parse core variables (name, region, tags)
parse_core_variables() {
    awk '
    /^variable "(name|region|tags)"/ {
        var_name = $2
        gsub(/"/, "", var_name)
        in_var = 1
        description = ""
        default_val = ""
        var_type = ""
        next
    }

    in_var && /description/ {
        match($0, /description[[:space:]]*=[[:space:]]*"([^"]*)"/, arr)
        if (arr[1]) {
            description = arr[1]
        }
    }

    in_var && /type[[:space:]]*=/ {
        if ($0 ~ /string/) var_type = "string"
        else if ($0 ~ /map/) var_type = "map(string)"
    }

    in_var && /default[[:space:]]*=/ {
        # Extract default value
        if ($0 ~ /"[^"]*"/) {
            match($0, /"([^"]*)"/, arr)
            default_val = arr[1]
        } else if ($0 ~ /{}/) {
            default_val = "{}"
        }
    }

    in_var && /^}/ {
        if (var_name && description) {
            # Capitalize variable name for display
            display_name = var_name
            cmd = "echo \"" display_name "\" | awk '"'"'{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1'"'"'"
            cmd | getline display_name
            close(cmd)

            if (default_val == "") default_val = "(none)"

            print display_name "|" description "|" var_name "|" var_type "|" default_val
        }
        in_var = 0
        var_name = ""
        description = ""
        default_val = ""
        var_type = ""
    }
    ' "$TERRAFORM_DIR/variables.tf"
}

# Parse enable_cluster_addons map
parse_cluster_addons() {
    awk '
    /^variable "enable_cluster_addons"/ {
        in_addons = 1
        next
    }

    in_addons && /default[[:space:]]*=/ {
        in_default = 1
        next
    }

    in_default && /^[[:space:]]*}[[:space:]]*$/ {
        in_default = 0
        in_addons = 0
    }

    in_default && /=/ {
        # Parse addon lines like: aws-ebs-csi-driver = true
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        split($0, parts, "=")
        addon = parts[1]
        value = parts[2]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", addon)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)

        # Clean up addon name for display
        display_name = addon
        gsub(/-/, " ", display_name)
        cmd = "echo \"" display_name "\" | awk '"'"'{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1'"'"'"
        cmd | getline display_name
        close(cmd)

        default_icon = (value == "true") ? "✅" : "❌"

        # Generate descriptions
        if (addon ~ /ebs/) desc = "Amazon EBS CSI driver for persistent volumes"
        else if (addon ~ /mountpoint/) desc = "Mountpoint for Amazon S3 CSI driver"
        else if (addon ~ /metrics-server/) desc = "Kubernetes metrics server for autoscaling"
        else if (addon ~ /monitoring/) desc = "EKS node monitoring agent"
        else if (addon ~ /cloudwatch/) desc = "Amazon CloudWatch observability"
        else desc = "EKS cluster addon"

        print display_name "|" desc "|enable_cluster_addons[\"" addon "\"]|" default_icon
    }
    ' "$TERRAFORM_DIR/variables.tf"
}

# Identify always-enabled components (no enable_ variable)
get_always_enabled() {
    cat <<EOF
Karpenter|Node autoscaling and provisioning|✅
Spark Operator|Apache Spark job orchestration|✅
ArgoCD|GitOps continuous delivery|✅
Cert Manager|TLS certificate management|✅
AWS Load Balancer Controller|AWS ALB/NLB integration|✅
Fluent Bit|Log forwarding to CloudWatch|✅
Kube Prometheus Stack|Prometheus and Grafana monitoring|✅
Spark History Server|Spark job history and metrics|✅
YuniKorn|Advanced batch scheduling|✅
Argo Workflows|Workflow engine for Kubernetes|✅
Argo Events|Event-driven workflow automation|✅
EOF
}

# Generate markdown file
generate_markdown() {
    cat > "$OUTPUT_FILE" <<'HEADER'
---
title: Customizing Your Stack
sidebar_position: 8
---

## Customizing Your Stack

After deploying a data stack, you can customize it by enabling additional components or adding new ones.

:::tip Start with Defaults First
If you haven't deployed a stack yet, start with one of the pre-configured [data stacks](/docs/datastacks/) using default settings. Once running, return here to customize.
:::

:::info About Components
- **Core Infrastructure**: Always deployed - provides foundational capabilities like autoscaling, monitoring, and GitOps
- **Optional Components**: Enable on-demand via Terraform variables
- **Custom Components**: Add your own via ArgoCD for experimentation
:::

---

### Core Configuration Variables

These variables configure the basic infrastructure settings:

| Variable | Description | Terraform Variable | Type | Default |
|----------|-------------|-------------------|------|---------|
HEADER

    parse_core_variables | while IFS='|' read -r name desc var type default; do
        echo "| $name | $desc | \`$var\` | \`$type\` | \`$default\` |"
    done >> "$OUTPUT_FILE"

    cat >> "$OUTPUT_FILE" <<'CORE_INFRA_HEADER'

---

### Core Infrastructure (Always Enabled)

These components are deployed by default in all data stacks:

| Component | Description | Variable | Status |
|-----------|-------------|----------|--------|
CORE_INFRA_HEADER

    get_always_enabled | sort | while IFS='|' read -r component desc status; do
        echo "| $component | $desc | N/A | $status |"
    done >> "$OUTPUT_FILE"

    cat >> "$OUTPUT_FILE" <<'OPTIONAL_HEADER'

---

### Optional Components

These components can be enabled by setting their corresponding Terraform variable.

#### How to Enable

1. Edit your stack's `terraform/data-stack.tfvars` file
2. Set the corresponding `enable_*` variable to `true`
3. Redeploy: `./deploy.sh`

Example:
```hcl
name   = "my-data-platform"
region = "us-east-1"

enable_datahub  = true
enable_superset = true
```

#### Available Optional Components

| Component | Description | Variable | Default |
|-----------|-------------|----------|---------|
OPTIONAL_HEADER

    parse_variables | sort | while IFS='|' read -r component desc variable default; do
        echo "| $component | $desc | \`$variable\` | $default |"
    done >> "$OUTPUT_FILE"

    cat >> "$OUTPUT_FILE" <<'ADDONS_HEADER'

---

### EKS Cluster Addons

Fine-grained control over EKS addons via the `enable_cluster_addons` map variable:

| Addon | Description | Variable | Default |
|-------|-------------|----------|---------|
ADDONS_HEADER

    parse_cluster_addons | sort | while IFS='|' read -r addon desc variable default; do
        echo "| $addon | $desc | \`$variable\` | $default |"
    done >> "$OUTPUT_FILE"

    cat >> "$OUTPUT_FILE" <<'FOOTER'

---

### Adding New Components

After deploying a data stack, you can add additional components for experimentation.

#### Quick Method: Deploy via ArgoCD

The fastest way to add a new component:

1. Create an ArgoCD Application manifest
2. Apply it: `kubectl apply -f my-component.yaml`
3. Monitor: `kubectl get application my-component -n argocd`

**Example: Adding Kro (Kubernetes Resource Orchestrator)**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kro
  namespace: argocd
spec:
  project: default
  source:
    repoURL: oci://registry.k8s.io/kro/charts
    chart: kro
    targetRevision: 0.7.1
  destination:
    server: https://kubernetes.default.svc
    namespace: kro-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Apply the manifest:
```bash
kubectl apply -f kro-app.yaml
```

Verify deployment:
```bash
kubectl get application kro -n argocd
kubectl get pods -n kro-system
```

Clean up when done:
```bash
kubectl delete application kro -n argocd
```

#### Advanced: Integrate into Stack (Optional)

If you want the component managed by Terraform for reproducible deployments:

1. Create overlay files in your stack's `terraform/` directory:
   - `terraform/kro.tf` - Terraform resource definitions
   - `terraform/argocd-applications/kro.yaml` - ArgoCD app manifest
   - `terraform/helm-values/kro.yaml` - Helm values (if needed)

2. Redeploy your stack: `./deploy.sh`

This approach is useful if you're building a reusable stack for your team. See the [Contributing Guide](./contributing.md) for detailed instructions.

---

**Note**: This page is auto-generated from Terraform source code. To update, run:
```bash
./website/scripts/generate-available-components.sh
```
FOOTER
}

# Main execution
echo "Generating available components documentation..."
generate_markdown
echo "✅ Generated: $OUTPUT_FILE"
