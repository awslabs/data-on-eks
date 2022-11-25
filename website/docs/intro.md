---
sidebar_position: 1
sidebar_label: Introduction
---

# Introduction
Data on Amazon EKS(DoEKS) is a tool for users to build [aws](https://aws.amazon.com/) managed and self-managed scalable data platforms on [Amazon EKS](https://aws.amazon.com/eks/). This repo provides the following tools.

1. Scalable deployment Infrastructure as Code(IaC) templates(e.g., [Terraform](https://www.terraform.io/) and [AWS CDK](https://aws.amazon.com/cdk/) etc.)
2. Best Practices for deploying Data Solutions on Amazon EKS
3. Performance Benchmark reports
4. Sample [Apache Spark](https://spark.apache.org/)/[ML](https://aws.amazon.com/machine-learning/) jobs and various other frameworks
5. Reference Architectures and Data blogs

# Architecture
The diagram displays the open source data tools, k8s operators and frameworks that runs on Kubernetes covered in DoEKS. AWS Data Analytics managed services integration with Data on EKS OSS tools.  

![Data on EKS.png](doeks.png)

# Main Features

🚀 [EMR on EKS](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/emr-eks.html)

🚀 [Open Source Spark on EKS](https://spark.apache.org/docs/latest/running-on-kubernetes.html)

🚀 Custom Kubernetes Schedulers (e.g., [Apache YuniKorn](https://yunikorn.apache.org/), [Volcano](https://volcano.sh/en/))

🚀 Job Schedulers (e.g., [Apache Airflow](https://airflow.apache.org/), [Argo Workflows](https://argoproj.github.io/argo-workflows/))

🚀 AI/ML on Kubernetes (e.g., KubeFlow, MLFlow, Tensorflow, PyTorch etc.)

🚀 Distributed Databases (e.g., [Cassandra](https://cassandra.apache.org/_/blog/Cassandra-on-Kubernetes-A-Beginners-Guide.html), [CockroachDB](https://github.com/cockroachdb/cockroach-operator), [MongoDB](https://github.com/mongodb/mongodb-kubernetes-operator) etc.)

🚀 Streaming Platforms (e.g., [Apache Kafka](https://github.com/apache/kafka), [Apache Flink](https://github.com/apache/flink), Apache Beam etc.)

# Getting Started

Checkout the documentation for each section to deploy infrastructure and run sample Spark/ML jobs.
