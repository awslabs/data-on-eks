resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: spark-karpenter
    spec:
      amiFamily: AL2023
      amiSelectorTerms:
        - alias: al2023@latest
      instanceStorePolicy: RAID0
      role: ${local.karpenter_node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${local.name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${local.name}
      tags:
        karpenter.sh/discovery: ${local.name}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 20Gi
            volumeType: gp2
            deleteOnTermination: true
            encrypted: true
  YAML
}

# Create a Karpenter NodePool using the AL2023 NodeClass
resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: spark-karpenter
    spec:
      template:
        metadata:
          labels:
            NodePool: karpenter
            karpenter.sh/capacity-type: "on-demand"
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: spark-karpenter
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values:
              - "on-demand"
            - key: node.kubernetes.io/instance-type
              operator: In
              values: # de base ca utilise c5d de ["4xlarge", "9xlarge", "12xlarge", "18xlarge", "24xlarge"]
              - r5.4xlarge
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 600s  #initialement à 60s
      limits:
        cpu: "1000"
        memory: 1000Gi
      weight: 100
      minCount: 1
  YAML

  depends_on = [
    kubectl_manifest.karpenter_node_class
  ]
}
