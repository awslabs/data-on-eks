name = "trino-v2"
region = "us-west-2"

# Enable only Trino
enable_trino = true
enable_trino_keda = true

# Disable all other components
enable_raydata = false
enable_datahub = false
enable_flink = false
enable_spark_operator = false
enable_spark_history_server = false
enable_kafka = false
enable_jupyterhub = false