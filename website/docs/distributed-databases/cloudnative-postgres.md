---
sidebar_position: 2
sidebar_label: Cloud Native PostGres Operator
---

# Run CloudNativePG operator to manage your Postgres DataBase on EKS

## Introduction

**CloudNativePG** is an open source
[operator](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
designed to manage [PostgreSQL](https://www.postgresql.org/) workloads [Kubernetes](https://kubernetes.io).

It defines a new Kubernetes resource called `Cluster` representing a PostgreSQL
cluster made up of a single primary and an optional number of replicas that co-exist
in a chosen Kubernetes namespace for High Availability and offloading of
read-only queries.

Applications that reside in the same Kubernetes cluster can access the
PostgreSQL database using a service which is solely managed by the operator,
without having to worry about changes of the primary role following a failover
or a switchover. Applications that reside outside the Kubernetes cluster, need
to configure a Service or Ingress object to expose the Postgres via TCP.
Web applications can take advantage of the native connection pooler based on PgBouncer.

CloudNativePG was originally built by [EDB](https://www.enterprisedb.com), then
released open source under Apache License 2.0 and submitted for CNCF Sandbox in April 2022.
The [source code repository is in Github](https://github.com/cloudnative-pg/cloudnative-pg).

More details about the project will be found on this [link](https://cloudnative-pg.io)

## Deploying the Solution

Let's go through the deployment steps

### Prerequisites

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### Deploy the EKS Cluster with CloudNativePG Operator

First, clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into cloudnative-postgres folder and run `install.sh` script. By default the script deploys EKS cluster to `us-west-2` region. Update `variables.tf` to change the region. This is also the time to update any other input variables or make any other changes to the terraform template.

```bash
cd data-on-eks/distributed-databases/cloudnative-postgres

./install .sh
```

### Verify Deployment

Verify the Amazon EKS Cluster

```bash
aws eks describe-cluster --name cnpg-on-eks
```

Update local kubeconfig so we can access kubernetes cluster

```bash
aws eks update-kubeconfig --name cnpg-on-eks --region us-west-2 
```

First, lets verify that we have worker nodes running in the cluster.

```bash
kubectl get nodes 
```

Next, lets verify all the pods are running.

```bash
kubectl get pods --namespace=monitoring

kubectl get pods --namespace=cnpg-system

```
