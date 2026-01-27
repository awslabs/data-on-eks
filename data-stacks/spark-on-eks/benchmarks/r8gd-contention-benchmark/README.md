# R8GD Contention Benchmark

Benchmark to compare performance between r8gd.8xlarge (1 pod/node) vs r8gd.24xlarge (3 pods/node).

## Prerequisites

- EKS cluster with Karpenter and Spark Operator
- `spark-team-a` namespace with service account
- APerf DaemonSet deployed
- NodePools for r8gd-8xlarge-benchmark and r8gd-24xlarge-benchmark

## Quick Reference

```bash
# Deploy APerf DaemonSet (run once)
kubectl apply -f aperf-daemonset.yaml

# Check aperf pods
kubectl get pods -n spark-team-a -l app=aperf
```

---

## Test 1: r8gd.8xlarge (24 nodes × 1 pod)

### Step 1.1: Start Test 1

```bash
kubectl apply -f tpcds-benchmark-r8gd-8xlarge.yaml
```

### Step 1.2: Wait for Executors to Start

```bash
# Monitor nodes and executors
watch -n 10 'echo "=== Nodes ===" && kubectl get nodes -l karpenter.sh/nodepool=r8gd-8xlarge-benchmark --no-headers | wc -l && echo "/24 nodes" && echo "" && echo "=== Executors ===" && kubectl get pods -n spark-team-a -l spark-role=executor --field-selector=status.phase=Running --no-headers | wc -l && echo "running"'
```

Wait until all 24 nodes are ready and executors are running.

### Step 1.3: Start APerf Collection on All Nodes

```bash
# Start collection (3600 seconds = 60 min)
kubectl get pods -n spark-team-a -l app=aperf -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | while read POD; do
  echo "Starting aperf on $POD..."
  kubectl exec -n spark-team-a $POD -- bash -c "
    nohup /usr/local/bin/collect-metrics.sh 3600 r8gd-8xlarge-test > /var/log/aperf/collection.log 2>&1 &
    echo \$! > /var/log/aperf/collect.pid
  " &
done
wait
echo "APerf collection started on all nodes"
```

### Step 1.4: Monitor Test Progress

```bash
watch -n 30 'kubectl get sparkapplication -n spark-team-a | grep r8gd-8xlarge'
```

### Step 1.5: After Test Completes - Sync Results to S3

Results are auto-synced by collect-metrics.sh, but you can manually sync:

```bash
kubectl get pods -n spark-team-a -l app=aperf -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | while read POD; do
  echo "Syncing $POD..."
  kubectl exec -n spark-team-a $POD -- /usr/local/bin/sync-to-s3.sh &
done
wait
echo "All results synced"
```

### Step 1.6: Cleanup Test 1

```bash
kubectl delete sparkapplication tpcds-benchmark-r8gd-8xlarge -n spark-team-a

# Wait for nodes to scale down (~15 min) or delete nodeclaims manually
kubectl delete nodeclaims -l karpenter.sh/nodepool=r8gd-8xlarge-benchmark
```

---

## Test 2: r8gd.24xlarge (8 nodes × 3 pods)

### Step 2.1: Start Test 2

```bash
kubectl apply -f tpcds-benchmark-r8gd-24xlarge.yaml
```

### Step 2.2: Wait for Executors to Start

```bash
watch -n 10 'echo "=== Nodes ===" && kubectl get nodes -l karpenter.sh/nodepool=r8gd-24xlarge-benchmark --no-headers | wc -l && echo "/8 nodes" && echo "" && echo "=== Executors ===" && kubectl get pods -n spark-team-a -l spark-role=executor --field-selector=status.phase=Running --no-headers | wc -l && echo "running"'
```

Wait until all 8 nodes are ready and executors are running.

### Step 2.3: Start APerf Collection on All Nodes

```bash
kubectl get pods -n spark-team-a -l app=aperf -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | while read POD; do
  echo "Starting aperf on $POD..."
  kubectl exec -n spark-team-a $POD -- bash -c "
    nohup /usr/local/bin/collect-metrics.sh 3600 r8gd-24xlarge-test > /var/log/aperf/collection.log 2>&1 &
    echo \$! > /var/log/aperf/collect.pid
  " &
done
wait
echo "APerf collection started on all nodes"
```

### Step 2.4: Monitor Test Progress

```bash
watch -n 30 'kubectl get sparkapplication -n spark-team-a | grep r8gd-24xlarge'
```

### Step 2.5: After Test Completes - Sync Results to S3

```bash
kubectl get pods -n spark-team-a -l app=aperf -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | while read POD; do
  echo "Syncing $POD..."
  kubectl exec -n spark-team-a $POD -- /usr/local/bin/sync-to-s3.sh &
done
wait
echo "All results synced"
```

### Step 2.6: Cleanup Test 2

```bash
kubectl delete sparkapplication tpcds-benchmark-r8gd-24xlarge -n spark-team-a
kubectl delete nodeclaims -l karpenter.sh/nodepool=r8gd-24xlarge-benchmark
```

---

## View Results

### S3 Location

```
s3://sS3_BUCKET/aperf-results/
├── r8gd-8xlarge-test/
│   └── r8gd.8xlarge-<instance-id>/
│       ├── metadata.txt
│       ├── psi.log          # CPU/memory/IO pressure metrics
│       ├── numa.log         # NUMA statistics
│       └── aperf.log        # APerf output
└── r8gd-24xlarge-test/
    └── r8gd.24xlarge-<instance-id>/
        └── ...
```

### Download Results

```bash
# Download all results
aws s3 sync s3://sS3_BUCKET/aperf-results/ ./aperf-results/

# View PSI data for a specific node
cat ./aperf-results/r8gd-8xlarge-test/r8gd.8xlarge-*/psi.log | head -50
```

### Key Metrics to Compare

1. **PSI CPU stalls** - `some avg10` and `full avg10` values
2. **NUMA statistics** - Cross-node memory access patterns
3. **Memory pressure** - Memory throttling indicators

---

## Test Configuration

| Test | Instance | Nodes | Pods/Node | vCPU/Pod | Memory/Pod |
|------|----------|-------|-----------|----------|------------|
| Test 1 | r8gd.8xlarge | 24 | 1 | 31 | 200 GB |
| Test 2 | r8gd.24xlarge | 8 | 3 | 31 | 200 GB |

Both tests use 24 total executors with 744 vCPU and 4.8 TB total memory.

---

## Troubleshooting

### Nodes not provisioning

```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# Check nodeclaim status
kubectl get nodeclaims -l karpenter.sh/nodepool=r8gd-8xlarge-benchmark
kubectl describe nodeclaim <name>
```

### APerf pods not running

```bash
# Check if DaemonSet is deployed
kubectl get daemonset aperf-collector -n spark-team-a

# Check pod status
kubectl describe pod -n spark-team-a -l app=aperf
```

### S3 upload failing

```bash
# Check S3 access from aperf pod
kubectl exec -n spark-team-a <aperf-pod> -- aws s3 ls s3://sS3_BUCKET/
```
