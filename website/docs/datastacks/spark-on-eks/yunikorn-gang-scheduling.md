---
title: YuniKorn Gang Scheduling
sidebar_position: 4
---

# YuniKorn Gang Scheduling

This blueprint demonstrates advanced batch scheduling with YuniKorn for guaranteed resource allocation and gang scheduling for multi-executor Spark jobs on Amazon EKS.

## Overview

YuniKorn gang scheduling ensures that all pods in a Spark application are scheduled together or not at all, preventing resource deadlocks and improving cluster utilization for large multi-executor jobs.

## Key Features

- **Gang Scheduling**: All-or-nothing scheduling for Spark applications
- **Resource Guarantees**: Prevents partial scheduling and resource deadlocks
- **Queue Management**: Hierarchical resource queues for multi-tenancy
- **Fair Sharing**: Balanced resource allocation across applications
- **Preemption Support**: Higher priority jobs can preempt lower priority ones

## Prerequisites

Before deploying this blueprint, ensure you have:

- ✅ [Infrastructure deployed](/data-on-eks/docs/datastacks/spark-on-eks/infra)
- ✅ `kubectl` configured for your EKS cluster
- ✅ YuniKorn scheduler deployed via ArgoCD

## Quick Deploy & Test

### 1. Deploy the Blueprint

```bash
# Navigate to data-stacks directory
cd data-stacks/spark-on-eks

# Apply the YuniKorn gang scheduling example
kubectl apply -f examples/karpenter/nvme-storage-yunikorn-gang-scheduling.yaml
```

### 2. Verify Deployment

```bash
# Check if the Spark application is created
kubectl get sparkapplications -n spark-team-a

# Monitor YuniKorn scheduling
kubectl logs -n yunikorn -l app=yunikorn-scheduler

# Check gang scheduling queue
kubectl get pods -n spark-team-a --watch
```

### 3. Monitor Gang Scheduling

```bash
# View YuniKorn web UI (if enabled)
kubectl port-forward -n yunikorn svc/yunikorn-service 9080:9080

# Check application queue status
kubectl describe sparkapplication yunikorn-spark-app -n spark-team-a

# Monitor resource allocation
kubectl top nodes
kubectl top pods -n spark-team-a
```

## Configuration Details

### Gang Scheduling Configuration

The blueprint includes YuniKorn-specific annotations for gang scheduling:

```yaml
metadata:
  annotations:
    yunikorn.apache.org/schedulingPolicyParameters: |
      gangSchedulingStyle: Hard
      gangSchedulingInitialTimeout: 30s
    yunikorn.apache.org/task-group-name: "spark-driver"
    yunikorn.apache.org/task-groups: |
      - name: "spark-driver"
        minMember: 1
        minResource:
          cpu: 1
          memory: 1Gi
      - name: "spark-executor"
        minMember: 2
        minResource:
          cpu: 2
          memory: 4Gi
```

### Queue Configuration

```yaml
spec:
  driver:
    labels:
      queue: "root.spark.batch"
      applicationId: "yunikorn-spark-app"
  executor:
    labels:
      queue: "root.spark.batch"
      applicationId: "yunikorn-spark-app"
```

## Performance Validation

### Test Gang Scheduling Behavior

```bash
# Submit multiple applications to test queue management
for i in {1..3}; do
  envsubst < examples/karpenter/nvme-storage-yunikorn-gang-scheduling.yaml | \
    sed "s/yunikorn-spark-app/yunikorn-spark-app-$i/g" | \
    kubectl apply -f -
done

# Monitor scheduling order and resource allocation
kubectl get sparkapplications -n spark-team-a --watch
```

### Verify Resource Allocation

```bash
# Check that all executor pods are scheduled together
kubectl get pods -n spark-team-a -l spark-role=executor

# Verify no partial scheduling occurred
kubectl describe nodes | grep -A 5 "Allocated resources"
```

## Expected Results

✅ **Gang Scheduling**: All Spark executor pods scheduled simultaneously
✅ **Resource Efficiency**: No partial allocations or resource waste
✅ **Queue Management**: Applications processed in priority order
✅ **Deadlock Prevention**: No resource contention between applications
✅ **Performance**: Improved job completion times for large applications

## Troubleshooting

### Common Issues

**Pods stuck in Pending state:**
```bash
# Check YuniKorn scheduler logs
kubectl logs -n yunikorn -l app=yunikorn-scheduler --tail=100

# Verify gang scheduling configuration
kubectl describe sparkapplication yunikorn-spark-app -n spark-team-a
```

**Resource allocation problems:**
```bash
# Check available cluster resources
kubectl describe nodes | grep -E "(Capacity|Allocatable)"

# Review queue configuration
kubectl get configmap yunikorn-configs -n yunikorn -o yaml
```

**Application not scheduling:**
```bash
# Check application events
kubectl describe sparkapplication yunikorn-spark-app -n spark-team-a

# Verify queue exists
kubectl logs -n yunikorn -l app=yunikorn-scheduler | grep -i queue
```

## Advanced Configuration

### Custom Queue Hierarchies

Create custom queue configurations for multi-tenancy:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: yunikorn-configs
  namespace: yunikorn
data:
  queues.yaml: |
    partitions:
      - name: default
        queues:
          - name: root
            queues:
              - name: spark
                queues:
                  - name: production
                    resources:
                      guaranteed: {memory: 100Gi, vcore: 50}
                      max: {memory: 200Gi, vcore: 100}
                  - name: development
                    resources:
                      guaranteed: {memory: 50Gi, vcore: 25}
                      max: {memory: 100Gi, vcore: 50}
```

### Preemption Policies

Configure preemption for priority-based scheduling:

```yaml
metadata:
  annotations:
    yunikorn.apache.org/schedulingPolicyParameters: |
      gangSchedulingStyle: Hard
      preemptionPolicy: fence
      preemptionDelay: 30s
```

## Cost Optimization

- **Resource Efficiency**: Gang scheduling prevents resource fragmentation
- **Cluster Utilization**: Better packing with guaranteed allocations
- **Job Latency**: Faster application startup with immediate resource allocation
- **Spot Instance Support**: Works with Karpenter spot instance provisioning

## Related Blueprints

- [NVMe Storage](/data-on-eks/docs/datastacks/spark-on-eks/nvme-storage) - High-performance local storage
- [Graviton Compute](/data-on-eks/docs/datastacks/spark-on-eks/graviton-compute) - ARM-based cost optimization
- [EBS PVC Storage](/data-on-eks/docs/datastacks/spark-on-eks/ebs-pvc-storage) - Persistent storage with gang scheduling

## Additional Resources

- [YuniKorn Documentation](https://yunikorn.apache.org/docs/)
- [Gang Scheduling Guide](https://yunikorn.apache.org/docs/user_guide/gang_scheduling)
- [Spark on Kubernetes Best Practices](https://spark.apache.org/docs/latest/running-on-kubernetes.html)
