---
title: Spark with EBS Persistent Volumes
sidebar_label: EBS Persistent Volumes
sidebar_position: 1
---

# Spark with EBS Persistent Volumes

Learn how to configure Apache Spark applications to use Amazon EBS persistent volumes for data storage and processing.

## Overview

This example demonstrates how to configure Spark applications to use EBS persistent volumes for:
- Storing large datasets that exceed node local storage
- Persistent data between job runs
- Shared storage across multiple Spark executors
- High-performance storage with gp3 volumes

## Prerequisites

- Spark on EKS data stack deployed
- EBS CSI driver enabled in blueprint configuration
- Appropriate IAM permissions for EBS operations

## Configuration

### Enable EBS CSI Driver

```hcl
# terraform/blueprint.tfvars
enable_aws_ebs_csi_driver = true
```

### Storage Class Configuration

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-spark
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  fsType: ext4
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

## Example Spark Job

### Persistent Volume Claim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: spark-data-pvc
  namespace: spark-operator
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3-spark
  resources:
    requests:
      storage: 100Gi
```

### Spark Application Configuration

```yaml
apiVersion: "sparkoperator.k8s.io/v1beta2"
kind: SparkApplication
metadata:
  name: spark-ebs-example
  namespace: spark-operator
spec:
  type: Python
  pythonVersion: "3"
  mode: cluster
  image: "apache/spark-py:v3.5.0"
  imagePullPolicy: Always
  mainApplicationFile: "local:///opt/spark/examples/src/main/python/pi.py"

  driver:
    cores: 1
    coreLimit: "1200m"
    memory: "1g"
    serviceAccount: spark-operator-spark
    volumeMounts:
      - name: data-volume
        mountPath: /data

  executor:
    cores: 2
    instances: 3
    memory: "2g"
    serviceAccount: spark-operator-spark
    volumeMounts:
      - name: data-volume
        mountPath: /data

  volumes:
    - name: data-volume
      persistentVolumeClaim:
        claimName: spark-data-pvc
```

## Running the Example

### 1. Deploy the Storage Resources

```bash
# Apply storage class
kubectl apply -f examples/storage/gp3-storage-class.yaml

# Create PVC
kubectl apply -f examples/storage/spark-data-pvc.yaml

# Verify PVC creation
kubectl get pvc -n spark-operator
```

### 2. Submit Spark Application

```bash
# Submit the job
kubectl apply -f examples/ebs/spark-ebs-pvc-job.yaml

# Monitor job progress
kubectl get sparkapplications -n spark-operator -w

# Check pod status
kubectl get pods -n spark-operator
```

### 3. Monitor Storage Usage

```bash
# Check PVC details
kubectl describe pvc spark-data-pvc -n spark-operator

# Monitor volume usage
kubectl exec -n spark-operator <driver-pod> -- df -h /data
```

## Performance Optimization

### Storage Performance Tuning

```yaml
# High-performance storage class
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-high-performance
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "16000"
  throughput: "1000"
  fsType: ext4
```

### Spark Configuration for EBS

```yaml
spec:
  sparkConf:
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.serializer": "org.apache.spark.serializer.KryoSerializer"
    # EBS-specific optimizations
    "spark.sql.files.maxPartitionBytes": "268435456"  # 256MB
    "spark.sql.adaptive.advisoryPartitionSizeInBytes": "268435456"
```

## Cost Optimization

### Volume Lifecycle Management

```yaml
# Snapshot policy for cost optimization
apiVersion: v1
kind: ConfigMap
metadata:
  name: snapshot-policy
data:
  policy.yaml: |
    schedules:
      - name: daily-snapshots
        schedule: "0 2 * * *"
        retention: 7
```

### Right-sizing Storage

```bash
# Monitor actual usage
kubectl top pv

# Resize PVC if needed
kubectl patch pvc spark-data-pvc -n spark-operator -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
```

## Troubleshooting

### Common Issues

#### PVC Stuck in Pending State

```bash
# Check events
kubectl describe pvc spark-data-pvc -n spark-operator

# Verify storage class
kubectl get storageclass

# Check EBS CSI driver
kubectl get pods -n kube-system | grep ebs
```

#### Performance Issues

```bash
# Check EBS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EBS \
  --metric-name VolumeReadOps \
  --dimensions Name=VolumeId,Value=<volume-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

#### Volume Mounting Failures

```bash
# Check driver logs
kubectl logs -n kube-system deployment/ebs-csi-controller

# Verify IAM permissions
aws sts get-caller-identity
```

## Best Practices

### Storage Selection

- **gp3**: Balanced performance and cost
- **io2**: High IOPS requirements
- **st1**: Throughput-optimized for large sequential workloads

### Data Patterns

- Use PVCs for datasets larger than node storage
- Consider S3 for input/output data with EBS for intermediate processing
- Implement data partitioning strategies for large datasets

### Monitoring

- Set up CloudWatch alarms for EBS metrics
- Monitor PVC utilization with Prometheus
- Track cost with AWS Cost Explorer

## Related Examples

- [Infrastructure Deployment](./infra)
- [Node Local Storage](./node-local-storage)
- [Back to Examples](/data-on-eks/docs/datastacks/spark-on-eks/)
