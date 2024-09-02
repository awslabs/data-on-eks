![Data on EKS](website/static/img/doeks-logo-green.png)
# [Data on Amazon EKS (DoEKS)](https://awslabs.github.io/data-on-eks/)
*(Pronounced: "Do.eks")*
> 💡 **Optimized Solutions for Data and AI on EKS**



### Build, Scale, and Optimize Data & AI/ML Platforms on [Amazon EKS](https://aws.amazon.com/eks/) 🚀

Welcome to **Data on EKS**, your gateway to scaling **Data and AI** workloads on Amazon EKS. Unlock the potential of [Gen AI](https://aws.amazon.com/generative-ai/) with a rich collection of Terraform Blueprints featuring best practices for deploying robust solutions with advanced logging and observability.

Explore practical examples and patterns for running Data workloads on EKS using advanced frameworks such as [Apache Spark](https://spark.apache.org/) for distributed data processing, [Apache Flink](https://flink.apache.org/) for real-time stream processing, and [Apache Kafka](https://kafka.apache.org/) for high-throughput distributed messaging. Automate and orchestrate complex workflows with [Apache Airflow](https://airflow.apache.org/) and leverage the robust capabilities of [Amazon EMR on EKS](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/emr-eks.html) to build resilient clusters, seamlessly integrating Kubernetes with big data solutions for enhanced scalability and performance.

On the AI/ML front, Explore practical patterns for running AI/ML workloads on EKS, leveraging the power of the [Ray](https://www.ray.io/) ecosystem for distributed computing. Utilize advanced serving solutions like [NVIDIA Triton Server](https://developer.nvidia.com/nvidia-triton-inference-server), [vLLM](https://github.com/vllm-project/vllm) for efficient and scalable model inference, and [TensorRT-LLM](https://developer.nvidia.com/tensorrt) for optimizing deep learning models.

Take advantage of high-performance [NVIDIA GPUs](https://aws.amazon.com/nvidia/) for intensive computational tasks and leverage AWS’s specialized hardware, including [AWS Trainium](https://aws.amazon.com/machine-learning/trainium/) for efficient model training and [AWS Inferentia](https://aws.amazon.com/machine-learning/inferentia/) for cost-effective model inference at scale.


> **Note:** DoEKS is in active development. For upcoming features and enhancements, check out the [issues](https://github.com/awslabs/data-on-eks/issues) section.


## 🏗️ Architecture
The diagram below showcases the wide array of open-source data tools, Kubernetes operators, and frameworks used by DoEKS. It also highlights the seamless integration of AWS Data Analytics managed services with the powerful capabilities of DoEKS open-source tools.

<img width="779" alt="image" src="https://user-images.githubusercontent.com/19464259/208900860-a7ccdaeb-158d-4767-baad-fbc76388bc09.png">


## 🌟 Features
Data on EKS(DoEKS) solution is categorized into the following focus areas.

🎯  [Data Analytics](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics) on EKS

🎯  [AI/ML](https://awslabs.github.io/data-on-eks/docs/gen-ai) on EKS

🎯  [Streaming Platforms](https://awslabs.github.io/data-on-eks/docs/blueprints/streaming-platforms) on EKS

🎯  [Scheduler Workflow Platforms](https://awslabs.github.io/data-on-eks/docs/blueprints/job-schedulers) on EKS

🎯  [Distributed Databases & Query Engine](https://awslabs.github.io/data-on-eks/docs/blueprints/distributed-databases) on EKS

## 🏃‍♀️Getting Started
In this repository, you'll find a variety of deployment blueprints for creating Data/ML platforms with Amazon EKS clusters. These examples are just a small selection of the available blueprints - visit the [DoEKS website](https://awslabs.github.io/data-on-eks/) for the complete list of options.

### 🧠 AI

🚀 [Trainium-Inferentia on EKS](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/trainium) 👈 This blueprint used for running Gen AI models on [AWS Neuron](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/) accelerators.

🚀 [JARK-Stack on EKS](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/jark) 👈 This blueprint deploys JARK stack for AI workloads with NVIDIA GPUs.

🚀 [JupyterHub on EKS](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/jupyterhub) 👈 This blueprint deploys a self-managed JupyterHub on EKS with Amazon Cognito authentication.

🚀 [Generative AI on EKS](https://awslabs.github.io/data-on-eks/docs/gen-ai) 👈 Collection of Generative AI Training and Inference LLM deployment patterns

### 📊 Data

🚀 [EMR-on-EKS with Karpenter](https://awslabs.github.io/data-on-eks/docs/blueprints/amazon-emr-on-eks/emr-eks-karpenter)  👈 Start here if you are new to EMR on EKS. This blueprint deploys EMR on EKS cluster and uses [Karpenter](https://karpenter.sh/) to scale Spark jobs.

🚀 [Spark Operator with Apache YuniKorn on EKS](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn) 👈 This blueprint deploys EKS cluster and uses Spark Operator and Apache YuniKorn for running self-managed Spark jobs

🚀 [Self-managed Airflow on EKS](https://awslabs.github.io/data-on-eks/docs/blueprints/job-schedulers/self-managed-airflow) 👈 This blueprint sets up a self-managed Apache Airflow on an Amazon EKS cluster, following best practices.

🚀 [Argo Workflows on EKS](https://awslabs.github.io/data-on-eks/docs/blueprints/job-schedulers/argo-workflows-eks) 👈 This blueprint sets up a self-managed Argo Workflow on an Amazon EKS cluster, following best practices.

🚀 [Kafka on EKS](https://awslabs.github.io/data-on-eks/docs/blueprints/streaming-platforms/kafka) 👈 This blueprint deploys a self-managed Kafka on EKS using the popular Strimzi Kafka operator.


## 📚 Documentation
For instructions on how to deploy Data on EKS patterns and run sample tests, visit the [DoEKS website](https://awslabs.github.io/data-on-eks/).

## 🏆 Motivation
[Kubernetes](https://kubernetes.io/) is a widely adopted system for orchestrating containerized software at scale. As more users migrate their data and machine learning workloads to Kubernetes, they often face the complexity of managing the Kubernetes ecosystem and selecting the right tools and configurations for their specific needs.

At [AWS](https://aws.amazon.com/), we understand the challenges users encounter when deploying and scaling data workloads on Kubernetes. To simplify the process and enable users to quickly conduct proof-of-concepts and build production-ready clusters, we have developed Data on EKS (DoEKS). DoEKS offers opinionated open-source blueprints that provide end-to-end logging and observability, making it easier for users to deploy and manage Spark on EKS, Kubeflow, MLFlow, Airflow, Presto, Kafka, Cassandra, and other data workloads. With DoEKS, users can confidently leverage the power of Kubernetes for their data and machine learning needs without getting overwhelmed by its complexity.

## 🤝 Support & Feedback
DoEKS is maintained by AWS Solution Architects and is not an AWS service. Support is provided on a best effort basis by the Data on EKS Blueprints community. If you have feedback, feature ideas, or wish to report bugs, please use the [Issues](https://github.com/awslabs/data-on-eks/issues) section of this GitHub.

## 🔐 Security
See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## 💼 License
This library is licensed under the Apache 2.0 License.

## 🙌 Community
We welcome all individuals who are enthusiastic about data on Kubernetes to become a part of this open source community. Your contributions and participation are invaluable to the success of this project.

Built with ❤️ at AWS.
