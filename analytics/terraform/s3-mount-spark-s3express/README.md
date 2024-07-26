# Spark S3 Mount Benchmark Workshop

## Description
Spark S3 Benchmark Mount Workshop

## Install Prerequisites
- AWS CLI
- kubectl
- helm
- python 3.11

## Configure AWS CLI
aws configure

Note: At the time of creation of this workshop, S3 Express One Zone is supported only in certails AZs in following regiosn, us-east-1, us-west-2, eu-north-1 and ap-northeast-1

## Deploy EKS resources
cd terraform/eks

(Optional) Logout of helm registry to perform an unauthenticated pull against the public ECR

helm registry logout public.ecr.aws

terraform init

terraform plan --var-file=terraform.tfvars

terraform apply --var-file=terraform.tfvars

## Generate test data
cd utils

pip3 install -r requirements.txt

mkdir -p input

fake -n 20000 -f parquet -c "order_id,customer_id,order_date,item_id,quantity,price" -o input/order.parquet "pyint,pyint,date_this_year,pyint,pyint,pyint"

## Push script and sample data to S3 Express Directory Bucket
[Run below commands from the repository root directory]

### replace ${s3_express_bucket_name} and ${region} in the below commands with information from Terraform output
aws s3api put-object --bucket ${s3_express_bucket_name} --key order/input/order.parquet --body utils/input/order.parquet --region ${region}

aws s3api put-object --bucket ${s3_express_bucket_name} --key scripts/pyspark-order.py --body terraform/eks/resources/scripts/pyspark-order.py --region ${region}

## Trigger job run
### Configure kubectl
aws eks --region ${region} update-kubeconfig --name eks-spark-s3-bench

cd terraform/eks

kubectl apply -f resources/spark_prometheus_monitor.yaml

kubectl apply -f resources/s3_express_pv.yaml

kubectl apply -f resources/s3_express_spark_app.yaml

kubectl describe sparkapplication order -n spark-s3-express

kubectl describe pod order -n spark-s3-express

## Monitor job run
### Grafana port-forward 

kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack

http://localhost:8080

### Grafana Admin user: admin

### Get admin user password (secret name is returned as part of terraform output)

aws secretsmanager get-secret-value --secret-id <output.grafana_secret_name> --region $AWS_REGION --query "SecretString" --output text

### Import Grafana Dashboard

Save the file to local disk: https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/emr-eks-karpenter/emr-grafana-dashboard/emr-eks-grafana-dashboard.json
On the Grafana console, upload this JSON and select "Prometheus" as data source. It takes a minute or two for the metrics to show up.

Note: adjust relative time to view the results

![image](/uploads/a9e78b8cba5dc75618dfb6b6485ffc70/image.png)

![image](/uploads/89a7a172b55b319762c41bf6cce6d79f/image.png)

