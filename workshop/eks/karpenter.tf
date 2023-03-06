
#---------------------------------------
# Karpenter Provisioners
#---------------------------------------
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/provisioners/spark-*.yaml"
  vars = {
    azs            = local.region
    eks_cluster_id = module.eks.cluster_name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_kubernetes_addons]
}

resource "kubectl_manifest" "memory_provisioner" {
  yaml_body = <<YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: spark-memory-optimized
      namespace: karpenter
    spec:
      kubeletConfiguration:
        containerRuntime: containerd
    #    podsPerCore: 2
    #    maxPods: 20
      requirements:
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: [${azs}b] #Update the correct region and zone
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
        - key: "node.kubernetes.io/instance-type" #If not included, all instance types are considered
          operator: In
          values: ["r5d.4xlarge","r5d.8xlarge","r5d.8xlarge"] # 2 NVMe disk
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
      limits:
        resources:
          cpu: 1000
      providerRef: # optional, recommended to use instead of `provider`
        name: spark-memory-optimized
      labels:
        type: karpenter
        provisioner: spark-memory-optimized
        NodeGroupType: SparkMemoryOptimized
      taints:
        - key: spark-memory-optimized
          value: 'true'
          effect: NoSchedule
      ttlSecondsAfterEmpty: 120 # optional, but never scales down if not set
    YAML
}





