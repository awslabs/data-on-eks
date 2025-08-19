---
sidebar_position: 1
sidebar_label: Introduction
---

# Amazon EMR on EKS
Amazon EMR on EKS enables you to submit Apache Spark jobs on-demand on Amazon Elastic Kubernetes Service (EKS) clusters. With EMR on EKS, you can consolidate analytical workloads with your other Kubernetes-based applications on the same Amazon EKS cluster to improve resource utilization and simplify infrastructure management.

## Benefits of EMR on EKS

### Simplify management
You get the same EMR benefits for Apache Spark on EKS that you get on EC2 today. This includes fully managed versions of Apache Spark 2.4 and 3.0, automatic provisioning, scaling, performance optimized runtime, and tools like EMR Studio for authoring jobs and an Apache Spark UI for debugging.

### Reduce Costs
With EMR on EKS, your compute resources can be shared between your Apache Spark applications and your other Kubernetes applications. Resources are allocated and removed on-demand to eliminate over-provisioning or under-utilization of these resources, enabling you to lower costs as you only pay for the resources you use.

### Optimize Performance
By running analytics applications on EKS, you can reuse existing EC2 instances in your shared Kubernetes cluster and avoid the startup time of creating a new cluster of EC2 instances dedicated for analytics. You can also get [3x faster performance](https://aws.amazon.com/blogs/big-data/amazon-emr-on-amazon-eks-provides-up-to-61-lower-costs-and-up-to-68-performance-improvement-for-spark-workloads/) running performance optimized Spark with EMR on EKS compared to standard Apache Spark on EKS.

## EMR on EKS Deployment patterns with Terraform

The following Terraform templates are available to deploy.

- [EMR on EKS with Karpenter](./emr-eks-karpenter.md): **:point_left::skin-tone-3: Start Here** if you are new to EMR on EKS. This template deploys EMR on EKS cluster and uses [Karpenter](https://karpenter.sh/) to scale Spark jobs.
- [EMR on EKS with Spark Operator](./emr-eks-spark-operator.md): This template deploys EMR on EKS cluster with Spark Operator for managing Spark jobs
