module "emr_containers" {
  source = "./modules/emr-eks-containers"

  eks_cluster_id        = module.eks.cluster_name
  eks_oidc_provider_arn = module.eks.oidc_provider_arn

  emr_on_eks_config = {
    # Example of all settings
    emr-data-team-a = {
      name = format("%s-%s", module.eks.cluster_name, "emr-data-team-a")

      create_namespace = true
      namespace        = "emr-data-team-a"

      execution_role_name                    = format("%s-%s", module.eks.cluster_name, "emr-eks-data-team-a")
      execution_iam_role_description         = "EMR Execution Role for emr-data-team-a"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

      tags = {
        Name = "emr-data-team-a"
      }
    },

    emr-data-team-b = {
      name = format("%s-%s", module.eks.cluster_name, "emr-data-team-b")

      create_namespace = true
      namespace        = "emr-data-team-b"

      execution_role_name                    = format("%s-%s", module.eks.cluster_name, "emr-eks-data-team-b")
      execution_iam_role_description         = "EMR Execution Role for emr-data-team-b"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

      tags = {
        Name = "emr-data-team-b"
      }
    }
  }
}
