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
