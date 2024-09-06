---
title: Spark Streaming from Kafka in EKS
sidebar_position: 6
---

:::danger
**DEPRECATION NOTICE**

This blueprint will be deprecated and eventually removed from this GitHub repository on **October 27, 2024**. No bugs will be fixed, and no new features will be added. The decision to deprecate is based on the lack of demand and interest in this blueprint, as well as the difficulty in allocating resources to maintain a blueprint that is not actively used by any users or customers.

If you are using this blueprint in production, please add yourself to the [adopters.md](https://github.com/awslabs/data-on-eks/blob/main/ADOPTERS.md) page and raise an issue in the repository. This will help us reconsider and possibly retain and continue to maintain the blueprint. Otherwise, you can make a local copy or use existing tags to access it.
:::


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

# Apply sed to delete topic manifest, this can be used to delete kafka topic and start the stack once again
sed -i.bak -e "s|__MY_KAFKA_BROKERS__|$MSK_BROKERS|g" \
           ../examples/producer/01_delete_topic.yaml
```

### Configuring Consumer

In order to deploy the Spark consumer, update the `examples/consumer/manifests/01_spark_application.yaml` manifests with the variables exported from Terraform.

```bash
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

After deploying both the producer and consumer, verify the data flow by checking the consumer application's output in the S3 bucket. You can run the `s3_automation` script to get a live view of the data size in your S3 bucket.

Follow these steps:

1. **Navigate to the `s3_automation` directory**:

    ```bash
    cd ../examples/s3_automation/
    ```

2. **Run the `s3_automation` script**:

    ```bash
    python app.py
    ```

    This script will continuously monitor and display the total size of your S3 bucket, giving you a real-time view of data being ingested. You can choose to view the bucket size or delete specific directories as needed.


#### Using the `s3_automation` Script

The `s3_automation` script offers two primary functions:

- **Check Bucket Size**: Continuously monitor and display the total size of your S3 bucket.
- **Delete Directory**: Delete specific directories within your S3 bucket.

Here's how to use these functions:

1. **Check Bucket Size**:
    - When prompted, enter `size` to get the current size of your bucket in megabytes (MB).

2. **Delete Directory**:
    - When prompted, enter `delete` and then provide the directory prefix you wish to delete (e.g., `myfolder/`).

## Tuning the Producer and Consumer for Better Performance

After deploying the producer and consumer, you can further optimize the data ingestion and processing by adjusting the number of replicas for the producer and the executor configuration for the Spark application. Here are some suggestions to get you started:

### Adjusting the Number of Producer Replicas

You can increase the number of replicas of the producer deployment to handle a higher rate of message production. By default, the producer deployment is configured with a single replica. Increasing this number allows more instances of the producer to run concurrently, increasing the overall throughput.

To change the number of replicas, update the `replicas` field in `examples/producer/00_deployment.yaml`:

```yaml
spec:
  replicas: 200  # Increase this number to scale up the producer
```

You can also adjust the environment variables to control the rate and volume of messages produced:

```yaml
env:
  - name: RATE_PER_SECOND
    value: "200000"  # Increase this value to produce more messages per second
  - name: NUM_OF_MESSAGES
    value: "20000000"  # Increase this value to produce more messages in total
```

Apply the updated deployment:

```bash
kubectl apply -f ../examples/producer/00_deployment.yaml
```

### Tuning Spark Executors for Better Ingestion Performance

To handle the increased data volume efficiently, you can add more executors to the Spark application or increase the resources allocated to each executor. This will allow the consumer to process data faster and reduce ingestion time.

To adjust the Spark executor configuration, update `examples/consumer/manifests/01_spark_application.yaml`:

```yaml
spec:
  dynamicAllocation:
    enabled: true
    initialExecutors: 5
    minExecutors: 5
    maxExecutors: 50  # Increase this number to allow more executors
  executor:
    cores: 4  # Increase CPU allocation
    memory: "8g"  # Increase memory allocation
```

Apply the updated Spark application:

```bash
kubectl apply -f ../examples/consumer/manifests/01_spark_application.yaml
```

### Verify and Monitor

After making these changes, monitor the logs and metrics to ensure the system is performing as expected. You can check the producer logs to verify data production and the consumer logs to verify data ingestion and processing.

To check producer logs:

```bash
kubectl logs $(kubectl get pods -l app=producer -oname) -f
```

To check consumer logs:

```bash
kubectl logs pod/spark-consumer-driver -n spark-operator
```

> Can use verify dataflow script again

### Summary

By adjusting the number of producer replicas and tuning the Spark executor settings, you can optimize the performance of your data pipeline. This allows you to handle higher ingestion rates and process data more efficiently, ensuring that your Spark Streaming application can keep up with the increased data volume from Kafka.

Feel free to experiment with these settings to find the optimal configuration for your workload. Happy streaming!


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


# Restore Consumer Spark application manifest
mv ../examples/consumer/manifests/01_spark_application.yaml.bak ../examples/consumer/manifests/01_spark_application.yaml
```

### Destroy the EKS Cluster and Resources

To clean up the entire EKS cluster and associated resources:

```bash
cd data-on-eks/streaming/spark-streaming/terraform/
terraform destroy
```
