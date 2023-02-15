---
sidebar_position: 2
sidebar_label: Ray on EKS
---

# Ray on EKS

:::caution
This blueprint should be considered as experimental and should only be used for proof of concept.
:::

## Introduction

[Ray](https://www.ray.io/) is an open-source framework for building scalable and distributed applications. It is designed to make it easy to write parallel and distributed Python applications by providing a simple and intuitive API for distributed computing. It has a growing community of users and contributors, and is actively maintained and developed by the Ray team at Anyscale, Inc.

To deploy Ray in production across multiple machines users must first deploy [**Ray Cluster**](https://docs.ray.io/en/latest/cluster/getting-started.html). A Ray Cluster consists of head nodes and worker nodes which can be autoscaled using the built-in **Ray Autoscaler**.

![RayCluster](img/ray-cluster.svg)

*Source: https://docs.ray.io/en/latest/cluster/key-concepts.html*

## Ray on Kubernetes

Deploying Ray Cluster on Kubernetes including on Amazon EKS is supported via the [**KubeRay Operator**](https://ray-project.github.io/kuberay/). The operator provides a Kubernetes-native way to manage Ray clusters. The installation of KubeRay Operator involves deploying the operator and the CRDs for `RayCluster`, `RayJob` and `RayService` as documented [here](https://ray-project.github.io/kuberay/deploy/helm/).

Deploying Ray on Kubernetes can provide several benefits:

1. Scalability: Kubernetes allows you to scale your Ray cluster up or down based on your workload requirements, making it easy to manage large-scale distributed applications.

1. Fault tolerance: Kubernetes provides built-in mechanisms for handling node failures and ensuring high availability of your Ray cluster.

1. Resource allocation: With Kubernetes, you can easily allocate and manage resources for your Ray workloads, ensuring that they have access to the necessary resources for optimal performance.

1. Portability: By deploying Ray on Kubernetes, you can run your workloads across multiple clouds and on-premises data centers, making it easy to move your applications as needed.

1. Monitoring: Kubernetes provides rich monitoring capabilities, including metrics and logging, making it easy to troubleshoot issues and optimize performance.

Overall, deploying Ray on Kubernetes can simplify the deployment and management of distributed applications, making it a popular choice for many organizations that need to run large-scale machine learning workloads.

Before moving forward with the deployment please make sure you have read the pertinent sections of the official [documentation](https://docs.ray.io/en/latest/cluster/kubernetes/index.html).

![RayonK8s](img/ray_on_kubernetes.webp)

*Source: https://docs.ray.io/en/latest/cluster/kubernetes/index.html*
## Deploying the Example

In this [example](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/terraform/terraform/ray), you will provision Ray Cluster on Amazon EKS using the KubeRay Operator. The example also demonstrates the use of Karpenter of autoscaling of worker nodes for job specific Ray Clusters.


![RayOnEKS](img/ray-on-eks.png)

### Prerequisites

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [python3](https://www.python.org/)
6. [ray](https://docs.ray.io/en/master/ray-overview/installation.html#from-wheels)


### Deploy the EKS Cluster with KubeRay Operator

#### Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

#### Initialize Terraform

Navigate into the example directory and run `terraform init`

```bash
cd data-on-eks/ai-ml/ray/terraform
terraform init
```

#### Terraform Plan

Run Terraform plan to verify the resources created by this execution.

```bash
terraform plan
```

#### Terraform Apply

```bash
terraform apply -auto-approve
```

#### Verify Deployment

Update local kubeconfig so we can access kubernetes cluster

```bash
aws eks update-kubeconfig --name ray-cluster
```

First, lets verify that we have worker nodes running in the cluster.

```bash
kuebctl get nodes
```
:::info
```bash
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-1-26-241.ec2.internal   Ready    <none>   10h   v1.24.9-eks-49d8fe8
ip-10-1-4-21.ec2.internal     Ready    <none>   10h   v1.24.9-eks-49d8fe8
ip-10-1-40-196.ec2.internal   Ready    <none>   10h   v1.24.9-eks-49d8fe8
```
:::

Next, lets verify all the pods are running.

```bash
kubectl get pods -n kuberay-operator
```
:::info
```bash
NAMESPACE            NAME                               READY   STATUS    RESTARTS        AGE
amazon-cloudwatch    aws-cloudwatch-metrics-d4xrr       1/1     Running   1 (1h37m ago)   1h
amazon-cloudwatch    aws-cloudwatch-metrics-tpqsz       1/1     Running   1 (1h37m ago)   1h
amazon-cloudwatch    aws-cloudwatch-metrics-z7wbn       1/1     Running   1 (1h37m ago)   1h
aws-for-fluent-bit   aws-for-fluent-bit-h82w4           1/1     Running   1 (1h37m ago)   1h
aws-for-fluent-bit   aws-for-fluent-bit-r5kxt           1/1     Running   1 (1h37m ago)   1h
aws-for-fluent-bit   aws-for-fluent-bit-wgxxl           1/1     Running   1 (1h37m ago)   1h
karpenter            karpenter-668c669897-fmxdr         1/1     Running   1 (1h37m ago)   1h
karpenter            karpenter-668c669897-prbr6         1/1     Running   1 (1h37m ago)   1h
kube-system          aws-node-fnwp5                     1/1     Running   1 (1h37m ago)   1h
kube-system          aws-node-r45xd                     1/1     Running   1 (1h37m ago)   1h
kube-system          aws-node-vfq66                     1/1     Running   1 (1h37m ago)   1h
kube-system          coredns-79989457d9-2jldd           1/1     Running   1 (1h37m ago)   1h
kube-system          coredns-79989457d9-cgtkf           1/1     Running   1 (1h37m ago)   1h
kube-system          kube-proxy-5jrtf                   1/1     Running   1 (1h37m ago)   1h
kube-system          kube-proxy-fjxsk                   1/1     Running   1 (1h37m ago)   1h
kube-system          kube-proxy-tzr79                   1/1     Running   1 (1h37m ago)   1h
kuberay-operator     kuberay-operator-7b5c85998-vfsjr   1/1     Running   1 (1h37m ago)   1h
```
:::


At this point we are ready to deploy Ray Clusters.

#### Deploy Ray Clusters and Workloads

For convenience, we have packaged the helm chart deployent of Ray Cluster as a repeatable terraform [module](../../..//ai-ml/ray/terraform/modules/ray-cluster/). This allows us to codify organizational best practices and requirements for deploying Ray Clusters for multiple Data Science teams. The module also creates configuration needed for karpenter to be able to provision EC2 instances for Ray applications as and when they are needed for the duration of the job. This model can be replicated via GitOps tooling such as ArgoCD or Flux but is done here via terraform for demonstration purpose.

##### XGBoost

First, we will deploy a Ray Cluster for our [XGBoost benchmark](https://docs.ray.io/en/latest/cluster/kubernetes/examples/ml-example.html#kuberay-ml-example) sample job.

Go to the xgboost directory followed by terraform init, and plan.

```bash
cd examples/xgboost
terraform init
terraform plan
```

If the changes look good, lets apply them.

```bash
terraform apply -auto-approve
```

As the RayCluster pod goes into the pending state, Karpenter will provision an EC2 instance based on the `Provisioner` and `AWSNodeTemplate` configuration we have provided. We can check that a new node has been created.

```bash
kubectl get nodes
```

:::info
```bash
NAME                          STATUS   ROLES    AGE     VERSION
# New node appears
ip-10-1-13-204.ec2.internal   Ready    <none>   2m22s   v1.24.9-eks-49d8fe8
ip-10-1-26-241.ec2.internal   Ready    <none>   12h     v1.24.9-eks-49d8fe8
ip-10-1-4-21.ec2.internal     Ready    <none>   12h     v1.24.9-eks-49d8fe8
ip-10-1-40-196.ec2.internal   Ready    <none>   12h     v1.24.9-eks-49d8fe8
```
:::

Wait until the RayCluster head node pods are provisioned.

```bash
kubectl get pods -n xgboost
```
:::info
```
NAME                         READY   STATUS    RESTARTS   AGE
xgboost-kuberay-head-585d6   2/2     Running   0          5m42s
```
:::

Now we are ready to run our sample training benchmark using for XGBoost. First, open another terminal and forward the Ray server to our localhost.

```sh
kubectl port-forward service/xgboost-kuberay-head-svc -n xgboost 8265:8265
```
:::info
```bash
Forwarding from 127.0.0.1:8265 -> 8265
Forwarding from [::1]:8265 -> 8265
```
:::

Submit the ray job for XGBoost benchmark.

```bash
python job/xgboost_submit.py
```

You can open http://localhost:8265 in your browser to monitor job progress. If there are any failures during execution those can be viewed in the logs under the Jobs section.

![RayDashboard](img/ray-dashboard.png)

As the job progresses, you will notice new Ray autoscaler will provision additional ray worker pods based on the autoscaling configuration defined in the RayCluster configuration. Those worker pods will initially remain in pending state. That will trigger karpenter to spin up new EC2 instances so the pending pods can be scheduled. After worker pods go to running state, the job will progress to completion.

```bash
kubectl get nodes
```
:::info
```bash
NAME                          STATUS    ROLES    AGE   VERSION
ip-10-1-1-241.ec2.internal    Unknown   <none>   1s  
ip-10-1-10-211.ec2.internal   Unknown   <none>   1s  
ip-10-1-13-204.ec2.internal   Ready     <none>   24m   v1.24.9-eks-49d8fe8
ip-10-1-26-241.ec2.internal   Ready     <none>   12h   v1.24.9-eks-49d8fe8
ip-10-1-3-64.ec2.internal     Unknown   <none>   7s  
ip-10-1-4-21.ec2.internal     Ready     <none>   12h   v1.24.9-eks-49d8fe8
ip-10-1-40-196.ec2.internal   Ready     <none>   12h   v1.24.9-eks-49d8fe8
ip-10-1-7-167.ec2.internal    Unknown   <none>   1s  
ip-10-1-9-112.ec2.internal    Unknown   <none>   1s  
ip-10-1-9-172.ec2.internal    Unknown   <none>   1s  
```
:::

Once the benchmark is complete, the job log will display the results. You might see different results based on your configurations.

:::info
```bash
Results: {'training_time': 1338.488839321999, 'prediction_time': 403.36653568099973}
```
:::
##### PyTorch

We can simultaneously deploy the PyTorch benchmark as well. We deploy a separate Ray Cluster with its own configuration for Karpenter workers. Different jobs can have different requirements for Ray Cluster such as a different version of Ray libraries or EC2 instance configuration such as making use of Spot market or GPU instances. We take advantage of node taints and tolerations in Ray Cluster pod specs to match the Ray Cluster configuration to Karpenter configuration thus taking advantage of the flexibility that Karpenter provides.

Go to the PyTorch directory and run the terraform init and plan as before.

```bash
cd ../pytorch
terraform init
terraform plan
```

Apply the changes.


```bash
terraform apply -auto-approve
```

Wait for the pytorch Ray Cluster head node pods to be ready.

```bash
kubectl get pods -n pytorch -w
```

:::info
```bash
NAME                         READY   STATUS    RESTARTS   AGE
pytorch-kuberay-head-9tx56   0/2     Pending   0          43s
```
:::

Once running, we can forward the port for server, taking care that we foward it to another local port as 8265 may be occupied by the xgboost connection.

```bash
kubectl port-forward service/xgboost-kuberay-head-svc -n pytorch 8265:8266
```

We can then submit the job for PyTorch benchmark workload.

```bash
python job/pytorch_submit.py
```

You can open http://localhost:8266 to monitor the progress of the pytorch benchmark.

#### Teardown

:::caution
To avoid unwanted charges to your AWS account, delete all the AWS resources created during this deployment.
:::

Destroy the Ray Clusters for pytorch followed by xgboost.

From the pytorch directory.

```bash
terraform destroy -auto-approve
```

From the xgboost directory.

```bash
cd ../xgboost
terraform destroy -auto-approve
```

Delete the add-ons.

```bash
cd ../../
tf destroy -auto-approve -target=module.eks_blueprints_kubernetes_addons
```

Delete worker nodes, EKS cluster.

```bash
tf destroy -auto-approve -target=module.eks
```

Delete the VPC.

```bash
tf destroy -auto-approve -target=module.vpc
```

Delete everything else.

```bash
terraform destroy -auto-approve
```
