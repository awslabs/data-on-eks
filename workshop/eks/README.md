# Install steps


## Step1: Deploy Pre-requisites
if you are using Cloud9 IDE to deploy the EKS Cluster then execute the following command

```shell
cd workshop/setup
./pre-requisites-setup.sh
```

Deploy the following pre-requisites tool only when you want to deploy in Mac or Windows without Cloud9 IDE

1. Terraform v1.2.8
2. kubectl
3. aws cli

## Step2: Deploy EKS Cluster and network resources
- Deploys VPC, EKS CLuster, Node groups and necessary add-ons

```shell
git clone https://github.com/awslabs/data-on-eks.git
cd workshop/eks
terraform init
terraform plan
terraform apply -auto-approve
```
