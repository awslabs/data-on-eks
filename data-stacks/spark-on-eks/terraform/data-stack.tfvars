# Checkout the docs for enabling more addons
# https://awslabs.github.io/data-on-eks/docs/datastacks/processing/spark-on-eks/infra

name                        = "spark-on-eks"
region                      = "us-west-2"
enable_ingress_nginx        = true
deployment_id               = "rOOMTbDP"
enable_celeborn             = false
enable_ipv6                 = false
enable_nvidia_device_plugin = false # Enable this for Spark RAPIDS on GPUs example

# EKS Provisioned Control Plane (PCP) Tier for high-scale benchmarking
# Tier Limits (EKS v1.30+):
#   XL  : 1700 API concurrency seats  | 167 pods/sec scheduling rate | 16 GB etcd
#   2XL : 3400 API concurrency seats  | 283 pods/sec scheduling rate | 16 GB etcd
#   4XL : 6800 API concurrency seats  | 400 pods/sec scheduling rate | 16 GB etcd
#   8XL : 13600 API concurrency seats | 400 pods/sec scheduling rate | 16 GB etcd
# eks_pcp_tier = "4XL"
