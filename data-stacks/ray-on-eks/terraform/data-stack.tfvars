name                 = "ray-on-eks"
region               = "us-west-2"
enable_ingress_nginx = true
enable_raydata       = true

# GPU support for Ray inference workloads (vLLM on g6e instances)
enable_nvidia_gpu_operator = true

# Observability
# - ADOT collector: Ray/node/KSM/GPU metrics -> Amazon Managed Prometheus, OTLP traces -> X-Ray
# - Amazon Managed Grafana: dashboards on AMP/X-Ray (needs IAM Identity Center)
# - KubeRay History Server: Ray Dashboard for deleted RayClusters/RayJobs, backed by S3
enable_amazon_prometheus      = true
enable_amazon_managed_grafana = true
enable_adot                   = true
enable_ray_history_server     = true

# IAM Identity Center users/groups assigned as Admin on the Grafana workspace
# aws identitystore list-users --identity-store-id $(aws sso-admin list-instances --query 'Instances[0].IdentityStoreId' --output text)
amg_admin_user_ids = ["FILL-IN-USER-IDS"]

# Unique ID used to tag all AWS resources for this deployment.
# Enables identification of orphaned resources and cleanup in case of Terraform state loss.
# Auto-generated on first deploy — do not edit manually.
deployment_id = "DO-NOT-EDIT-AUTO-GENERATED"

# EKS Provisioned Control Plane (PCP) Tier for high-scale benchmarking
# Tier Limits (EKS v1.30+):
#   XL  : 1700 API concurrency seats  | 167 pods/sec scheduling rate | 16 GB etcd
#   2XL : 3400 API concurrency seats  | 283 pods/sec scheduling rate | 16 GB etcd
#   4XL : 6800 API concurrency seats  | 400 pods/sec scheduling rate | 16 GB etcd
#   8XL : 13600 API concurrency seats | 400 pods/sec scheduling rate | 16 GB etcd
eks_pcp_tier = "2XL"
