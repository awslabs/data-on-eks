name   = "trino-v2"
region = "us-west-2"

# Enable all components for full stack deployment
enable_trino                = true
enable_trino_keda           = true
enable_spark_operator       = true
enable_spark_history_server = true
enable_yunikorn             = true
enable_jupyterhub           = true
enable_raydata              = true
enable_flink                = true
enable_kafka                = true
enable_amazon_prometheus    = true
enable_superset             = true
enable_ingress_nginx        = true
