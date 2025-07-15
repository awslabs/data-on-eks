

#---------------------------------------------------------------
# cluster_issuer
#---------------------------------------------------------------
# resource "kubectl_manifest" "cluster_issuer" {
#
#     yaml_body = templatefile("${path.module}/helm-values/cluster_issuer.yaml", {
#         cluster_issuer_name = local.cluster_issuer_name
#     })
#
#     depends_on = [
#         module.eks_blueprints_addons
#     ]
# }

resource "kubectl_manifest" "cluster_issuer_dns" {

    yaml_body = templatefile("${path.module}/helm-values/cluster_issuer_dns.yaml", {
        cluster_issuer_name = local.cluster_issuer_name
        region = local.region
        zone_id = local.zone_id
    })

}
