---
title: Graviton Compute
sidebar_position: 5
---

# Graviton Compute

This blueprint demonstrates running Apache Spark workloads on ARM-based AWS Graviton processors for improved price-performance ratio with up to 40% better cost efficiency.

## Overview

AWS Graviton processors are custom ARM-based processors designed by AWS to deliver optimal price-performance for cloud workloads. This blueprint showcases how to run Spark applications on Graviton instances with native ARM64 optimizations.

## Key Features

- **Cost Efficiency**: Up to 40% better price-performance vs comparable x86 instances
- **ARM64 Optimization**: Native ARM compilation for Spark and dependencies
- **Graviton3 Support**: Latest generation Graviton processors with enhanced performance
- **Compatible Ecosystem**: Works with all major Spark libraries and frameworks
- **Auto-scaling**: Karpenter integration for efficient Graviton instance provisioning

## Prerequisites

Before deploying this blueprint, ensure you have:

- ✅ [Infrastructure deployed](/data-on-eks/docs/datastacks/spark-on-eks/infra)
- ✅ `kubectl` configured for your EKS cluster
- ✅ Karpenter configured for ARM64 instance provisioning

## Quick Deploy & Test

### 1. Deploy the Blueprint

```bash
# Navigate to data-stacks directory
cd data-stacks/spark-on-eks

# Apply the Graviton compute example
kubectl apply -f examples/karpenter/spark-app-graviton.yaml
```

### 2. Verify Deployment

```bash
# Check if the Spark application is created
kubectl get sparkapplications -n spark-team-a

# Monitor Karpenter provisioning ARM64 nodes
kubectl get nodes -l kubernetes.io/arch=arm64

# Watch pod scheduling on Graviton nodes
kubectl get pods -n spark-team-a -o wide --watch
```

### 3. Monitor Performance

```bash
# Check Spark application progress
kubectl describe sparkapplication spark-pi-graviton -n spark-team-a

# Monitor resource utilization on ARM64 nodes
kubectl top nodes -l kubernetes.io/arch=arm64

# View Spark History Server (if available)
kubectl port-forward -n spark-history svc/spark-history-server 18080:80
```

## Configuration Details

### Graviton Instance Selection

The blueprint uses Karpenter NodePool with ARM64 instance families:

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spark-graviton-nodepool
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["c7g.large", "c7g.xlarge", "c7g.2xlarge", "c7g.4xlarge", "c7g.8xlarge"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
```

### ARM64 Container Images

```yaml
spec:
  image: "public.ecr.aws/spark/spark:3.5.0-arm64"
  sparkConf:
    "spark.kubernetes.container.image": "public.ecr.aws/spark/spark:3.5.0-arm64"
    "spark.kubernetes.executor.podTemplateFile": "/opt/spark/conf/executor_pod_template.yaml"
```

### Resource Configuration

```yaml
spec:
  driver:
    cores: 1
    memory: "2g"
    serviceAccount: spark-team-a
  executor:
    cores: 2
    instances: 3
    memory: "4g"
    serviceAccount: spark-team-a
```

## Performance Validation

### Run Performance Tests

```bash
# Submit CPU-intensive workload
kubectl apply -f examples/karpenter/spark-app-graviton.yaml

# Monitor execution time
kubectl logs -n spark-team-a -l spark-role=driver --follow

# Compare with x86 baseline (if available)
kubectl apply -f examples/karpenter/spark-app-ondemand.yaml
```

### Benchmark Results

Expected performance improvements with Graviton3:

- **Cost**: 20-40% cost savings vs comparable x86 instances
- **Memory Bandwidth**: Up to 50% higher memory bandwidth
- **Encryption**: Hardware-accelerated encryption performance
- **Network**: Enhanced networking performance for distributed workloads

## Expected Results

✅ **Cost Optimization**: 20-40% reduction in compute costs
✅ **ARM64 Execution**: Native ARM64 Spark job execution
✅ **Auto-scaling**: Automatic Graviton instance provisioning
✅ **Performance**: Comparable or better performance vs x86
✅ **Compatibility**: Full compatibility with Spark ecosystem

## Troubleshooting

### Common Issues

**Pods not scheduling on ARM64 nodes:**
```bash
# Check NodePool configuration
kubectl describe nodepool spark-graviton-nodepool

# Verify ARM64 nodes are available
kubectl get nodes -l kubernetes.io/arch=arm64

# Check pod node affinity
kubectl describe pod <spark-pod-name> -n spark-team-a
```

**Container image issues:**
```bash
# Verify ARM64 image availability
docker manifest inspect public.ecr.aws/spark/spark:3.5.0-arm64

# Check image pull events
kubectl describe sparkapplication spark-pi-graviton -n spark-team-a
```

**Performance issues:**
```bash
# Check CPU and memory utilization
kubectl top nodes -l kubernetes.io/arch=arm64
kubectl top pods -n spark-team-a

# Review Spark metrics
kubectl logs -n spark-team-a -l spark-role=driver | grep -i "task.*finished"
```

## Advanced Configuration

### Mixed Architecture Clusters

Run both ARM64 and x86 workloads in the same cluster:

```yaml
# ARM64 NodePool
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: graviton-nodepool
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]

---
# x86 NodePool
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: x86-nodepool
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
```

### Custom ARM64 Images

Build custom Spark images for ARM64:

```dockerfile
FROM public.ecr.aws/spark/spark:3.5.0-arm64

# Add custom dependencies
COPY requirements.txt /opt/spark/
RUN pip3 install -r /opt/spark/requirements.txt

# Custom Spark configurations
COPY spark-defaults.conf /opt/spark/conf/
```

### Instance Type Optimization

Choose optimal Graviton instance types for your workload:

```yaml
# Compute optimized (C7g family)
- key: node.kubernetes.io/instance-type
  operator: In
  values: ["c7g.large", "c7g.xlarge", "c7g.2xlarge", "c7g.4xlarge"]

# Memory optimized (R7g family)
- key: node.kubernetes.io/instance-type
  operator: In
  values: ["r7g.large", "r7g.xlarge", "r7g.2xlarge", "r7g.4xlarge"]

# General purpose (M7g family)
- key: node.kubernetes.io/instance-type
  operator: In
  values: ["m7g.large", "m7g.xlarge", "m7g.2xlarge", "m7g.4xlarge"]
```

## Cost Optimization

### Spot Instance Strategy

```yaml
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
      nodeClassRef:
        name: default
      taints:
        - key: "graviton-spot"
          value: "true"
          effect: NoSchedule
```

### Right-sizing Recommendations

- **Small jobs**: c7g.large, c7g.xlarge
- **Medium jobs**: c7g.2xlarge, c7g.4xlarge
- **Large jobs**: c7g.8xlarge, c7g.12xlarge
- **Memory-intensive**: r7g family
- **Network-intensive**: c7gn family

## Related Blueprints

- [NVMe Storage](/data-on-eks/docs/datastacks/spark-on-eks/nvme-storage) - Combine with local NVMe storage
- [YuniKorn Gang Scheduling](/data-on-eks/docs/datastacks/spark-on-eks/yunikorn-gang-scheduling) - Gang scheduling with Graviton
- [Graviton Benchmarks](/data-on-eks/docs/datastacks/spark-on-eks/graviton-benchmarks) - Performance comparisons

## Additional Resources

- [AWS Graviton Technical Guide](https://aws.amazon.com/ec2/graviton/)
- [Graviton Performance Studies](https://aws.amazon.com/ec2/graviton/performance/)
- [ARM64 Container Images](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/docker-custom-images-arm.html)
