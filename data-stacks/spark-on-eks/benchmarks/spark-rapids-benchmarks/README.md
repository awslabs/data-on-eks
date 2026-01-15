# TPC-DS Benchmark with NVIDIA RAPIDS GPU on EKS

Run TPC-DS 1TB benchmark with GPU acceleration using NVIDIA RAPIDS on Amazon EKS.

## ⚠️ Cost Warning

**GPU instances are expensive!** A g6.2xlarge costs $0.98/hour. Running this benchmark on 4 GPU executors + 1 CPU driver for 2 hours will cost approximately **$8-9**.

Always check current AWS pricing and set cost alerts before running GPU workloads.

## Quick Start

### Prerequisites

- EKS cluster with Spark Operator installed
- Karpenter configured for g6.2xlarge GPU nodes
- NVIDIA device plugin running
- Namespace `spark-team-a` with service account
- S3 bucket with Pod Identity/IRSA access

### Step 1: Generate TPC-DS Test Data (Required)

**You must generate the 1TB TPC-DS dataset first:**

```bash
# Update S3 bucket name in the YAML
export S3_BUCKET=your-bucket-name

# Generate 1TB TPC-DS data in Parquet format
cd data-stacks/spark-on-eks/benchmarks/benchmark-testdata-generation
envsubst < tpcds-benchmark-data-generation-1t.yaml | kubectl apply -f -

# Monitor data generation (takes ~30-60 minutes)
kubectl get sparkapplication -n spark-team-a -w

# Verify data is generated
aws s3 ls s3://$S3_BUCKET/TPCDS-TEST-1TB/ --recursive --summarize
```

**Expected Output:**
- S3 path: `s3://$S3_BUCKET/TPCDS-TEST-1TB/`
- Format: Parquet files
- Size: ~1TB compressed

### Step 2: Build or Use Docker Image

**Option A: Use Pre-built Image (Recommended)**

```bash
# Use the pre-built image
docker pull varabonthu/spark352-rapids25-tpcds4-cuda12-9:v1.1.0
```

**Option B: Build Your Own Image**

```bash
cd data-stacks/spark-on-eks/benchmarks/spark-rapids-benchmarks/

# Build the image
docker build \
  -f Dockerfile-spark352-rapids25-tpcds4-cuda12-9 \
  -t your-registry/spark-rapids-tpcds:v1.0.0 .

# Push to your registry
docker push your-registry/spark-rapids-tpcds:v1.0.0
```

**Image includes:**
- Apache Spark 3.5.2
- NVIDIA RAPIDS 25.12.0
- CUDA 12.9
- TPC-DS toolkit v4.0 (with v2.4 and v4.0 query specifications)
- Benchmark application

### Step 3: Run the Benchmark

```bash
# Update S3 bucket and image in the YAML
cd data-stacks/spark-on-eks/benchmarks/spark-rapids-benchmarks/

# Edit tpcds-benchmark-rapids.yaml and update:
# 1. S3 bucket name: Replace $S3_BUCKET with your bucket
# 2. Container image (if using custom image)

# Submit the benchmark job
kubectl apply -f tpcds-benchmark-rapids.yaml
```

**Monitor the job:**

```bash
# Watch job status
kubectl get sparkapplication tpcds-benchmark-rapids -n spark-team-a -w

# Check driver logs
kubectl logs -n spark-team-a -l spark-role=driver -f

# View GPU utilization
EXECUTOR_POD=$(kubectl get pods -n spark-team-a -l spark-role=executor -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n spark-team-a $EXECUTOR_POD -- nvidia-smi
```

### Step 4: Get Results

```bash
# Results are saved to S3
aws s3 ls s3://$S3_BUCKET/TPCDS-TEST-1TB-RESULT-RAPIDS-GPU/

# Download results
aws s3 sync s3://$S3_BUCKET/TPCDS-TEST-1TB-RESULT-RAPIDS-GPU/ ./results/

# View query execution times
cat ./results/summary.csv/part-*.csv
```

