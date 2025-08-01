resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: trino-karpenter
    spec:
      amiFamily: AL2023
      amiSelectorTerms:
        - alias: al2023@latest
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 20Gi # This storage used for Trino Spill data
            volumeType: gp2
            encrypted: true
            deleteOnTermination: true
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
  YAML
}

# Create a Karpenter NodePool using the AL2023 NodeClass
resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: trino-sql-karpenter
    spec:
      template:
        metadata:
          labels:
            NodePool: trino-sql-karpenter
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: trino-karpenter
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values:
              - "on-demand"
            - key: topology.kubernetes.io/region
              operator: In
              values:
              - "${local.region}"
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
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
