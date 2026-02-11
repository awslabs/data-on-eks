---
sidebar_position: 6
sidebar_label: Mountpoint S3 for Spark
---

import CollapsibleContent from '@site/src/components/CollapsibleContent';
import CodeBlock from '@theme/CodeBlock';

# Mountpoint S3 for Spark Workloads

## Overview

When working with SparkApplications managed by [Spark Operator](https://github.com/kubeflow/spark-operator), handling multiple dependency JAR files presents significant challenges:

- **Increased Build Time**: Downloading JAR files during image builds inflates build time
- **Larger Image Size**: Bundled JARs increase container size and pull time
- **Frequent Rebuilds**: JAR updates require complete image rebuilds

[Mountpoint for Amazon S3](https://aws.amazon.com/s3/features/mountpoint/) solves these challenges by mounting S3 buckets as local file systems, enabling seamless access to JARs without embedding them in container images.

## What is Mountpoint S3?

[Mountpoint S3](https://github.com/awslabs/mountpoint-s3) is an open-source file client that translates POSIX file operations into S3 API calls. It's optimized for:
- **High read throughput** to large objects from many concurrent clients
- **Sequential writes** of new objects from single clients
- **Large-scale data processing** and AI/ML training workloads

### Performance Foundation: AWS CRT Library

Mountpoint S3's high performance is powered by the [AWS Common Runtime (CRT)](https://docs.aws.amazon.com/sdkref/latest/guide/common-runtime.html) library:

- **Efficient I/O Management**: Non-blocking I/O operations minimize latency
- **Lightweight Design**: Minimal overhead with modular architecture
- **Advanced Memory Management**: Reduces garbage collection overhead
- **Optimized Network Protocols**: HTTP/2 tuned for AWS environments

## Prerequisites

:::info
Before proceeding, ensure you have deployed the Spark on EKS infrastructure following the [Infrastructure Setup Guide](/data-on-eks/docs/datastacks/processing/spark-on-eks/infra).
:::

**Required:**
- ✅ Spark on EKS infrastructure deployed
- ✅ S3 bucket for JAR files and dependencies
- ✅ IAM roles with S3 access permissions
- ✅ `kubectl` configured for cluster access

## Deployment Approaches

Mountpoint S3 can be deployed at **Pod level** or **Node level**, each with distinct trade-offs:

| Metric | Pod Level (PVC) | Node Level (HostPath) |
|--------|-----------------|----------------------|
| **Access Control** | Fine-grained via RBAC and service accounts | Shared access across all pods on node |
| **Scalability** | Individual PVCs increase overhead | Reduced configuration complexity |
| **Performance** | Isolated performance per pod | Potential contention if multiple pods access same bucket |
| **Flexibility** | Different pods access different datasets | All pods share same dataset (ideal for common JARs) |
| **Caching** | Each pod has separate cache (more S3 API calls) | Shared cache across pods (fewer API calls) |

**Recommendation:**
- **Pod Level**: Use for strict security/compliance or pod-specific datasets
- **Node Level**: Use for shared JAR dependencies across Spark jobs (cost-effective caching)

## Approach 1: Pod-Level Deployment with PVC

Deploying Mountpoint S3 at the pod level uses Persistent Volumes (PV) and Persistent Volume Claims (PVC) for fine-grained access control.

**Key Features:**
- S3 bucket becomes cluster-level resource
- Service accounts + RBAC limit PVC access
- Each pod has isolated mount and cache

**Limitation:** Does not support taints/tolerations (incompatible with GPU nodes)

For detailed Pod-level deployment instructions, refer to the [EKS Mountpoint S3 CSI Driver documentation](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html).

## Approach 2: Node-Level Deployment

Mounting S3 at the node level streamlines JAR dependency management by sharing a single mount across all pods on the node. This can be implemented via **USERDATA** or **DaemonSet**.

### Common Mountpoint S3 Arguments

Configure these arguments for optimal performance:

```bash
mount-s3 \
  --metadata-ttl indefinite \  # JAR files are immutable (read-only)
  --allow-other \              # Enable access for all users/pods
  --cache /tmp/mountpoint-cache \  # Enable caching to reduce S3 API calls
  <S3_BUCKET_NAME> /mnt/s3
```

**Key Parameters:**
- `--metadata-ttl indefinite`: No metadata refresh for static JARs
- `--allow-other`: Allows pods to access mount
- `--cache`: Caches files locally for repeated reads (critical for cost optimization)

For additional configuration options, see [Mountpoint S3 Configuration Docs](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md).

### Approach 2.1: USERDATA (Recommended)

Use USERDATA for new clusters or Karpenter-based auto-scaling where nodes are dynamically provisioned.

**Advantages:**
- Executes during node initialization
- Supports node-specific configurations (different buckets per NodePool)
- Integrates with Karpenter taints/tolerations for workload-specific nodes

**USERDATA Script:**

```bash
#!/bin/bash
set -e

# Update system and install dependencies
yum update -y
yum install -y wget fuse

# Download and install Mountpoint S3
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
yum install -y ./mount-s3.rpm

# Create mount point
mkdir -p /mnt/s3

# Mount S3 bucket with caching
/opt/aws/mountpoint-s3/bin/mount-s3 \
  --metadata-ttl indefinite \
  --allow-other \
  --cache /tmp/mountpoint-cache \
  <S3_BUCKET_NAME> /mnt/s3

# Verify mount
mount | grep /mnt/s3
```

**Karpenter Integration Example:**

```yaml
# Karpenter NodePool with USERDATA
apiVersion: karpenter.sh/v1beta1
kind: EC2NodeClass
metadata:
  name: spark-jars
spec:
  userData: |
    #!/bin/bash
    yum update -y && yum install -y wget fuse
    wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
    yum install -y ./mount-s3.rpm
    mkdir -p /mnt/s3-jars
    /opt/aws/mountpoint-s3/bin/mount-s3 \
      --metadata-ttl indefinite \
      --allow-other \
      --cache /tmp/mountpoint-cache \
      my-spark-jars-bucket /mnt/s3-jars
```

### Approach 2.2: DaemonSet (For Existing Clusters)

Use DaemonSets when you have static nodes that cannot be restarted or lack USERDATA customization.

**Architecture:**
1. **ConfigMap**: Script to install and maintain Mountpoint S3
2. **DaemonSet**: Pod on every node executes the script

**Security Considerations:**

:::danger
DaemonSet requires elevated privileges. Review security implications before production use.
:::

**Required Permissions:**
- `privileged: true` - Full host access for package installation
- `hostPID: true` - Enter host PID namespace via `nsenter`
- `hostIPC: true` - Access shared memory (if needed)
- `hostNetwork: true` - Download packages from internet

**DaemonSet Example:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mountpoint-s3-script
  namespace: spark-team-a
data:
  mount-s3.sh: |
    #!/bin/bash
    set -e

    # Configuration
    S3_BUCKET="${S3_BUCKET_NAME:-my-spark-jars}"
    MOUNT_POINT="/mnt/s3"
    CACHE_DIR="/tmp/mountpoint-cache"
    LOG_FILE="/var/log/mountpoint-s3.log"

    # Install Mountpoint S3 if not present
    if ! command -v mount-s3 &> /dev/null; then
      echo "Installing Mountpoint S3..." | tee -a $LOG_FILE
      wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
      yum install -y ./mount-s3.rpm
    fi

    # Mount loop with health checks
    while true; do
      if ! mountpoint -q $MOUNT_POINT; then
        echo "Mounting S3 bucket $S3_BUCKET..." | tee -a $LOG_FILE
        mkdir -p $MOUNT_POINT $CACHE_DIR
        mount-s3 \
          --metadata-ttl indefinite \
          --allow-other \
          --cache $CACHE_DIR \
          $S3_BUCKET $MOUNT_POINT
      fi
      sleep 60  # Health check interval
    done
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: mountpoint-s3
  namespace: spark-team-a
spec:
  selector:
    matchLabels:
      app: mountpoint-s3
  template:
    metadata:
      labels:
        app: mountpoint-s3
    spec:
      serviceAccountName: spark-team-a
      hostPID: true
      hostIPC: true
      hostNetwork: true
      containers:
      - name: mountpoint-installer
        image: amazonlinux:2023
        command:
        - /bin/bash
        - -c
        - |
          yum install -y util-linux
          cp /scripts/mount-s3.sh /host/tmp/mount-s3.sh
          chmod +x /host/tmp/mount-s3.sh
          nsenter --target 1 --mount --uts --ipc --net --pid -- /tmp/mount-s3.sh
        env:
        - name: S3_BUCKET_NAME
          value: "my-spark-jars"  # Replace with your bucket
        securityContext:
          privileged: true
        volumeMounts:
        - name: host
          mountPath: /host
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: host
        hostPath:
          path: /
      - name: scripts
        configMap:
          name: mountpoint-s3-script
```

:::warning
This example uses the `spark-team-a` namespace with pre-configured IRSA. In production:
- Create dedicated namespace for DaemonSet
- Use least-privilege IAM roles
- Limit S3 bucket access to specific paths
- Follow [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
:::

## Hands-On: Deploy Spark Job with Mountpoint S3

### Step 1: Prepare S3 Bucket with JARs

Upload Spark dependency JARs to S3:

```bash
cd data-stacks/spark-on-eks/examples/mountpoint-s3

# Upload sample JARs (Hadoop AWS, AWS SDK)
aws s3 cp hadoop-aws-3.3.1.jar s3://${S3_BUCKET}/jars/
aws s3 cp aws-java-sdk-bundle-1.12.647.jar s3://${S3_BUCKET}/jars/

# Or use provided script
chmod +x copy-jars-to-s3.sh
./copy-jars-to-s3.sh
```

### Step 2: Deploy DaemonSet (Node-Level Approach)

```bash
# Update S3_BUCKET in DaemonSet YAML
export S3_BUCKET=my-spark-jars

# Deploy DaemonSet
kubectl apply -f mountpoint-s3-daemonset.yaml

# Verify DaemonSet pods running
kubectl get pods -n spark-team-a -l app=mountpoint-s3
```

### Step 3: Submit Spark Job

Create SparkApplication that references mounted JARs:

```yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: spark-with-mountpoint
  namespace: spark-team-a
spec:
  type: Python
  mode: cluster
  image: "public.ecr.aws/data-on-eks/spark:3.5.3-scala2.12-java17-python3-ubuntu"
  mainApplicationFile: "local:///opt/spark/examples/src/main/python/pi.py"

  sparkConf:
    # Reference JARs from Mountpoint S3 mount
    "spark.jars": "file:///mnt/s3/jars/hadoop-aws-3.3.1.jar,file:///mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar"

    # S3 configuration
    "spark.hadoop.fs.s3a.aws.credentials.provider": "software.amazon.awssdk.auth.credentials.ContainerCredentialsProvider"

  driver:
    cores: 1
    memory: "512m"
    serviceAccount: spark-team-a
    nodeSelector:
      NodeGroupType: "SparkComputeOptimized"

  executor:
    cores: 1
    instances: 2
    memory: "512m"
    serviceAccount: spark-team-a
    nodeSelector:
      NodeGroupType: "SparkComputeOptimized"
```

```bash
kubectl apply -f spark-with-mountpoint.yaml
```

### Step 4: Monitor Job Execution

```bash
# Watch SparkApplication status
kubectl get sparkapplication -n spark-team-a -w

# Check driver logs
kubectl logs -n spark-team-a spark-with-mountpoint-driver -f

# Check executor logs
kubectl logs -n spark-team-a spark-with-mountpoint-exec-1 -f
```

## Verification

### Confirm JAR Loading from Mountpoint S3

Check executor logs for JAR copy operations:

```text
24/08/13 00:08:46 INFO Executor: Fetching file:/mnt/s3/jars/hadoop-aws-3.3.1.jar
24/08/13 00:08:46 INFO Utils: Copying /mnt/s3/jars/hadoop-aws-3.3.1.jar to /var/data/spark-...
24/08/13 00:08:46 INFO Executor: Adding file:/opt/spark/work-dir/./hadoop-aws-3.3.1.jar to class loader
```

### Verify Mountpoint S3 Installation on Node

Connect to node via SSM and verify:

```bash
# Check Mountpoint S3 version
mount-s3 --version

# Verify mount point
mount | grep /mnt/s3

# Check cached JARs (after first job run)
sudo ls -lh /tmp/mountpoint-cache/
```

**Expected Output:**
```
/mnt/s3 type fuse.mountpoint-s3 (rw,nosuid,nodev,relatime,user_id=0,group_id=0,allow_other)
```

### Verify Cache Effectiveness

After running multiple jobs, cache should contain JAR files:

```bash
sudo du -sh /tmp/mountpoint-cache/
# Example output: 256M  /tmp/mountpoint-cache/
```

**Cache benefits:**
- Subsequent jobs read from cache (no S3 API calls)
- Reduced S3 request costs
- Faster executor startup (no download latency)

## Production Best Practices

### 1. Cache Management

```bash
# Configure cache size limits
mount-s3 \
  --cache /tmp/mountpoint-cache \
  --max-cache-size 10737418240 \  # 10 GB limit
  my-bucket /mnt/s3
```

### 2. Logging and Debugging

Enable detailed logging for troubleshooting:

```bash
mount-s3 \
  --log-directory /var/log/mountpoint-s3 \
  --debug \
  my-bucket /mnt/s3
```

See [Mountpoint S3 Logging Documentation](https://github.com/awslabs/mountpoint-s3/blob/main/doc/LOGGING.md).

### 3. IAM Permissions

Minimal S3 permissions for read-only JAR access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-spark-jars",
        "arn:aws:s3:::my-spark-jars/jars/*"
      ]
    }
  ]
}
```

### 4. Multi-Bucket Strategy

Use different mount points for different workload types:

```bash
# Production JARs
mount-s3 prod-jars-bucket /mnt/s3/prod-jars

# Development JARs
mount-s3 dev-jars-bucket /mnt/s3/dev-jars

# ML models
mount-s3 ml-models-bucket /mnt/s3/ml-models
```

## Troubleshooting

### Mount Fails with "Permission Denied"

**Cause:** Missing `fuse` kernel module or user permissions

**Solution:**
```bash
# Install fuse
yum install -y fuse

# Verify fuse module loaded
lsmod | grep fuse

# Ensure --allow-other flag is set
```

### High S3 API Costs

**Cause:** Cache not enabled or cache eviction

**Solution:**
```bash
# Enable cache with sufficient size
mount-s3 \
  --cache /tmp/mountpoint-cache \
  --max-cache-size 53687091200 \  # 50 GB
  --metadata-ttl indefinite \
  my-bucket /mnt/s3
```

### Pods Cannot Access /mnt/s3

**Cause:** Missing `--allow-other` flag or incorrect permissions

**Solution:**
```bash
# Remount with --allow-other
umount /mnt/s3
mount-s3 --allow-other my-bucket /mnt/s3

# Verify permissions
ls -la /mnt/s3
```

### DaemonSet Pods in CrashLoopBackOff

**Cause:** Insufficient privileges or missing host access

**Solution:**
```yaml
# Ensure all required privileges are set
securityContext:
  privileged: true
hostPID: true
hostIPC: true
hostNetwork: true
```

## Cost Optimization

### S3 Request Cost Comparison

**Without Caching (per executor per job):**
- 10 executors × 5 JARs = 50 GET requests
- 1000 jobs/month = 50,000 GET requests
- Cost: ~$0.20/month (at $0.0004 per 1000 requests)

**With Caching (shared node cache):**
- First executor: 5 GET requests
- Subsequent executors: 0 GET requests (cache hit)
- 1000 jobs/month = 5,000 GET requests
- Cost: ~$0.02/month (90% reduction)

### Storage Cost Savings

**JARs in Container Image:**
- 5 JARs × 50 MB = 250 MB per image
- 10 image versions = 2.5 GB in ECR
- ECR cost: $0.25/month

**JARs in S3 with Mountpoint:**
- 5 JARs × 50 MB = 250 MB in S3
- S3 cost: $0.006/month (98% cheaper)

## Conclusion

Mountpoint for Amazon S3 enables cost-effective, high-performance JAR dependency management for Spark on EKS by:
- **Decoupling dependencies** from container images
- **Reducing build times** and image sizes
- **Enabling shared caching** across pods (node-level deployment)
- **Providing virtually unlimited storage** at low S3 costs

Choose **Node-Level Deployment** with DaemonSet or USERDATA for shared Spark JAR dependencies to maximize caching benefits and minimize S3 API costs.

## Related Resources

- [Mountpoint S3 GitHub Repository](https://github.com/awslabs/mountpoint-s3)
- [Mountpoint S3 Configuration Guide](https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md)
- [AWS CRT Library Documentation](https://docs.aws.amazon.com/sdkref/latest/guide/common-runtime.html)
- [EKS Mountpoint S3 CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html)
- [Infrastructure Setup Guide](/data-on-eks/docs/datastacks/processing/spark-on-eks/infra)
