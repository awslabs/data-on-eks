module "emr_containers" {
  source = "./modules/emr-eks-containers"

  enable_emr_on_eks = true
  eks_cluster_id = module.eks.cluster_name

  emr_on_eks_config = {
    # Example of all settings
    emr-data-team-a = {
      name = "emr-data-team-a"

      create_namespace = true
      namespace        = "emr-data-team-a"

      execution_role_name                    = "emr-eks-data-team-a"
      execution_iam_role_description         = "EMR Execution Role for emr-data-team-a"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

      tags = {
        Name = "emr-data-team-a"
      }
    },

    emr-data-team-b = {
      name = "emr-data-team-b"

      create_namespace = true
      namespace        = "emr-data-team-b"

      execution_role_name                    = "emr-eks-data-team-b"
      execution_iam_role_description         = "EMR Execution Role for emr-data-team-b"
      execution_iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] # Attach additional policies for execution IAM Role

    }
  }

}