## Benchmark Configuration

**Current setup:**
- Driver: 1× c6i.2xlarge (4 cores, 8GB + 2GB overhead)
- Executors: 4× g6.2xlarge (4 cores, 16GB + 12GB overhead, 1× L4 GPU each)
- Dataset: TPC-DS 1TB (104 queries, 3 iterations)
- Expected runtime: ~2 hours

**Key RAPIDS settings:**
- GPU memory: 80% allocation with ASYNC pool
- Pinned memory: 2GB for CPU-GPU transfers
- Shuffle: RAPIDS shuffle manager (MULTITHREADED mode)
- Concurrent GPU tasks: 1 per GPU (prevents OOM)

## Troubleshooting

**GPU not detected:**
```bash
# Check NVIDIA device plugin
kubectl get pods -n kube-system | grep nvidia

# Verify GPU nodes
kubectl get nodes -l node.kubernetes.io/instance-type=g6.2xlarge
```

**Out of GPU memory:**
- Reduce executors or cores per executor
- Decrease `spark.rapids.sql.concurrentGpuTasks` from 1 to 1
- Lower `spark.rapids.memory.gpu.allocFraction` from 0.8 to 0.6

**Job stuck in pending:**
```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Check node capacity
kubectl get nodes -o wide
```

**S3 access denied:**
```bash
# Verify service account IAM role
kubectl describe sa spark-team-a -n spark-team-a

# Test S3 access
aws s3 ls s3://$S3_BUCKET/
```

## Cleanup

```bash
# Delete the benchmark job
kubectl delete sparkapplication tpcds-benchmark-rapids -n spark-team-a

# (Optional) Delete test data
aws s3 rm s3://$S3_BUCKET/TPCDS-TEST-1TB/ --recursive

# (Optional) Delete results
aws s3 rm s3://$S3_BUCKET/TPCDS-TEST-1TB-RESULT-RAPIDS-GPU/ --recursive
```

## Cost Estimation

Approximate costs for running this benchmark in us-west-2 (on-demand pricing):

| Resource | Instance | Hours | Rate/Hour | Cost |
|----------|----------|-------|-----------|------|
| Driver | 1× c6i.2xlarge | 2 | $0.34 | $0.68 |
| Executors | 4× g6.2xlarge | 2 | $0.9776 | $7.82 |
| **Total** | | | | **~$8.50** |

**Notes:**
- GPU instance pricing: g6.2xlarge = $0.9776/hour (8 vCPU, 32 GiB RAM, 1× L4 GPU)
- CPU instance pricing: c6i.2xlarge = $0.34/hour (8 vCPU, 16 GiB RAM)
- Costs vary by region and may change. Always check [current AWS pricing](https://aws.amazon.com/ec2/pricing/on-demand/).

## References

- [NVIDIA RAPIDS Documentation](https://docs.nvidia.com/spark-rapids/user-guide/latest/)
- [TPC-DS Benchmark Specification](http://www.tpc.org/tpcds/)
- [Benchmark Results Documentation](/docs/benchmarks/spark-rapids-gpu-benchmark)
- [Dockerfile](./Dockerfile-spark352-rapids25-tpcds4-cuda12-9)

**Benchmark Results:**
- [TPC-DS v2.4 Results](./results/sparkrapids-benchmark-tpcds24-results.csv) - Primary benchmark results
- [TPC-DS v4.0 Results](./results/sparkrapids-benchmark-tpcds40-results.csv) - Comparison run results
- [v2.4 vs v4.0 Comparison](./results/sparkrapids-benchmark-tpcds24-vs-tpcds40-comparison.csv) - Performance comparison

## Need Help?

- Review the [full benchmark documentation](/docs/benchmarks/spark-rapids-gpu-benchmark)
- Check [NVIDIA RAPIDS configuration guide](https://nvidia.github.io/spark-rapids/docs/configs.html)
- See [AWS EKS GPU best practices](https://docs.aws.amazon.com/eks/latest/userguide/gpu-ami.html)
