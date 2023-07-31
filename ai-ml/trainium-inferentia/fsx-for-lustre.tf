#---------------------------------------------------------------
# FSx for Lustre File system Static provisioning
#    1> Create Fsx for Lustre filesystem (Lustre FS storage capacity must be 1200, 2400, or a multiple of 3600)
#    2> Create Storage Class for Filesystem (Cluster scoped)
#    3> Persistent Volume with  Hardcoded reference to Fsx for Lustre filesystem with filesystem_id and dns_name (Cluster scoped)
#    4> Persistent Volume claim for this persistent volume will always use the same file system (Namespace scoped)
#---------------------------------------------------------------

#---------------------------------------------------------------
# Sec group for FSx for Lustre
#---------------------------------------------------------------
resource "aws_security_group" "fsx" {
  name        = "${local.name}-fsx"
  description = "Allow inbound traffic from private subnets of the VPC to FSx filesystem"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allows Lustre traffic between Lustre clients"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 1021
    to_port     = 1023
    protocol    = "tcp"
  }
  ingress {
    description = "Allows Lustre traffic between Lustre clients"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 988
    to_port     = 988
    protocol    = "tcp"
  }
  tags = local.tags
}

#---------------------------------------------------------------
# Storage Class - FSx for Lustre
#---------------------------------------------------------------
resource "kubectl_manifest" "fsx_storageclass" {
  yaml_body = <<YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fsx
provisioner: fsx.csi.aws.com
parameters:
  subnetId: ${module.vpc.private_subnets[0]}
  securityGroupIds: ${aws_security_group.fsx.id}
  deploymentType: PERSISTENT_1
  automaticBackupRetentionDays: "1"
  dailyAutomaticBackupStartTime: "00:00"
  copyTagsToBackups: "true"
  perUnitStorageThroughput: "200"
  dataCompressionType: "NONE"
  weeklyMaintenanceStartTime: "7:09:00"
  fileSystemTypeVersion: "2.12"
mountOptions:
  - flock
YAML

  depends_on = [module.eks.eks_cluster_id]
}

#---------------------------------------------------------------
# Static PV for FSx for Lustre
# Don't change the metdata.name `fsx-claim` as this is referenced in lib/trn1_dist_ddp.py script
#---------------------------------------------------------------
resource "kubectl_manifest" "static_pv" {
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fsx-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: fsx
  resources:
    requests:
      storage: 1200Gi
YAML

  depends_on = [resource.kubectl_manifest.fsx_storageclass]
}

#---------------------------------------------------------------
# AWS CLI Command shell pod to copy the files Training dataset from S3 to FSx for Lustre
#---------------------------------------------------------------
resource "kubectl_manifest" "cmd_shell_fsx" {
  yaml_body = <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: cmd-shell
spec:
  containers:
  - name: app
    image: public.ecr.aws/aws-cli/aws-cli:2.13.1
    command: ["/bin/sh", "-c"]
    args: ["while true; do sleep 30; done"]
    volumeMounts:
    - name: persistent-storage
      mountPath: /data
  volumes:
  - name: persistent-storage
    persistentVolumeClaim:
      claimName: fsx-claim
  restartPolicy: Never
YAML

  depends_on = [resource.kubectl_manifest.static_pv]
}
