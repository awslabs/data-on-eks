module "emr_containers" {
  source = "../../workshop/modules/emr-eks-containers"

  eks_cluster_id        = module.eks.cluster_name
  eks_oidc_provider_arn = module.eks.oidc_provider_arn

  emr_on_eks_config = {
    # Example of all settings
    emr-ml-team-a = {
      name = format("%s-%s", module.eks.cluster_name, "emr-ml-team-a")

      create_namespace = true
      namespace        = "emr-ml-team-a"

      execution_role_name                    = format("%s-%s", module.eks.cluster_name, "emr-eks-data-team-a")
      execution_iam_role_description         = "EMR Execution Role for emr-ml-team-a"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess", "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"] # Attach additional policies for execution IAM Role
      tags = {
        Name = "emr-ml-team-a"
      }
    },

    emr-ml-team-b = {
      name = format("%s-%s", module.eks.cluster_name, "emr-ml-team-b")

      create_namespace = true
      namespace        = "emr-ml-team-b"

      execution_role_name                    = format("%s-%s", module.eks.cluster_name, "emr-eks-data-team-b")
      execution_iam_role_description         = "EMR Execution Role for emr-ml-team-b"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess", "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"] # Attach additional policies for execution IAM Role

      tags = {
        Name = "emr-ml-team-b"
      }
    }
  }
}
