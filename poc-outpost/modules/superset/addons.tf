

module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.31.5" # ensure to update this to the latest/desired version

  oidc_provider_arn = local.oidc_provider_arn

  #---------------------------------------
  # AWS Apache Superset Add-on
  #---------------------------------------
  enable_superset = true
  superset_helm_config = {
    values = [
      templatefile("${path.module}/helm-values/superset-values.yaml", {

        db_user = local.superset_name
        db_pass = try(sensitive(aws_secretsmanager_secret_version.postgres.secret_string), "")
        db_name = try(module.db.db_instance_name, "")
        db_host = try(element(split(":", module.db.db_instance_endpoint), 0), "")

        redis_user = local.superset_name
        redis_host = try(module.elasticache.cluster_cache_nodes[0].address, "failed")

      })
    ]
  }
}

#---------------------------------------------------------------
# Spark history server Virtual Service qui remplace l'Ingress
#---------------------------------------------------------------

module "virtual_service" {
  source = "../virtualService"

  cluster_issuer_name = local.cluster_issuer_name
  virtual_service_name = local.superset_name
  dns_name = "${local.superset_name}.${local.main_domain}"
  service_name = "superset"
  service_port = 8088
  namespace = local.superset_namespace

  tags = local.tags

  depends_on = [module.eks_data_addons]
}
