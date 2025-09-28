---
title: Spark with Node Local Storage
sidebar_label: Node Local Storage
sidebar_position: 2
---

# Spark with Node Local Storage

Optimize Apache Spark performance using node local storage for high-speed data processing and intermediate storage.

## Overview

This example demonstrates how to configure Spark applications to leverage:
- Instance store NVMe SSD volumes for maximum performance
- Local ephemeral storage for intermediate data
- Node-local data processing to minimize network overhead
- Karpenter provisioning for storage-optimized instances

## Prerequisites

- Spark on EKS data stack deployed
- Karpenter configured for instance types with local storage
- Understanding of Spark data locality concepts

## Configuration

### Karpenter NodePool for Storage-Optimized Instances

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spark-storage-optimized
spec:
  template:
    metadata:
      labels:
        workload-type: spark-storage
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["r5d.large", "r5d.xlarge", "r5d.2xlarge", "r5d.4xlarge", "m5d.large", "m5d.xlarge", "m5d.2xlarge"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: spark-storage-nodeclass
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
```

### EC2NodeClass with Local Storage

```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: spark-storage-nodeclass
spec:
  amiFamily: AL2
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "spark-on-eks"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "spark-on-eks"
  instanceStorePolicy: "RAID0"  # Configure instance store as RAID0
  userData: |
    #!/bin/bash
    /etc/eks/bootstrap.sh spark-on-eks

    # Mount instance store to /local-ssd
    mkdir -p /local-ssd

    # Format and mount NVMe storage
    if [ -b /dev/nvme1n1 ]; then
      mkfs.ext4 /dev/nvme1n1
      mount /dev/nvme1n1 /local-ssd
      chmod 777 /local-ssd
    fi
```

## Example Spark Job Configuration

### Local Storage Spark Application

```yaml
apiVersion: "sparkoperator.k8s.io/v1beta2"
kind: SparkApplication
metadata:
  name: spark-local-storage-example
  namespace: spark-operator
spec:
  type: Python
  pythonVersion: "3"
  mode: cluster
  image: "apache/spark-py:v3.5.0"
  imagePullPolicy: Always
  mainApplicationFile: "local:///app/large-dataset-processing.py"

  sparkConf:
    # Local storage optimizations
    "spark.local.dir": "/local-ssd/spark-temp"
    "spark.sql.adaptive.enabled": "true"
    "spark.sql.adaptive.coalescePartitions.enabled": "true"
    "spark.sql.adaptive.localShuffleReader.enabled": "true"
    "spark.serializer": "org.apache.spark.serializer.KryoSerializer"
    # Optimize for local storage
    "spark.sql.shuffle.partitions": "400"
    "spark.sql.files.maxPartitionBytes": "134217728"  # 128MB
    "spark.executor.heartbeatInterval": "20s"

  driver:
    cores: 2
    coreLimit: "2000m"
    memory: "4g"
    serviceAccount: spark-operator-spark
    nodeSelector:
      workload-type: spark-storage
    volumeMounts:
      - name: local-storage
        mountPath: /local-ssd

  executor:
    cores: 4
    instances: 6
    memory: "8g"
    serviceAccount: spark-operator-spark
    nodeSelector:
      workload-type: spark-storage
    volumeMounts:
      - name: local-storage
        mountPath: /local-ssd

  volumes:
    - name: local-storage
      hostPath:
        path: /local-ssd
        type: DirectoryOrCreate
```

## Running the Example

### 1. Deploy NodePool Configuration

```bash
# Apply Karpenter configuration
kubectl apply -f examples/storage/storage-optimized-nodepool.yaml

# Verify NodePool creation
kubectl get nodepools
```

### 2. Submit Spark Application

```bash
# Submit the job
kubectl apply -f examples/storage/spark-local-storage-job.yaml

# Monitor node provisioning
kubectl get nodes -l workload-type=spark-storage -w

# Check job progress
kubectl get sparkapplications -n spark-operator -w
```

### 3. Monitor Performance

```bash
# Check local storage usage
kubectl exec -n spark-operator <executor-pod> -- df -h /local-ssd

# Monitor I/O performance
kubectl exec -n spark-operator <executor-pod> -- iostat -x 1 5
```

## Performance Optimization

### Instance Type Selection

```yaml
# High-performance instance types with NVMe
requirements:
  - key: node.kubernetes.io/instance-type
    operator: In
    values:
      # Storage-optimized
      - "i3.large"      # 475 GB NVMe
      - "i3.xlarge"     # 950 GB NVMe
      - "i3.2xlarge"    # 1,900 GB NVMe
      - "i3.4xlarge"    # 3,800 GB NVMe
      # Memory-optimized with local storage
      - "r5d.xlarge"    # 150 GB NVMe
      - "r5d.2xlarge"   # 300 GB NVMe
      - "r5d.4xlarge"   # 600 GB NVMe
```

### Spark Configuration Tuning

```yaml
sparkConf:
  # Maximize local storage utilization
  "spark.local.dir": "/local-ssd/spark-temp,/local-ssd/spark-temp2"
  "spark.shuffle.spill.diskWriteBufferSize": "1048576"  # 1MB
  "spark.io.compression.codec": "snappy"

  # Memory management
  "spark.executor.memory": "12g"
  "spark.executor.memoryFraction": "0.8"
  "spark.storage.memoryFraction": "0.2"

  # Network optimization for data locality
  "spark.locality.wait": "0s"
  "spark.locality.wait.process": "0s"
  "spark.locality.wait.node": "0s"
  "spark.locality.wait.rack": "0s"
```

## Data Processing Patterns

### Large Dataset Processing

```python
# Example Python application
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("LocalStorageExample") \
    .config("spark.local.dir", "/local-ssd/spark-temp") \
    .getOrCreate()

# Read large dataset from S3
df = spark.read.parquet("s3a://your-bucket/large-dataset/")

# Cache to local storage for repeated access
df.cache()

# Process data with multiple transformations
result = df.groupBy("category") \
    .agg({"amount": "sum", "count": "count"}) \
    .orderBy("sum(amount)", ascending=False)

# Write intermediate results to local storage
result.write.mode("overwrite") \
    .parquet("/local-ssd/intermediate-results")

# Read intermediate data for further processing
intermediate_df = spark.read.parquet("/local-ssd/intermediate-results")

# Final output to S3
intermediate_df.write.mode("overwrite") \
    .parquet("s3a://your-bucket/processed-results/")
```

## Troubleshooting

### Local Storage Not Available

```bash
# Check node storage configuration
kubectl describe node <node-name> | grep -A5 "Capacity:"

# Verify instance store mounting
kubectl exec -n karpenter <node-name> -- lsblk

# Check userData script execution
kubectl logs -n karpenter deployment/karpenter
```

### Performance Issues

```bash
# Check I/O wait
kubectl exec -n spark-operator <executor-pod> -- top

# Monitor disk utilization
kubectl exec -n spark-operator <executor-pod> -- iotop

# Verify data locality
kubectl logs -n spark-operator <driver-pod> | grep "data locality"
```

## Best Practices

### Storage Strategy

- Use instance store for temporary data and shuffle operations
- Combine with S3 for input/output data persistence
- Implement data partitioning for optimal locality

### Resource Allocation

- Size executors to match available local storage
- Use memory efficiently to reduce disk spills
- Consider network bandwidth for S3 operations

### Fault Tolerance

- Implement checkpointing for long-running jobs
- Use S3 for critical intermediate results
- Design for spot instance interruptions

## Related Examples

- [Infrastructure Deployment](./infra)
- [EBS Persistent Volumes](./ebs-persistent-volumes)
- [Back to Examples](/data-on-eks/docs/datastacks/spark-on-eks/)
