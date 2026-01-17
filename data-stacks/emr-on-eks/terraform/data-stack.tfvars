# EMR on EKS Data Stack Configuration
# This file enables EMR on EKS Virtual Clusters for running Spark jobs

name                 = "emr-on-eks"
region               = "us-west-2"
deployment_id        = "abcdefg"

# Enable EMR on EKS Virtual Clusters
enable_emr_on_eks    = true

# Optional: Enable additional addons as needed
enable_ingress_nginx = true
enable_ipv6          = false
