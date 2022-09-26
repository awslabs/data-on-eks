# Data on Amazon EKS (DoEKS)

💥Welcome to **Data on Amazon EKS (DoEKS)** 💥

Data on Amazon EKS(DoEKS) is a tool for users to build [aws](https://aws.amazon.com/) managed and self-managed scalable data platforms on [Amazon EKS](https://aws.amazon.com/eks/).
This repo provides Infrastructure as Code(IaC) templates(e.g., [Terraform](https://www.terraform.io/), [AWS CDK](https://aws.amazon.com/cdk/) etc.),
sample [Apache Spark](https://spark.apache.org/)/[ML](https://aws.amazon.com/machine-learning/) jobs, references to AWS Data blogs, Performance Benchmark reports and Best Practices for deploying Data Solutions on Amazon EKS.

## Features
Data on EKS(DoEKS) solution is categorized into the following areas.

✅  [Data Analytics](analytics) on EKS

✅  [AI/ML](ai-ml) on EKS

✅  [Distributed Databases](distributed-databases) on EKS

✅  [Streaming Platforms](streaming) on EKS

✅  [Scheduler Workflow Platforms](schedulers) on EKS

## Getting Started
In this repository you will find multiple deployment examples for bootstrapping Amazon EKS clusters with Data related Kubernetes add-ons/operators.

Check the README under each folder for more instructions to deploy the infrastrcuture on EKS and run sample tests.

Example.,

🚀 [EMR on EKS](analytics/emr-eks-amp-amg/README.md) - Deploy EKS Cluster, EMR on EKS Cluster with teams and sample Spark scripts.

🚀 [Spark Operator on EKS](analytics/spark-k8s-operator/README.md) - Deploy EKS Cluster, Spark Operator and Apache YuniKorn with sample Spark scripts.

🚀 [Self-managed Airflow on EKS](schedulers/self-managed-airflow/README.md) - Deploy self-managed Apache Airflow with best practices on Amazon EKS.

🚀 [Ray on EKS](ai-ml/ray/README.md) - Deploy Ray Operator on EKS with sample scripts.

*NOTE: Please refer to the [issues](https://github.com/awslabs/data-on-eks/issues) section to see the work in progress features.*

## Documentation
Documentation is available under each folder of the deployment pattern with README files.


## Motivation
[Kubernetes](https://kubernetes.io/) is the most widely known system for large-scale orchestration of containerized software.
It became more mature for running stateful workloads with the introduction of several storage options in version 1.19.
In addition, with an introduction of [Spark on Kubernetes](https://spark.apache.org/docs/2.3.0/running-on-kubernetes.html) and the flexibility that Kubernetes offers have motivated many users to migrate their existing Hadoop based clusters to Kubernetes.

Deploying and managing Kubernetes clusters and scaling data workloads is still challenging for many users because they are expected to be familiar with Kubernetes and data workloads.
To address this, we chose to launch this new Data on EKS (DoEKS) tool to help simplify the journey for the users who want to run Spark on EKS, Kubeflow, MLFlow, Airflow, Presto, Kafka, Cassandra etc. or any other data workloads.

## Support & Feedback
Data on EKS(DoEKS) is maintained by AWS Solution Architects.
It is not part of an AWS service, and support is provided best effort by the Data on EKS Blueprints community.

Please use the Issues section of this GitHub to post feedback, submit feature ideas, or report bugs.

## Security
See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License
This library is licensed under the Apache 2.0 License.

## Community
We invite everyone who is passionate about data on Kubernetes to join this initiative.

Built with ❤️ at AWS.
