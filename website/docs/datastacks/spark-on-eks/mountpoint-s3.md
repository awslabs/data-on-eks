---
title: Mountpoint S3
sidebar_position: 6
---

# Mountpoint S3

This blueprint demonstrates high-performance S3 access using Mountpoint for S3 with optimized data transfer and seamless S3 integration for Spark workloads.

## Overview

Mountpoint for S3 is a high-performance, POSIX-style file client that translates local file system API calls to S3 object API calls. It provides optimized throughput and lower latency compared to traditional S3 access methods.

## Key Features

- **High Throughput**: Optimized for large sequential reads with multi-part downloads
- **POSIX Interface**: Standard file system semantics for S3 objects
- **Low Latency**: Reduced overhead compared to S3A file system
- **Concurrent Access**: Multiple readers and writers with intelligent caching
- **Cost Effective**: Direct S3 access without additional storage costs

## Prerequisites

Before deploying this blueprint, ensure you have:

- ✅ [Infrastructure deployed](/data-on-eks/docs/datastacks/spark-on-eks/infra)
- ✅ `kubectl` configured for your EKS cluster
- ✅ S3 bucket created for Spark data
- ✅ IAM roles with S3 access permissions

## Quick Deploy & Test

### 1. Deploy Mountpoint DaemonSet

```bash
# Navigate to data-stacks directory
cd data-stacks/spark-on-eks

# Deploy Mountpoint S3 DaemonSet
kubectl apply -f examples/mountpoint-s3-spark/mountpoint-s3-daemonset.yaml
```

### 2. Deploy Spark Application

```bash
# Apply Spark job with Mountpoint S3 integration
kubectl apply -f examples/mountpoint-s3-spark/mountpoint-s3-spark-job.yaml
```

### 3. Verify Deployment

```bash
# Check DaemonSet rollout
kubectl get daemonset -n kube-system mountpoint-s3-csi-driver

# Monitor Spark application
kubectl get sparkapplications -n spark-team-a

# Check pod logs for Mountpoint mounting
kubectl logs -n spark-team-a -l spark-role=driver
```

### 4. Upload Test Data

```bash
# Copy test data to S3 bucket
./examples/mountpoint-s3-spark/copy-jars-to-s3.sh

# Verify S3 data accessibility
kubectl exec -n spark-team-a <driver-pod> -- ls -la /opt/spark/s3-data/
```

## Configuration Details

### Mountpoint DaemonSet Configuration

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: mountpoint-s3-csi-driver
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: mountpoint-s3
        image: public.ecr.aws/mountpoint-s3/mountpoint-s3-csi-driver:latest
        securityContext:
          privileged: true
        volumeMounts:
        - name: s3-mount
          mountPath: /mnt/s3
          mountPropagation: Bidirectional
```

### Spark Application Configuration

```yaml
spec:
  sparkConf:
    "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem"
    "spark.hadoop.fs.s3a.mountpoint.enabled": "true"
    "spark.hadoop.fs.s3a.mountpoint.path": "/mnt/s3"
  volumes:
    - name: s3-volume
      hostPath:
        path: /mnt/s3
        type: Directory
  volumeMounts:
    - name: s3-volume
      mountPath: /opt/spark/s3-data
```

### S3 Bucket Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:role/spark-team-a"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::spark-on-eks-*",
        "arn:aws:s3:::spark-on-eks-*/*"
      ]
    }
  ]
}
```

## Performance Validation

### Throughput Testing

```bash
# Run I/O intensive Spark job
kubectl apply -f - <<EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: mountpoint-s3-benchmark
  namespace: spark-team-a
spec:
  type: Scala
  mode: cluster
  image: public.ecr.aws/spark/spark:3.5.0
  mainClass: org.apache.spark.examples.SparkPi
  mainApplicationFile: "s3a://spark-on-eks-data/jars/spark-examples.jar"
  sparkConf:
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.hadoop.fs.s3a.mountpoint.enabled": "true"
  driver:
    cores: 2
    memory: "4g"
  executor:
    cores: 4
    instances: 4
    memory: "8g"
EOF
```

### Performance Metrics

