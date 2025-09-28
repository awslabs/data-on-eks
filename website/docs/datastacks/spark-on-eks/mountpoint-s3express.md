---
title: Mountpoint S3 Express
sidebar_position: 7
---

# Mountpoint S3 Express

This blueprint demonstrates ultra-high performance S3 Express One Zone storage with single-digit millisecond latency for high-throughput Spark analytics workloads.

## Overview

S3 Express One Zone is a high-performance storage class that delivers consistent single-digit millisecond data access for frequently accessed data. Combined with Mountpoint for S3, it provides the fastest possible S3 integration for Spark workloads.

## Key Features

- **Ultra-Low Latency**: Single-digit millisecond access times
- **High Throughput**: Up to 10x faster than standard S3
- **Zone-Optimized**: Co-located with compute for minimal network latency
- **Cost Effective**: Pay only for what you use with no minimum commitments
- **POSIX Interface**: Standard file system semantics via Mountpoint

## Prerequisites

Before deploying this blueprint, ensure you have:

- ✅ [Infrastructure deployed](/data-on-eks/docs/datastacks/spark-on-eks/infra)
- ✅ `kubectl` configured for your EKS cluster
- ✅ S3 Express One Zone bucket created in same AZ as EKS nodes
- ✅ IAM roles with S3 Express permissions

## Quick Deploy & Test

### 1. Create S3 Express One Zone Bucket

```bash
# Create S3 Express bucket in same AZ as your EKS cluster
export AZ="us-west-2a"
export BUCKET_NAME="spark-express-${RANDOM}--${AZ}--x-s3"

aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --create-bucket-configuration LocationConstraint=us-west-2 \
  --bucket-type Directory

# Enable S3 Express One Zone
aws s3api put-bucket-accelerate-configuration \
  --bucket $BUCKET_NAME \
  --accelerate-configuration Status=Enabled
```

### 2. Deploy Mountpoint for S3 Express

```bash
# Navigate to data-stacks directory
cd data-stacks/spark-on-eks

# Update bucket name in configuration
export S3_EXPRESS_BUCKET=$BUCKET_NAME
envsubst < examples/mountpoint-s3-spark/mountpoint-s3express-daemonset.yaml | kubectl apply -f -
```

### 3. Deploy Spark Application

```bash
# Deploy S3 Express optimized Spark job
envsubst < examples/mountpoint-s3-spark/spark-s3express-job.yaml | kubectl apply -f -
```

### 4. Verify Performance

```bash
# Monitor Spark application
kubectl get sparkapplications -n spark-team-a

# Check latency metrics
kubectl logs -n spark-team-a -l spark-role=driver | grep -i "s3.*time"

# View detailed performance metrics
kubectl port-forward -n spark-history svc/spark-history-server 18080:80
```

## Configuration Details

### S3 Express One Zone Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: s3express-config
  namespace: spark-team-a
data:
  bucket: "spark-express-123--us-west-2a--x-s3"
  region: "us-west-2"
  availability-zone: "us-west-2a"
  endpoint: "https://s3express-control.us-west-2.amazonaws.com"
```

### Mountpoint S3 Express DaemonSet

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: mountpoint-s3express
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: mountpoint-s3express
        image: public.ecr.aws/mountpoint-s3/mountpoint-s3-csi-driver:latest
        args:
          - "--cache-size=20GB"
          - "--part-size=8MB"
          - "--max-concurrent-requests=64"
          - "--read-timeout=5s"
          - "--write-timeout=10s"
          - "--s3-express-one-zone"
        env:
        - name: S3_EXPRESS_BUCKET
          valueFrom:
            configMapKeyRef:
              name: s3express-config
              key: bucket
```

### Spark Application Optimization

```yaml
spec:
  sparkConf:
    "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem"
    "spark.hadoop.fs.s3a.s3express.create.session": "true"
    "spark.hadoop.fs.s3a.s3express.session.duration": "300"
    "spark.hadoop.fs.s3a.connection.maximum": "200"
    "spark.hadoop.fs.s3a.fast.upload": "true"
    "spark.hadoop.fs.s3a.multipart.size": "8388608"
    "spark.hadoop.fs.s3a.multipart.threshold": "8388608"
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.sql.adaptive.advisoryPartitionSizeInBytes": "134217728"
```

## Performance Validation

### Latency Benchmarking

```bash
# Run latency-sensitive workload
kubectl apply -f - <<EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: s3express-latency-test
  namespace: spark-team-a
spec:
  type: Python
  mode: cluster
  image: public.ecr.aws/spark/spark-py:3.5.0
  mainApplicationFile: "s3a://${S3_EXPRESS_BUCKET}/scripts/latency-test.py"
  sparkConf:
    "spark.hadoop.fs.s3a.s3express.create.session": "true"
    "spark.eventLog.enabled": "true"
    "spark.eventLog.dir": "s3a://${S3_EXPRESS_BUCKET}/spark-logs/"
  driver:
    cores: 2
    memory: "4g"
  executor:
    cores: 4
    instances: 8
    memory: "8g"
EOF
```

