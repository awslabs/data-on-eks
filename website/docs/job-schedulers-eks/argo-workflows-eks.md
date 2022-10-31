---
title: Argo Workflows on EKS
sidebar_position: 4
---
# Argo Workflows on EKS
Argo Workflows is an open source container-native workflow engine for orchestrating parallel jobs on Kubernetes. It is implemented as a Kubernetes CRD (Custom Resource Definition). As a result, Argo workflows can be managed using kubectl and natively integrates with other Kubernetes services such as volumes, secrets, and RBAC.

The example demonstrates how to use Argo Workflows to assign jobs to Amazon EKS in two ways.
1. Use Argo Workflows to create a spark job. 
2. Use Argo Workflows to create a spark job through spark operator.

[Code repo](https://github.com/awslabs/data-on-eks/tree/main/schedulers/argo-workflow) for this example.

## Prerequisites:

Ensure that you have the following tools installed locally:

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## Deploy

To provision this example:

```bash
cd data-on-eks/schedulers/argo-workflow
terraform init
terraform apply -var region=<aws_region> #defaults to us-west-2
```

Enter `yes` at command prompt to apply

The following components are provisioned in your environment:
- A sample VPC, 3 Private Subnets and 3 Public Subnets
- Internet gateway for Public Subnets and NAT Gateway for Private Subnets
- EKS Cluster Control plane with one managed node group
- EKS Managed Add-ons: VPC_CNI, CoreDNS, Kube_Proxy, EBS_CSI_Driver
- K8S metrics server, cluster autoscaler, Spark Operator and yunikorn scheduler
- K8s roles and rolebindings for argo workflows

## Install the Argo Workflows CLI 
Please follow this link: https://github.com/argoproj/argo-workflows/releases/latest

## Validate

The following command will update the `kubeconfig` on your local machine and allow you to interact with your EKS Cluster using `kubectl` to validate the deployment.

1. Run `update-kubeconfig` command:

```bash
aws eks --region <REGION> update-kubeconfig --name <CLUSTER_NAME>
```

2. List the nodes running currently

```bash
kubectl get nodes

# Output should look like below
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-1-131-99.us-west-2.compute.internal   Ready    <none>   26h   v1.23.9-eks-ba74326
ip-10-1-16-117.us-west-2.compute.internal   Ready    <none>   26h   v1.23.9-eks-ba74326
ip-10-1-80-41.us-west-2.compute.internal    Ready    <none>   26h   v1.23.9-eks-ba74326
```

3. List the namespaces in your EKS cluster
```bash
kubectl get ns

# Output should look like below
NAME              STATUS   AGE
argo-workflows    Active   28h
default           Active   30h
kube-node-lease   Active   30h
kube-public       Active   30h
kube-system       Active   30h
spark-operator    Active   30h
yunikorn          Active   30h
```

4. Argo workflows provide a web UI. You can access by following steps:  
```bash
kubectl -n argo-workflows port-forward deployment.apps/argo-workflows-server 2746:2746
argo auth token # get login token
# result:
Bearer k8s-aws-v1.aHR0cHM6Ly9zdHMudXMtd2VzdC0yLmFtYXpvbmF3cy5jb20vP0FjdGlvbj1HZXRDYWxsZXJJZGVudGl0eSZWZXJzaW9uPTIwMTEtMDYtMTUmWC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNWNFhDV1dLUjZGVTRGMiUyRjIwMjIxMDEzJTJGdXMtd2VzdC0yJTJGc3RzJTJGYXdzNF9yZXF1ZXN0JlgtQW16LURhdGU9MjAyMjEwMTNUMDIyODAyWiZYLUFtei1FeHBpcmVzPTYwJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCUzQngtazhzLWF3cy1pZCZYLUFtei1TaWduYXR1cmU9NmZiNmMxYmQ0MDQyMWIwNTI3NjY4MzZhMGJiNmUzNjg1MTk1YmM0NDQzMjIyMTg5ZDNmZmE1YzJjZmRiMjc4OA
```

Open browser and enter http://localhost:2746/ and paste the token
![argo-workflow-login](argo-workflow-login.PNG)

5. Use Argo workflows to create a spark job workflow <br/>
Modify workflow-example/argo-spark.yaml with your eks api server url


```bash
kubectl apply -f workflow-example/argo-spark.yaml

kubectl get wf -n argo-workflows
NAME    STATUS    AGE   MESSAGE
spark   Running   8s  
```
You can also check the workflow status from web UI
![argo-wf-spark](argo-wf-spark.png)

6. Create a spark job workflow through spark operator
```bash
kubectl apply -f workflow-example/argo-spark-operator.yaml

kubectl get wf -n argo-workflows 
NAME             STATUS      AGE     MESSAGE
spark            Succeeded   3m58s  
spark-operator   Running     5s  
```
The workflow status from web UI
![argo-wf-spark-operator](argo-wf-spark-operator.png)
