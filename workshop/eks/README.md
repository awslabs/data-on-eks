# Install steps

## Step1: Deploy EKS Cluster
- Deploys VPC, EKS CLuster, Node groups and necessary add-ons

```shell
cd workshop/eks
terraform init
terraform plan
terraform apply -auto-approve
```

## Step2: Deploy Karpenter provisioners
- Deploy Karpenter provisioner for running spark workloads

```shell
terraform plan
terraform apply -auto-approve
```

## Step3: Execute Sample Spark job

- Verify the CW Logs and S3 logs
- Check the Spark History server

## Step4: Deploy Open source grafana module
- Deploy Grafana module

```shell
terraform plan
terraform apply -auto-approve
```

## Step5: Setup Grafana dashboard and monitor the logs
- Steps to setup Grafana EMR Jobs dashboard
