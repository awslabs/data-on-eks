apiVersion: v1
kind: PersistentVolume
metadata:
  name: spark-s3-mount-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  mountOptions:
    - uid=1001
    - gid=185
    - allow-other
    - allow-delete
    - allow-overwrite
    # replace ${region} with S3 Express bucket name from Terraform output
    - region ${region}
  csi:
    driver: s3.csi.aws.com # required
    volumeHandle: s3-csi-driver-volume
    volumeAttributes:
      # replace ${s3_express_bucket_name} with S3 Express bucket name from Terraform output
      bucketName: ${s3_express_bucket_name}
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values:
            # replace ${s3express_bucket_zone} with S3 Express bucket availability zone from Terraform output
            - ${s3express_bucket_zone}