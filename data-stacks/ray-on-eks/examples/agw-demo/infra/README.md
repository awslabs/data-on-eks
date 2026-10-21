# agw-demo infrastructure

AWS and Karpenter resources are Terraform in the ray-on-eks stack overlay and are
applied only by `data-stacks/ray-on-eks/deploy.sh` (never run terraform by hand).

| What | File |
|---|---|
| Feature flags | `data-stacks/ray-on-eks/terraform/data-stack.tfvars` (`enable_agentgateway`, `enable_agw_demo`). GPU workers and Valkey use the first two AZs of the cluster's region (fixed in `agw-demo.tf`) |
| ElastiCache Valkey, SG, Pod Identity, namespace, ServiceAccounts, Valkey Secret | `data-stacks/ray-on-eks/terraform/agw-demo.tf` |
| EC2NodeClasses `agw-demo-cpu`/`agw-demo-gpu`, NodePools `agw-demo-cpu`/`agw-demo-gpu-gemma`/`agw-demo-gpu-embed` | `data-stacks/ray-on-eks/terraform/manifests/agw-demo/karpenter/` |
| Gateway API CRDs v1.6.0, agentgateway 1.6.0 (ArgoCD) | `infra/terraform/agentgateway.tf`, `infra/terraform/argocd-applications/{gateway-api-crds,agentgateway-crds,agentgateway}.yaml`, `infra/terraform/helm-values/agentgateway.yaml` |

Why Terraform via deploy.sh: it is how this repo manages every AWS resource, it
keeps state (so cleanup is a flag flip), and it tags everything consistently
(`project=agw-demo`, `owner=vara`).

Remove all of it: set `enable_agw_demo = false` (and `enable_agentgateway = false`
if nothing else uses it), then run `./deploy.sh`.
