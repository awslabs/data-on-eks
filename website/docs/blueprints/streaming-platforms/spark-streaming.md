---
title: Spark Streaming from Kafka in EKS
sidebar_position: 6
---

This example showcases the usage of Spark Operator to create a producer and consumer stack using Kafka (Amazon MSK). The main idea is to show Spark Streaming working with Kafka, persisting data in Parquet format using Apache Iceberg.

## Deploy the EKS Cluster with all the add-ons and infrastructure needed to test this example

### Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

### Initialize Terraform

Navigate into the example directory and run the initialization script `install.sh`.

```bash
cd data-on-eks/streaming/spark-streaming/terraform/
./install.sh
```

### Export Terraform Outputs

After the Terraform script finishes, export the necessary variables to use them in the `sed` commands.

```bash
export CLUSTER_NAME=$(terraform output -raw cluster_name)
export PRODUCER_ROLE_ARN=$(terraform output -raw producer_iam_role_arn)
export CONSUMER_ROLE_ARN=$(terraform output -raw consumer_iam_role_arn)
export MSK_BROKERS=$(terraform output -raw bootstrap_brokers)
export REGION=$(terraform output -raw s3_bucket_region_spark_history_server)
export ICEBERG_BUCKET=$(terraform output -raw s3_bucket_id_iceberg_bucket)
```

### Update kubeconfig

Update the kubeconfig to verify the deployment.

```bash
aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME
kubectl get nodes
```

### Configuring Producer

In order to deploy the producer, update the `examples/producer/00_deployment.yaml` manifest with the variables exported from Terraform.

```bash
# Apply `sed` commands to replace placeholders in the producer manifest
sed -i.bak -e "s|__MY_PRODUCER_ROLE_ARN__|$PRODUCER_ROLE_ARN|g" \
           -e "s|__MY_AWS_REGION__|$REGION|g" \
           -e "s|__MY_KAFKA_BROKERS__|$MSK_BROKERS|g" \
           ../examples/producer/00_deployment.yaml
```

### Configuring Consumer

In order to deploy the Spark consumer, update the `examples/consumer/manifests/00_rbac_permissions.yaml` and `examples/consumer/manifests/01_spark_application.yaml` manifests with the variables exported from Terraform.

```bash
# Apply `sed` commands to replace placeholders in the consumer RBAC permissions manifest
sed -i.bak -e "s|__MY_CONSUMER_ROLE_ARN__|$CONSUMER_ROLE_ARN|g" \
           ../examples/consumer/manifests/00_rbac_permissions.yaml

# Apply `sed` commands to replace placeholders in the consumer Spark application manifest
sed -i.bak -e "s|__MY_BUCKET_NAME__|$ICEBERG_BUCKET|g" \
           -e "s|__MY_KAFKA_BROKERS_ADRESS__|$MSK_BROKERS|g" \
           ../examples/consumer/manifests/01_spark_application.yaml
```

### Deploy Producer and Consumer

After configuring the producer and consumer manifests, deploy them using kubectl.

```bash
# Deploy Producer
kubectl apply -f ../examples/producer/00_deployment.yaml

# Deploy Consumer
kubectl apply -f ../examples/consumer/manifests/
```

#### Checking Producer to MSK

First, let's see the producer logs to verify data is being created and flowing into MSK:

```bash
kubectl logs $(kubectl get pods -l app=producer -oname) -f
```

#### Checking Spark Streaming application with Spark Operator

For the consumer, we first need to get the `SparkApplication` that generates the `spark-submit` command to Spark Operator to create driver and executor pods based on the YAML configuration:

```bash
kubectl get SparkApplication -n spark-operator
```

You should see the `STATUS` equals `RUNNING`, now let's verify the driver and executors pods:

```bash
kubectl get pods -n spark-operator
```

You should see an output like below:

```bash
NAME                                     READY   STATUS      RESTARTS   AGE
kafkatoiceberg-1e9a438f4eeedfbb-exec-1   1/1     Running     0          7m15s
kafkatoiceberg-1e9a438f4eeedfbb-exec-2   1/1     Running     0          7m14s
kafkatoiceberg-1e9a438f4eeedfbb-exec-3   1/1     Running     0          7m14s
spark-consumer-driver                    1/1     Running     0          9m
spark-operator-9448b5c6d-d2ksp           1/1     Running     0          117m
spark-operator-webhook-init-psm4x        0/1     Completed   0          117m
```

We have `1 driver` and `3 executors` pods. Now, let's check the driver logs:

```bash
kubectl logs pod/spark-consumer-driver -n spark-operator
```

You should see only `INFO` logs indicating that the job is running.

### Verify Data Flow

After deploying both the producer and consumer, verify the data flow by checking the consumer application's output in the S3 bucket.

```bash
# List data in the Iceberg bucket
aws s3 ls s3://$ICEBERG_BUCKET/iceberg/warehouse/my_table/data/
```

### Cleaning Up Producer and Consumer Resources

To clean up only the producer and consumer resources, use the following commands:

```bash
# Clean up Producer resources
kubectl delete -f ../examples/producer/00_deployment.yaml

# Clean up Consumer resources
kubectl delete -f ../examples/consumer/manifests/
```

### Restoring `.yaml` Files from `.bak`

If you need to reset the `.yaml` files to their original state with placeholders, move the `.bak` files back to `.yaml`.

```bash
# Restore Producer manifest
mv ../examples/producer/00_deployment.yaml.bak ../examples/producer/00_deployment.yaml

# Restore Consumer RBAC permissions manifest
mv ../examples/consumer/manifests/00_rbac_permissions.yaml.bak ../examples/consumer/manifests/00_rbac_permissions.yaml

# Restore Consumer Spark application manifest
mv ../examples/consumer/manifests/01_spark_application.yaml.bak ../examples/consumer/manifests/01_spark_application.yaml
```

### Destroy the EKS Cluster and Resources

To clean up the entire EKS cluster and associated resources:

```bash
cd data-on-eks/streaming/spark-streaming/terraform/
terraform destroy
```
