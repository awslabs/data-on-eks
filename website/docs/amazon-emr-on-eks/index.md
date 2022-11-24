---
sidebar_position: 1
sidebar_label: Introduction
---

# Amazon EMR on Amazon EKS
Amazon EMR on Amazon EKS enables you to submit Apache Spark jobs on demand on Amazon Elastic Kubernetes Service (EKS) without provisioning clusters. With EMR on EKS, you can consolidate analytical workloads with your other Kubernetes-based applications on the same Amazon EKS cluster to improve resource utilization and simplify infrastructure management.

## Benefits of EMR on EKS

### Simplify management
You get the same EMR benefits for Apache Spark on EKS that you get on EC2 today. This includes fully managed versions of Apache Spark 2.4 and 3.0, automatic provisioning, scaling, performance optimized runtime, and tools like EMR Studiofor authoring jobs and an Apache Spark UI for debugging.

### Reduce Costs
With EMR on EKS, your compute resources can be shared between your Apache Spark applications and your other Kubernetes applications. Resources are allocated and removed on demand to eliminate over-provisioning or under-utilization of these resources, enabling you to lower costs as you only pay for the resources you use.

### Optimize Performance
By running analytics applications on EKS, you can reuse existing EC2 instances in your shared Kubernetes cluster and avoid the startup time of creating a new cluster of EC2 instances dedicated for analytics. You can also get 3x faster performance running performance optimized Spark with EMR on EKS compared to standard Apache Spark on EKS.

## EMR on EKS Deployment patterns with Terraform

The following Terraform templates are available to deploy.
- [Scaling EMR on EKS Spark Jobs with Karpenter](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-karpenter).
- [Running EMR on EKS Spark Jobs with Apache Yunikorn](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-yunikorn)
- [Running EMR on EKS Spark Jobs with FSx for Lustre as Shuffle Storage](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-fsx-lustre)
- [Running ACK controller for EMR on EKS to run Spark Jobs](https://github.com/awslabs/data-on-eks/tree/main/analytics/terraform/emr-eks-ack)
