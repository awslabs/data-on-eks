#---------------------------------------------------------------
# selfsigned_cluster_issuer
#---------------------------------------------------------------
resource "kubectl_manifest" "selfsigned_cluster_issuer" {

    yaml_body = templatefile("${path.module}/helm-values/selfsigned_cluster_issuer.yaml", {
        cluster_issuer_name = local.cluster_issuer_name
    })

    depends_on = [
        module.eks_blueprints_addons
    ]
}