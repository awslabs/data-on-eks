resource "aws_iam_policy" "karpenter_controlloer_policy" {
  description = "Additional IAM policy for Karpenter controller"
  policy      = data.aws_iam_policy_document.karpenter_controller_policy.json
}

data "aws_iam_policy_document" "karpenter_controller_policy" {
  statement {
    actions = [
      "ec2:RunInstances",
      "ec2:CreateLaunchTemplate",
    ]
    resources = ["*"]
    effect    = "Allow"
    sid       = "Karpenter"
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_policy_attachment" {
  # name       = "karpenter-controller-policy-attachment"
  role      = module.eks_blueprints_addons.karpenter.iam_role_name
  policy_arn = aws_iam_policy.karpenter_controlloer_policy.arn
}