# To enable more add-ons, refer to
# https://awslabs.github.io/data-on-eks/docs/datastacks/processing/spark-on-eks/infra

name                = "spark-on-eks"
region              = "us-east-1"
eks_cluster_version = "1.37"
# This ID is on the tags of all AWS resources of this deployment. It helps you find
# orphaned resources after Terraform state loss. The first deploy writes it. Do not change it.
deployment_id              = "rOOMTbDP"
enable_celeborn            = false
enable_ipv6                = true
enable_jupyterhub          = false
enable_yunikorn            = false # The EKS scheduler must place the test pods.
enable_nvidia_gpu_operator = false # Set to true for the Spark RAPIDS GPU example.

# For the tier limits, refer to the eks_pcp_tier description in variables.tf.
eks_pcp_tier = "8XL"
