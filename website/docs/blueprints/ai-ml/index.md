---
sidebar_position: 1
sidebar_label: Introduction
---

:::caution

The **AI on EKS** content **is being migrated** to a new repository.
🔗 👉 [Read the full migration announcement »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

# AI/ML Platforms on Amazon EKS

Amazon Elastic Kubernetes Service (EKS) is a powerful, managed Kubernetes platform that has become a cornerstone for deploying and managing AI/ML workloads in the cloud. With its ability to handle complex, resource-intensive tasks, Amazon EKS provides a scalable and flexible foundation for running AI/ML models, making it an ideal choice for organizations aiming to harness the full potential of machine learning.

## Key Advantages of AI/ML Platforms on Amazon EKS

### 1. Scalability and Flexibility
Amazon EKS enables organizations to scale AI/ML workloads seamlessly. Whether you're training large language models that require vast amounts of compute power or deploying inference pipelines that need to handle unpredictable traffic patterns, EKS scales up and down efficiently, optimizing resource use and cost.

### 2. High Performance with GPUs and Neuron Instances
Amazon EKS supports a wide range of compute options, including GPUs and AWS Neuron instances, which are essential for accelerating AI/ML workloads. This support allows for high-performance training and low-latency inference, ensuring that models run efficiently in production environments.

### 3. Integration with AI/ML Tools
Amazon EKS integrates seamlessly with popular AI/ML tools and frameworks like TensorFlow, PyTorch, and Ray, providing a familiar and robust ecosystem for data scientists and engineers. These integrations enable users to leverage existing tools while benefiting from the scalability and management capabilities of Kubernetes.

### 4. Automation and Management
Kubernetes on Amazon EKS automates many of the operational tasks associated with managing AI/ML workloads. Features like automatic scaling, rolling updates, and self-healing ensure that your applications remain highly available and resilient, reducing the overhead of manual intervention.

### 5. Security and Compliance
Running AI/ML workloads on Amazon EKS provides robust security features, including fine-grained IAM roles, encryption, and network policies, ensuring that sensitive data and models are protected. EKS also adheres to various compliance standards, making it suitable for enterprises with strict regulatory requirements.

## Why Choose Amazon EKS for AI/ML?

Amazon EKS offers a comprehensive, managed environment that simplifies the deployment of AI/ML models while providing the performance, scalability, and security needed for production workloads. With its ability to integrate with a variety of AI/ML tools and its support for advanced compute resources, EKS empowers organizations to accelerate their AI/ML initiatives and deliver innovative solutions at scale.

By choosing Amazon EKS, you gain access to a robust infrastructure that can handle the complexities of modern AI/ML workloads, allowing you to focus on innovation and value creation rather than managing underlying systems. Whether you are deploying simple models or complex AI systems, Amazon EKS provides the tools and capabilities needed to succeed in a competitive and rapidly evolving field.

## Deploying Generative AI Models on Amazon EKS

Deploying Generative AI models on Amazon EKS is supported through two major blueprints:

- **For GPUs**: Use the [JARK stack blueprint](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/jark).
- **For Neuron**: Start with the [Trainium on EKS blueprint](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/trainium).

In addition to these, this section provides other valuable ML blueprints:

- **NVIDIA Spark RAPIDS**: For Spark on GPU workloads, refer to the [NVIDIA Spark RAPIDS blueprint](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/emr-spark-rapids).

- **JupyterHub on EKS**: Explore the [JupyterHub blueprint](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/jupyterhub), which showcases Time Slicing and MIG features, as well as multi-tenant configurations with profiles. This is ideal for deploying large-scale JupyterHub platforms on EKS.

- **Additional Patterns**: For other patterns using NVIDIA Triton server, NVIDIA NGC, and more, refer to the [Gen AI page](https://awslabs.github.io/data-on-eks/docs/gen-ai).
