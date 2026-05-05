name   = "starrocks-on-eks"
region = "us-east-1"

# Core component
enable_starrocks = true

# Enable optional components if needed
enable_spark_operator       = false
enable_spark_history_server = false
enable_yunikorn             = false
enable_jupyterhub           = false
enable_raydata              = false
enable_flink                = false
enable_kafka                = false
enable_amazon_prometheus    = false
enable_superset             = false
enable_ingress_nginx        = false

# Unique ID used to tag all AWS resources for this deployment.
# Enables identification of orphaned resources and cleanup in case of Terraform state loss.
# Auto-generated on first deploy — do not edit manually.
deployment_id = "DO-NOT-EDIT-AUTO-GENERATED"
