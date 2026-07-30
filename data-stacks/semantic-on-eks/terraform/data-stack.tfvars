name   = "semantic-on-eks"
region = "us-west-2"

# ---------------------------------------------------------------------------
# semantic-on-eks
#
# Foundation stack for the Apache Ossie / Open Semantic Interchange (OSI)
# semantic-operator demos and testing. Provides the query engine (Trino), an
# Iceberg REST catalog (Apache Polaris), a metadata catalog (DataHub), and an
# optional result cache (Valkey) that the datahub-polaris-trino example expects
# to already exist.
#
# All services are ClusterIP only — reach them with `kubectl port-forward`.
# ---------------------------------------------------------------------------

# Core components for the semantic-operator example.
# Trino is always deployed by the base infra (no enable flag) with a
# Glue-backed 'iceberg' catalog; enable_polaris adds the 'polaris' REST catalog.
enable_polaris = true
enable_datahub = true
enable_valkey  = true

# Optional components — off for this stack.
enable_starrocks         = false
enable_jupyterhub        = false
enable_raydata           = false
enable_amazon_prometheus = false
enable_superset          = false
enable_pinot             = false
enable_airflow           = false
enable_celeborn          = false
enable_ingress_nginx     = false

# Unique ID used to tag all AWS resources for this deployment.
# Enables identification of orphaned resources and cleanup in case of Terraform state loss.
# Auto-generated on first deploy — do not edit manually.
deployment_id = "DO-NOT-EDIT-AUTO-GENERATED"