### Throughput Testing

```bash
# Monitor I/O performance
kubectl exec -n spark-team-a <driver-pod> -- iostat -x 1 10

# Check S3 Express metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name NumberOfObjects \
  --dimensions Name=BucketName,Value=$S3_EXPRESS_BUCKET \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Expected Results

✅ **Ultra-Low Latency**: Under 10ms access times for hot data
✅ **High Throughput**: 10x faster than standard S3
✅ **Consistent Performance**: Predictable latency under load
✅ **Cost Optimization**: Pay-per-request with no minimums
✅ **Spark Integration**: Seamless integration with existing Spark code

## Troubleshooting

### Common Issues

**S3 Express session creation failures:**
```bash
# Check IAM permissions for S3 Express
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/spark-team-a \
  --action-names s3express:CreateSession \
  --resource-arns arn:aws:s3express:us-west-2:ACCOUNT:bucket/$S3_EXPRESS_BUCKET

# Verify bucket configuration
aws s3api describe-bucket --bucket $S3_EXPRESS_BUCKET
```

**High latency despite S3 Express:**
```bash
# Check AZ alignment
kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.'topology\.kubernetes\.io/zone'

# Verify S3 Express endpoint
kubectl exec -n spark-team-a <pod-name> -- nslookup s3express-control.us-west-2.amazonaws.com

# Monitor network latency
kubectl exec -n spark-team-a <pod-name> -- ping -c 10 s3express-control.us-west-2.amazonaws.com
```

**Performance degradation:**
```bash
# Check Mountpoint cache utilization
kubectl exec -n kube-system <mountpoint-pod> -- df -h /mnt/s3express-cache

# Monitor concurrent request limits
kubectl logs -n kube-system -l app=mountpoint-s3express | grep -i "throttl\|limit"

# Verify S3 Express capacity
aws s3api get-bucket-location --bucket $S3_EXPRESS_BUCKET
```

## Advanced Configuration

### Multi-AZ Deployment

```yaml
# Deploy across multiple AZs for HA
apiVersion: v1
kind: ConfigMap
metadata:
  name: s3express-multi-az
data:
  primary-bucket: "spark-express-123--us-west-2a--x-s3"
  secondary-bucket: "spark-express-456--us-west-2b--x-s3"
  tertiary-bucket: "spark-express-789--us-west-2c--x-s3"
```

### Session Management

```yaml
# Optimize S3 Express session configuration
spec:
  sparkConf:
    "spark.hadoop.fs.s3a.s3express.create.session": "true"
    "spark.hadoop.fs.s3a.s3express.session.duration": "900"
    "spark.hadoop.fs.s3a.s3express.session.cache.size": "1000"
    "spark.hadoop.fs.s3a.s3express.session.refresh.interval": "600"
```

### Request Optimization

```yaml
# Tune for maximum performance
spec:
  sparkConf:
    "spark.hadoop.fs.s3a.connection.maximum": "500"
    "spark.hadoop.fs.s3a.threads.max": "64"
    "spark.hadoop.fs.s3a.max.total.tasks": "100"
    "spark.hadoop.fs.s3a.multipart.uploads.enabled": "true"
    "spark.hadoop.fs.s3a.fast.upload.buffer": "bytebuffer"
```

## Cost Optimization

### Request Pattern Analysis

```bash
# Monitor request patterns
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name AllRequests \
  --dimensions Name=BucketName,Value=$S3_EXPRESS_BUCKET \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum

# Analyze cost per request
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '1 day ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

### Data Lifecycle Management

```yaml
# Configure automated cleanup
apiVersion: batch/v1
kind: CronJob
metadata:
  name: s3express-cleanup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: amazon/aws-cli:latest
            command:
            - /bin/sh
            - -c
            - |
              aws s3api list-objects-v2 --bucket $S3_EXPRESS_BUCKET \
                --query 'Contents[?LastModified<`$(date -u -d "7 days ago" +%Y-%m-%d)`].Key' \
                --output text | xargs -I {} aws s3api delete-object --bucket $S3_EXPRESS_BUCKET --key {}
```

## Related Blueprints

- [Mountpoint S3](/data-on-eks/docs/datastacks/spark-on-eks/mountpoint-s3) - Standard S3 with Mountpoint
- [S3 Tables](/data-on-eks/docs/datastacks/spark-on-eks/s3tables) - Iceberg integration with S3 Express
- [Spark Operator Benchmarks](/data-on-eks/docs/datastacks/spark-on-eks/spark-operator-benchmarks) - Performance testing

## Additional Resources

- [S3 Express One Zone Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-one-zone.html)
- [S3 Express Performance Guide](https://aws.amazon.com/s3/storage-classes/express-one-zone/)
- [Mountpoint S3 Express Configuration](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md)
