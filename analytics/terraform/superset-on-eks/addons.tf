
#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.20"
  role_name_prefix      = format("%s-%s", local.name, "ebs-csi-driver-")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

resource "kubernetes_ingress_class_v1" "aws_alb" {
  metadata {
    name = "aws-alb"
  }

  spec {
    controller = "ingress.k8s.aws/alb"
  }
}

module "lb_role" {
  source                                 = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version                                = "5.37.1"
  role_name                              = format("%s-%s", local.name, "lb-controller-role")
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}


resource "kubernetes_service_account" "service_account" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn"               = module.lb_role.iam_role_arn
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
  }
  depends_on = [module.eks]
}



resource "kubernetes_ingress_v1" "superset" {
  metadata {
    name      = "superset-ingress3"
    namespace = "superset"
    annotations = {
      "alb.ingress.kubernetes.io/scheme"      = "internal-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
  }
  spec {
    ingress_class_name = "aws-alb"
    rule {
      http {
        path {
          path = "/*"
          backend {
            service {
              name = "superset"
              port {
                number = 8088
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.superset]
}



module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    # aws-ebs-csi-driver = {
    #   most_recent              = true
    #   service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    # }
    coredns = {
      preserve = true
    }
    vpc-cni = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
  }
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "1.5.4"
  }
  tags = local.tags
}
