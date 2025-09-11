# Spark Benchmarking on Graviton Instances

This document provides a step-by-step guide to execute Spark benchmarks on Graviton instances, specifically for comparing Graviton3 and Graviton4.

 - r6g Benchmark Job: analytics/terraform/spark-k8s-operator/examples/benchmark/tpcds-benchmark-1t-r6g.yaml
 - r8g Benchmark Job: analytics/terraform/spark-k8s-operator/examples/benchmark/tpcds-benchmark-1t-r8g.yaml

## Steps to Execute the Job

### Step 1: Deploy the Spark Operator Blueprint
Deploy the Spark Operator Blueprint with YuniKorn scheduler. Follow the instructions provided in the [Data on EKS - Spark Operator with YuniKorn documentation](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn).

### Step 2: Create an S3 Bucket for TPC-DS Data
Set up a dedicated S3 bucket to store the TPC-DS data output.

### Step 3: Configure the S3 Bucket in the YAML File
Replace `<S3_BUCKET>` with the name of your S3 bucket in the provided YAML configuration file.

 - **r6g Benchmark Job**: analytics/terraform/spark-k8s-operator/examples/benchmark/tpcds-benchmark-1t-r6g.yaml
 - **r8g Benchmark Job**: analytics/terraform/spark-k8s-operator/examples/benchmark/tpcds-benchmark-1t-r8g.yaml

### Step 4: Ensure an EKS Managed Node Group with `r6g` Instances
Make sure an EKS managed node group with `r6g` instances is available. Check the `eks.tf` file under [EKS Terraform Config](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/eks.tf) for configuration details.

### Step 5: Apply the Configuration
Run the following command to apply the YAML configuration file:

```bash
kubectl apply -f <filename>
```

### Step 6: Verify Benchmark Results in S3
After the job completes, navigate to the output path in your S3 bucket as specified in the YAML config file. You should see:

One JSON file with the benchmark results
One CSV file with the benchmark results
The output files contain detailed benchmarking data for analysis.
