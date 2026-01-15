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
| Name | Name to be used on all the resources as identifier | `name` | `string` | `data-on-eks` |
| Region | AWS region | `region` | `string` | `us-west-2` |
| Tags | A map of tags to add to all resources | `tags` | `string` | `{}` |

---

### Core Infrastructure (Always Enabled)

These components are deployed by default in all data stacks:

| Component | Description | Variable | Status |
|-----------|-------------|----------|--------|
| AWS Load Balancer Controller | AWS ALB/NLB integration | N/A | ✅ |
| Argo Events | Event-driven workflow automation | N/A | ✅ |
| Argo Workflows | Workflow engine for Kubernetes | N/A | ✅ |
| ArgoCD | GitOps continuous delivery | N/A | ✅ |
| Cert Manager | TLS certificate management | N/A | ✅ |
| Fluent Bit | Log forwarding to CloudWatch | N/A | ✅ |
| Karpenter | Node autoscaling and provisioning | N/A | ✅ |
| Kube Prometheus Stack | Prometheus and Grafana monitoring | N/A | ✅ |
| Spark History Server | Spark job history and metrics | N/A | ✅ |
| Spark Operator | Apache Spark job orchestration | N/A | ✅ |
| YuniKorn | Advanced batch scheduling | N/A | ✅ |

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
| Airflow | Enable Apache Airflow for workflow orchestration | `enable_airflow` | ❌ |
| Amazon Prometheus | Enable AWS Managed Prometheus service | `enable_amazon_prometheus` | ❌ |
| Celeborn | Enable Apache Celeborn for remote shuffling service | `enable_celeborn` | ❌ |
| Cluster Addons | A map of EKS addon names to boolean values that control whether each addon is enabled. This allows fine-grained control over which addons are deployed by this Terraform stack. To enable or disable an addon, set its value to `true` or `false` in your blueprint.tfvars file. If you need to add a new addon, update this variable definition and also adjust the logic in the EKS module (e.g., in eks.tf locals) to include any custom configuration needed. | `enable_cluster_addons` | ❌ |
| Datahub | Enable DataHub for metadata management | `enable_datahub` | ❌ |
| Ingress Nginx | Enable ingress-nginx | `enable_ingress_nginx` | ✅ |
| Ipv6 | Enable IPv6 for the EKS cluster and its components | `enable_ipv6` | ❌ |
| Jupyterhub | Enable Jupyter Hub | `enable_jupyterhub` | ✅ |
| Nvidia Device Plugin | Enable NVIDIA Device plugin addon for GPU workloads | `enable_nvidia_device_plugin` | ❌ |
| Raydata | Enable Ray Data via ArgoCD | `enable_raydata` | ❌ |
| Superset | Enable Apache Superset for data exploration and visualization | `enable_superset` | ❌ |

---

### EKS Cluster Addons

Fine-grained control over EKS addons via the `enable_cluster_addons` map variable:

| Addon | Description | Variable | Default |
|-------|-------------|----------|---------|
| Amazon Cloudwatch Observability | Amazon CloudWatch observability | `enable_cluster_addons["amazon-cloudwatch-observability"]` | ❌ |
| Aws Ebs Csi Driver | Amazon EBS CSI driver for persistent volumes | `enable_cluster_addons["aws-ebs-csi-driver"]` | ✅ |
| Aws Mountpoint S3 Csi Driver | Mountpoint for Amazon S3 CSI driver | `enable_cluster_addons["aws-mountpoint-s3-csi-driver"]` | ✅ |
| Eks Node Monitoring Agent | EKS node monitoring agent | `enable_cluster_addons["eks-node-monitoring-agent"]` | ✅ |
| Metrics Server | Kubernetes metrics server for autoscaling | `enable_cluster_addons["metrics-server"]` | ✅ |

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
