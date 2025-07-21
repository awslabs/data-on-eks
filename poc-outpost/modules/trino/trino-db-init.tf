#---------------------------------------------------------------
# INIT DB RDS password for iceberg
#---------------------------------------------------------------
resource "kubectl_manifest" "iceberg_rds_db_init_password" {

  yaml_body = templatefile("${path.module}/helm-values/trino-init-db-secret.yaml", {
    trino_namespace = local.trino_namespace
    postgres_password = try(sensitive(aws_secretsmanager_secret_version.postgres.secret_string), "")
  })

  depends_on = [
    module.db,
    module.trino_addon
  ]
}

#---------------------------------------------------------------
# INIT DB RDS Tables for iceberg
#---------------------------------------------------------------
resource "kubectl_manifest" "iceberg_rds_db_init_table" {

yaml_body = templatefile("${path.module}/helm-values/trino-init-db.yaml", {
  trino_namespace = local.trino_namespace
  postgres_host = try(element(split(":", module.db.db_instance_endpoint), 0), "")
  postgres_db_name = try(module.db.db_instance_name, "")
  postgres_user = try(module.db.db_instance_name, "")

})

  lifecycle {
    replace_triggered_by = [
      null_resource.db_state_trigger
      ]
  }

  depends_on = [
    kubectl_manifest.iceberg_rds_db_init_password
  ]
}

resource "null_resource" "db_state_trigger" {
  triggers = {
    db_instance_endpoint = module.db.db_instance_endpoint
    db_instance_name    = module.db.db_instance_name
    trino_namespace = local.trino_namespace
    postgres_password = sensitive(aws_secretsmanager_secret_version.postgres.secret_string)
    db_init_yaml        = templatefile("${path.module}/helm-values/trino-init-db.yaml", {
      trino_namespace  = local.trino_namespace
      postgres_host    = try(element(split(":", module.db.db_instance_endpoint), 0), "")
      postgres_db_name = try(module.db.db_instance_name, "")
      postgres_user    = try(module.db.db_instance_name, "")
    })
  }
}