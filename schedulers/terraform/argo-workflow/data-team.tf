#---------------------------------------------------------------
# create data-team-a ns and sa
#---------------------------------------------------------------
module "irsa" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.15.0"

  eks_cluster_id             = local.name
  eks_oidc_provider_arn      = module.eks.oidc_provider_arn
  irsa_iam_policies          = [aws_iam_policy.spark.arn]
  kubernetes_namespace       = "data-team-a"
  kubernetes_service_account = "data-team-a"
}

resource "aws_iam_policy" "spark" {
  description = "IAM role policy for Spark Job execution"
  name        = "${local.name}-spark-irsa"
  policy      = data.aws_iam_policy_document.spark_operator.json
}
#---------------------------------------------------------------
# Kubernetes Cluster role for run spark jobs
#---------------------------------------------------------------
resource "kubernetes_cluster_role" "spark_op_role" {
  metadata {
    name = "spark-op-role"
  }

  rule {
    verbs      = ["*"]
    api_groups = ["sparkoperator.k8s.io"]
    resources  = ["sparkapplications"]
  }
}
#---------------------------------------------------------------
# Kubernetes Role binding for argo workflows/data-team-a
#---------------------------------------------------------------
# allow argo-workflows to run spark application in data-team-a
resource "kubernetes_role_binding" "spark_role_binding" {
  metadata {
    name      = "data-team-a-spark-rolebinding"
    namespace = "data-team-a"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "argo-workflows"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.spark_op_role.id
  }

  depends_on = [module.eks_data_addons]
}
// grant argo-workflows admin role
resource "kubernetes_role_binding" "admin_rolebinding_argoworkflows" {
  metadata {
    name      = "argo-workflows-admin-rolebinding"
    namespace = "argo-workflows"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "argo-workflows"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }

  depends_on = [module.eks_data_addons]
}
// grant data-team-a admin role
resource "kubernetes_role_binding" "admin_rolebinding_data_teama" {
  metadata {
    name      = "data-team-a-admin-rolebinding"
    namespace = "data-team-a"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "data-team-a"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
}

#---------------------------------------------------------------
# IRSA for Argo events to read SQS
#---------------------------------------------------------------
module "irsa_argo_events" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.15.0"

  create_kubernetes_namespace = true
  kubernetes_namespace        = "argo-events"
  kubernetes_service_account  = "event-sa"
  irsa_iam_policies           = [data.aws_iam_policy.sqs.arn]
  eks_cluster_id              = module.eks.cluster_name
  eks_oidc_provider_arn       = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${module.eks.oidc_provider_arn}"
}