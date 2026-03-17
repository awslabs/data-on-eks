# EMR on EKS Data Stack Configuration
# This file enables EMR on EKS Virtual Clusters for running Spark jobs

name          = "emr-on-eks"
region        = "us-west-2"
deployment_id = "abcdefg"

# Enable EMR on EKS Virtual Clusters
enable_emr_on_eks = true

# Enable EMR Spark Operator for declarative Spark job management
enable_emr_spark_operator = true

# Optional: Enable additional addons as needed
enable_ingress_nginx = true
enable_ipv6          = false

# EKS Provisioned Control Plane (PCP) Tier for high-scale benchmarking
# Tier Limits (EKS v1.30+):
#   XL  : 1700 API concurrency seats  | 167 pods/sec scheduling rate | 16 GB etcd
#   2XL : 3400 API concurrency seats  | 283 pods/sec scheduling rate | 16 GB etcd
#   4XL : 6800 API concurrency seats  | 400 pods/sec scheduling rate | 16 GB etcd
#   8XL : 13600 API concurrency seats | 400 pods/sec scheduling rate | 16 GB etcd
# eks_pcp_tier = "4XL"

enable_cluster_addons = {
  aws-ebs-csi-driver              = true
  aws-mountpoint-s3-csi-driver    = true
  metrics-server                  = true
  eks-node-monitoring-agent       = true
  amazon-cloudwatch-observability = true
}
