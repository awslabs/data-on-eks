resource "kubernetes_namespace" "s3_namespace" {
  metadata {
    name = "${local.s3_user}"
  }
}


resource "kubernetes_service_account_v1" "s3_sa" {
  metadata {
    name      = "awscli-irsa-sa"
    namespace = "${kubernetes_namespace.s3_namespace.metadata[0].name}"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.s3_outposts_role.arn
    }
  }
}

resource "aws_iam_role" "s3_outposts_role" {
  name = "irsa-s3-outposts-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${kubernetes_namespace.s3_namespace.metadata[0].name}:awscli-irsa-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "s3_outposts_policy" {
  name = "s3-outposts-access"
  role = aws_iam_role.s3_outposts_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Sid": "AccessPointAccess",
        "Effect": "Allow",
        "Action": [
          "s3-outposts:GetObject",
          "s3-outposts:PutObject",
          "s3-outposts:DeleteObject",
          "s3-outposts:ListBucket"
        ],
        "Resource": [
          "${module.airflow_s3_bucket.s3_access_arn}",
          "${module.airflow_s3_bucket.s3_access_arn}/*"
        ]
      },
      {
        "Sid": "BucketAccess",
        "Effect": "Allow",
        "Action": [
          "s3-outposts:GetObject",
          "s3-outposts:PutObject",
          "s3-outposts:DeleteObject",
          "s3-outposts:ListBucket"
        ],
        "Resource": [
          "${module.airflow_s3_bucket.s3_bucket_arn}",
          "${module.airflow_s3_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}


resource "kubectl_manifest" "s3_user_client" {

  yaml_body = templatefile("${path.module}/helm-values/s3.yaml", {
    sa_name = kubernetes_service_account_v1.s3_sa.metadata[0].name
    namespace = kubernetes_namespace.s3_namespace.metadata[0].name
    s3_bucket_name = module.airflow_s3_bucket.s3_bucket_id
  })

}


