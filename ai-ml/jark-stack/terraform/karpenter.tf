
resource "kubectl_manifest" "karpenter_gpu_node_class" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: Bottlerocket
      role: ${module.eks_blueprints_addons.karpenter.node_iam_role_name}
      securityGroupSelectorTerms:
      - tags:
          Name: ${module.eks.cluster_name}-node
      subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      blockDeviceMappings:
        # Root device
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 50Gi
            volumeType: gp3
            encrypted: true
        # Data device: Container resources such as images and logs
        - deviceName: /dev/xvdb
          ebs:
            volumeSize: 300Gi
            volumeType: gp3
            encrypted: true
            ${var.bottlerocket_data_disk_snpashot_id != null ? "snapshotID: ${var.bottlerocket_data_disk_snpashot_id}" : ""}
  YAML
  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "karpenter_gpu_node_pool" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: gpu
    spec:
      disruption:
        consolidateAfter: 600s
        consolidationPolicy: WhenEmpty
        expireAfter: 720h
      limits:
        cpu: 1k
        memory: 1000Gi
        nvidia.com/gpu: 50
      template:
        metadata: 
          labels:
            NodeGroupType: g5-gpu-karpenter
            type: karpenter
        spec:
          nodeClassRef:
            name: default
          requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: karpenter.k8s.aws/instance-category
            operator: In
            values: ["g"]
          - key: karpenter.k8s.aws/instance-generation
            operator: Gt
            values: ["4"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "topology.kubernetes.io/zone"
            operator: In
            values: ${jsonencode(local.azs)}
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand"]
          taints:
          - key: nvidia.com/gpu
            value: "Exists"
            effect: "NoSchedule"
            
  YAML
  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: default

    spec:
      disruption:
        consolidateAfter: 600s
        consolidationPolicy: WhenEmpty
        expireAfter: 720h
      limits:
        cpu: 1k
      template:
        metadata:
          labels:
            NodeGroupType: x86-cpu-karpenter
            type: karpenter
        spec:
          kubelet:
            maxPods: 110
          nodeClassRef:
            name: default
          requirements:
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c", "m", "r"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "topology.kubernetes.io/zone"
            operator: In
            values: ${jsonencode(local.azs)}
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["on-demand"]
  YAML
  depends_on = [module.eks_blueprints_addons]
}


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