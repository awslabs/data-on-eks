# Apache Superset on EKS
This repository contains Terraform configuration to deploy Apache Superset on AWS infrastructure.

## Architecture
Terraform will create following AWS infrastructure for Superset:
- VPC
- Subnets (Public/Private)
- EC2 Instance for Superset 
- Security Groups
- IAM Roles and Policies

## Pre-requisites
- AWS account
- AWS CLI installed and configured
- Terraform v0.12+ installed
- Helm

## Usage
- Clone this repository
- Update variables.tf with your AWS details
- Initialize Terraform
    ```
    terraform init
    ```
- Review execution plan
    ```
    terraform plan
    ```

- Provision infrastructure
    ```
    terraform apply
    ```
 
- Access the Superset web UI at http://PUBLIC_IP

- Default credentials are admin/admin

- Destroy infrastructure when done
    ```
    terraform destroy
    ```

## Resources
Following resources will be created by Terraform:

- VPC with public and private subnets
- Postgres database (superset-db)
- EC2 instance (Apache Superset)
- Security Groups for DB & EC2 instances
- IAM Roles & Policies


Review the resources section in main.tf file
