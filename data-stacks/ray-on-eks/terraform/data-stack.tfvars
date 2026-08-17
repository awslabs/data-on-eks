name                 = "ray-on-eks"
region               = "us-west-2"
enable_ingress_nginx = true
enable_raydata       = true

# GPU support for Ray inference workloads (vLLM on g6e instances)
enable_nvidia_gpu_operator = true

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
