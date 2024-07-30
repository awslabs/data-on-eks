resource "aws_kms_key" "eks_insights_kms" {
  description         = "${var.name}-kms"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms_policy.json
}

resource "aws_kms_alias" "eks_insights_kms_alias" {
  name          = "alias/${var.name}-kms"
  target_key_id = aws_kms_key.eks_insights_kms.key_id
}