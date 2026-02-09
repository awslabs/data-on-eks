# Running Celeborn Benchmarks

To run Celeborn benchmarks in Kubernetes with Karpenter, follow the steps below.

## Setup

1. Copy the `helm-values` directory to `data-stacks/spark-on-eks/terraform`
2. In `data-stacks/spark-on-eks/terraform/data-stack.tfvars`, set `enable_celeborn` to `true`
3. Change directory to `data-stacks/spark-on-eks`
4. Make sure you have AWS credentials configured. This will spin up an EKS cluster and install components necessary to run the benchmark
5. Run `./deploy.sh`
6. Wait for the script to finish

## Running the Benchmarks

### Data Generation

1. Once your environment is up, run `terraform -chdir=terraform/_local output -raw s3_bucket_id_spark_history_server`. The output is the S3 bucket name created to store benchmark data and results
2. In `benchmarks/celeborn-benchmarks/tpcds-benchmark-data-generation-3t.yaml`, replace `<S3_BUCKET>` with the output from step 1
   - The scale factor in this benchmark is set to 3000GB. To test with different values, update the Scale Factor arguments in the file
3. Submit the Spark application to your cluster: `kubectl apply -f benchmarks/celeborn-benchmarks/tpcds-benchmark-data-generation-3t.yaml`
4. Monitor the job: `kubectl get sparkapplication -n spark-team-a -w`
5. Wait for data generation to complete. This takes approximately 3 hours for 3TB of data
6. Generated data is stored in `s3://<S3_BUCKET>/TPCDS-TEST-3TB`

### Benchmarks

#### Running the Benchmark with Spark Default Shuffler

1. In `benchmarks/celeborn-benchmarks/tpcds-benchmark-3t-ebs-builtin-shuffler.yaml`, replace `<S3_BUCKET>` with your bucket name from the data generation step above
2. This file runs the TPC-DS benchmark with the default shuffler to measure baseline performance. It runs the benchmark 10 times
3. Submit the Spark application: `kubectl apply -f benchmarks/celeborn-benchmarks/tpcds-benchmark-3t-ebs-builtin-shuffler.yaml`
4. Monitor the job: `kubectl get sparkapplication -n spark-team-a -w`
5. Wait for completion. This typically takes approximately 6 hours
6. Results are stored in `s3://<S3_BUCKET>/TPCDS-TEST-3T-RESULT/` as CSV and JSON files

#### Running the Benchmark with Apache Celeborn

1. In `benchmarks/celeborn-benchmarks/tpcds-benchmark-3t-ebs-celeborn.yaml`, replace `<S3_BUCKET>` with your bucket name from the data generation step above
2. This file contains the minimum configuration necessary to use Apache Celeborn with Spark
3. Submit the Spark application: `kubectl apply -f benchmarks/celeborn-benchmarks/tpcds-benchmark-3t-ebs-celeborn.yaml`
4. Monitor the job: `kubectl get sparkapplication -n spark-team-a -w`
5. Wait for completion. This typically takes approximately 6 hours
6. Results are stored in `s3://<S3_BUCKET>/TPCDS-TEST-3T-RESULT/` as CSV and JSON files

## Cleanup

1. Change directory to `data-stacks/spark-on-eks`
2. Run `./cleanup.sh`

**Note:** This will destroy the entire EKS cluster and all associated resources.
