locals {
  argo_events_namespace       = "argo-events"
  argo_events_service_account = "data-on-eks"
  argo_events_values = yamldecode(templatefile("${path.module}/helm-values/argo-events.yaml", {
  }))
}

#---------------------------------------------------------------
# Argo Events Namespace and Service Account
#---------------------------------------------------------------
resource "kubectl_manifest" "argo_events_manifests" {
  for_each = fileset("${path.module}/manifests/argo-events", "*.yaml")

  yaml_body = file("${path.module}/manifests/argo-events/${each.value}")

  depends_on = [
    kubectl_manifest.argo_events
  ]
}

#---------------------------------------------------------------
# Pod Identity for Argo Events SQS Access
#---------------------------------------------------------------
module "argo_events_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name = "data-on-eks-argo-events"

  additional_policy_arns = {
    sqs_access = aws_iam_policy.sqs_argo_events.arn
  }

  associations = {
    argo_events = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.argo_events_namespace
      service_account = local.argo_events_service_account
    }
  }
}

#---------------------------------------------------------------
# IAM Policy for Argo Events SQS Access
#---------------------------------------------------------------
data "aws_iam_policy_document" "sqs_argo_events" {
  statement {
    sid       = "AllowReadingAndSendingSQSfromArgoEvents"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "sqs:ListQueues",
      "sqs:GetQueueUrl",
      "sqs:ListDeadLetterSourceQueues",
      "sqs:ListMessageMoveTasks",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:ListQueueTags",
      "sqs:DeleteMessage"
    ]
  }
}

resource "aws_iam_policy" "sqs_argo_events" {
  name        = "data-on-eks-argo-events-sqs-policy"
  description = "IAM policy for Argo Events SQS access"
  policy      = data.aws_iam_policy_document.sqs_argo_events.json
}

#---------------------------------------------------------------
# Argo Events Application
#---------------------------------------------------------------
resource "kubectl_manifest" "argo_events" {
  yaml_body = templatefile("${path.module}/argocd-applications/argo-events.yaml", {
    user_values_yaml = indent(10, yamlencode(local.argo_events_values))
  })

  depends_on = [
    helm_release.argocd
  ]
}
