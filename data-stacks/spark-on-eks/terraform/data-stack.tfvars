# Checkout the docs for enabling more addons
# https://awslabs.github.io/data-on-eks/docs/datastacks/processing/spark-on-eks/infra

name                 = "spark-on-eks"
region               = "us-west-2"
enable_ingress_nginx = true
deployment_id        = "rOOMTbDP"
enable_celeborn      = false
enable_ipv6          = false
enable_nvidia_device_plugin = false # Enable this for Spark RAPIDS on GPUs example
