#---------------------------------------
# Karpenter Provisioners
#---------------------------------------
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/provisioners/spark-*.yaml"
  vars = {
    azs            = var.region
    eks_cluster_id = var.name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value
}