```bash
# Monitor read/write throughput
kubectl exec -n spark-team-a <driver-pod> -- iostat -x 1

# Check Mountpoint metrics
kubectl logs -n kube-system -l app=mountpoint-s3-csi-driver | grep -i throughput

# Spark metrics via History Server
kubectl port-forward -n spark-history svc/spark-history-server 18080:80
```

## Expected Results

✅ **High Throughput**: 2-3x faster S3 read performance vs S3A
✅ **Low Latency**: Reduced first-byte latency for file access
✅ **POSIX Compatibility**: Standard file operations work seamlessly
✅ **Cost Efficiency**: No additional storage costs beyond S3
✅ **Scalability**: Concurrent access across multiple Spark executors

## Troubleshooting

### Common Issues

**Mountpoint pods not starting:**
```bash
# Check DaemonSet status
kubectl describe daemonset -n kube-system mountpoint-s3-csi-driver

# Verify node permissions
kubectl get nodes -o wide

# Check security context
kubectl describe pod -n kube-system -l app=mountpoint-s3-csi-driver
```

**S3 access permission errors:**
```bash
# Verify IAM role permissions
aws sts get-caller-identity

# Check S3 bucket policy
aws s3api get-bucket-policy --bucket spark-on-eks-data

# Test S3 access from pod
kubectl exec -n spark-team-a <pod-name> -- aws s3 ls s3://spark-on-eks-data/
```

**Mount path issues:**
```bash
# Check mount points
kubectl exec -n kube-system <mountpoint-pod> -- mount | grep s3

# Verify volume mounts in Spark pods
kubectl describe pod -n spark-team-a <spark-pod-name>

# Check file system accessibility
kubectl exec -n spark-team-a <pod-name> -- ls -la /opt/spark/s3-data/
```

## Advanced Configuration

### Performance Tuning

```yaml
# Optimized Mountpoint configuration
spec:
  containers:
  - name: mountpoint-s3
    args:
      - "--cache-size=10GB"
      - "--part-size=16MB"
      - "--max-concurrent-requests=32"
      - "--read-timeout=30s"
      - "--write-timeout=60s"
```

### Multi-Bucket Support

```yaml
# Multiple S3 bucket mounts
spec:
  volumes:
    - name: data-bucket
      csi:
        driver: s3.csi.aws.com
        volumeAttributes:
          bucketName: spark-data-bucket
          mountOptions: "allow-delete,allow-overwrite"
    - name: logs-bucket
      csi:
        driver: s3.csi.aws.com
        volumeAttributes:
          bucketName: spark-logs-bucket
          mountOptions: "read-only"
```

### Regional Optimization

```yaml
# Region-specific configuration
spec:
  template:
    metadata:
      annotations:
        mountpoint.s3.aws/region: "us-west-2"
        mountpoint.s3.aws/endpoint: "https://s3.us-west-2.amazonaws.com"
```

## Cost Optimization

### Intelligent Tiering

```bash
# Configure S3 Intelligent Tiering
aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket spark-on-eks-data \
  --id spark-tiering \
  --intelligent-tiering-configuration \
  Id=spark-tiering,Status=Enabled,IncludedObjectFilter='{}'
```

### Storage Class Optimization

```yaml
# Configure storage class for different workloads
spec:
  sparkConf:
    "spark.hadoop.fs.s3a.fast.upload": "true"
    "spark.hadoop.fs.s3a.storage.class": "INTELLIGENT_TIERING"
    "spark.hadoop.fs.s3a.multipart.size": "67108864"
```

## Related Blueprints

- [Mountpoint S3 Express](/data-on-eks/docs/datastacks/spark-on-eks/mountpoint-s3express) - Ultra-fast S3 Express One Zone
- [S3 Tables](/data-on-eks/docs/datastacks/spark-on-eks/s3tables) - Apache Iceberg with S3 Tables
- [NVMe Storage](/data-on-eks/docs/datastacks/spark-on-eks/nvme-storage) - Hybrid storage with local and S3

## Additional Resources

- [Mountpoint for S3 Documentation](https://github.com/awslabs/mountpoint-s3)
- [S3 Performance Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/optimizing-performance.html)
- [Spark S3A Configuration Guide](https://spark.apache.org/docs/latest/cloud-integration.html)