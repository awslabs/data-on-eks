# Spark Shuffle Storage Comparison: S3 Express vs EBS

## Prerequisites

Create test data using the taxi trip script:

```bash
../../scripts/taxi-trip-execute.sh
```

## Deployment Options

### Option A: S3 Express Shuffle Storage

1. Deploy PV/PVC for S3 Express:
```bash
./deploy-s3express-pv-pvc.sh
```
Enter when prompted:
- S3 Express bucket name (e.g., `my-bucket--usw2-az1--x-s3`)
- AWS region (e.g., `us-west-2`)
- Availability zone (e.g., `us-west-2b`)

2. Deploy Spark job:
```bash
./deploy-spark-job.sh
```
Enter when prompted:
- S3 bucket name for data/logs (e.g., `my-data-bucket`)
- Availability zone (e.g., `us-west-2b`)

### Option B: EBS Shuffle Storage

Deploy Spark job with dynamic EBS PVC:
```bash
./deploy-ebs-spark-job.sh
```
Enter when prompted:
- S3 bucket name for data/logs (e.g., `my-data-bucket`)
- Availability zone (e.g., `us-west-2b`)

## Delete and Redeploy Job

To delete a failed job and redeploy:

```bash
# Delete S3 Express job
kubectl delete sparkapplication taxi-trip-s3express -n spark-s3-express

# Delete EBS job
kubectl delete sparkapplication taxi-trip-ebs -n spark-s3-express

# Redeploy (choose one)
./deploy-spark-job.sh      # S3 Express version
./deploy-ebs-spark-job.sh  # EBS version
```

## Verification

Check the created resources:

```bash
# Check Spark jobs
kubectl get sparkapplications -n spark-s3-express

# For S3 Express option - check PV/PVC
kubectl get pv spark-s3-shuffle-pv
kubectl get pvc spark-s3-shuffle-pvc -n spark-s3-express

# For EBS option - check dynamic PVCs
kubectl get pvc -n spark-s3-express -l spark-role=driver
kubectl get pvc -n spark-s3-express -l spark-role=executor
```