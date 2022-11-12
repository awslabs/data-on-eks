#---------------------------------------------------------------
# Kubernetes Add-ons
#---------------------------------------------------------------
module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.15.0"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  # EKS Addons
  enable_amazon_eks_vpc_cni    = true
  enable_amazon_eks_coredns    = true
  enable_amazon_eks_kube_proxy = true

  enable_metrics_server                = true
  enable_cluster_autoscaler            = true
  enable_amazon_eks_aws_ebs_csi_driver = true
  enable_aws_efs_csi_driver            = true
  enable_aws_for_fluentbit             = true
  enable_aws_load_balancer_controller  = true
  enable_prometheus                    = true

  # Apache Airflow add-on with custom helm config
  enable_airflow = true
  airflow_helm_config = {
    name             = local.airflow_name
    chart            = local.airflow_name
    repository       = "https://airflow.apache.org"
    version          = "1.6.0"
    namespace        = module.airflow_irsa.namespace
    create_namespace = false
    timeout          = 360
    wait             = false # This is critical setting. Check this issue -> https://github.com/hashicorp/terraform-provider-helm/issues/683
    description      = "Apache Airflow v2 Helm chart deployment configuration"
    values = [templatefile("${path.module}/values.yaml", {
      # Airflow Postgres RDS Config
      airflow_db_user = local.airflow_name
      airflow_db_name = module.db.db_instance_name
      airflow_db_host = element(split(":", module.db.db_instance_endpoint), 0)
      # S3 bucket config for Logs
      s3_bucket_name          = module.airflow_s3_bucket.s3_bucket_id
      webserver_secret_name   = local.airflow_webserver_secret_name
      airflow_service_account = local.airflow_service_account
      efs_pvc                 = local.efs_pvc
    })]

    set_sensitive = [
      {
        name  = "data.metadataConnection.pass"
        value = aws_secretsmanager_secret_version.postgres.secret_string
      }
    ]
  }
  tags = local.tags
}
