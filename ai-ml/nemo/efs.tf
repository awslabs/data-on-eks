#---------------------------------------------------------------
# EFS Filesystem for private volumes per user
# This will be replaced with Dynamic EFS provision using EFS CSI Driver
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs" {
  creation_token = "efs-nemo-eks"
  encrypted      = true

  tags = local.tags
}

resource "aws_efs_mount_target" "efs_mt" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = module.vpc.private_subnets[2]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {

  name        = "${local.name}-efs"
  description = "Allow inbound NFS traffic from private subnets of the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow NFS 2049/tcp"
    cidr_blocks = module.vpc.vpc_secondary_cidr_blocks
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  tags = local.tags
}

resource "kubectl_manifest" "storageclass" {

  yaml_body = <<YAML
kind: StorageClass 
apiVersion: storage.k8s.io/v1 
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
YAML

depends_on = [ module.eks_blueprints_addons ]
}

resource "kubectl_manifest" "pv" {

  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolume 
metadata:
  name: efs-pv 
spec:
  capacity: 
    storage: 200Gi
  volumeMode: Filesystem 
  accessModes:
    - ReadWriteMany 
  persistentVolumeReclaimPolicy: Retain 
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com 
    volumeHandle: ${aws_efs_file_system.efs.id}
YAML

  depends_on = [module.eks_blueprints_addons]
}

resource "kubectl_manifest" "pvc" {

  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim 
metadata:
  name: efs-claim
spec:
  accessModes:
    - ReadWriteMany 
  storageClassName: efs-sc 
  resources:
    requests: 
      storage: 200Gi
YAML

  depends_on = [module.eks_blueprints_addons]
}

