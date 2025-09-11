resource "kubectl_manifest" "external_secrets_operator" {
  yaml_body = templatefile("${path.module}/argocd-applications/external-secrets-operator.yaml", {})

  depends_on = [
    helm_release.argocd,
    module.external_secrets_pod_identity
  ]
}


resource "aws_iam_policy" "external_secrets_policy" {
  name = "${local.name}-external-secrets-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:ListSecrets",
          "secretsmanager:BatchGetSecretValue"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = [
          "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${local.name}/*"
        ]
      }
    ]
  })
}

module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "external-secrets"

  additional_policy_arns = {
    load_balancer_controller = aws_iam_policy.external_secrets_policy.arn
  }

  associations = {
    external_secrets = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}
