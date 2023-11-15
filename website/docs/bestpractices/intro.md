---
sidebar_position: 1
sidebar_label: Introduction
---

# Introduction

:::info

COMING SOON

Please note that this section is currently a work in progress and will provide a collection of best practices for running Data and ML workloads on EKS.
These best practices will cover various aspects, including cluster configuration, resource management, data storage, security, monitoring, and more.
By following these recommended practices, you can optimize the performance, reliability, and security of your data and ML workloads on EKS.

Stay tuned for valuable insights and guidance on how to achieve the best outcomes in your EKS environment.

:::

Through working with AWS customers, we’ve identified a number of Best Practices that we have recommended for Spark or other large data workloads. We continue to collect and post those recommendations here. Because this is an ongoing effort, please open an Issue or Pull Request if you find something outdated so we can update it.

These Data on EKS Best Practices are meant to expand upon the [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/) for data-centric use cases (e.g., batch processing, stream processing, and machine learning) and we recommend reviewing the EKS Best Practices as a primer before diving into these. The Data on EKS Best Practices are not comprehensive and we recommend you read through the guidance and determine what’s best for your environment.

The recommendations here were built from working with customers one of two designs (listed below). Each data use case (e.g., batch processing, stream processing) aligns more closely to one of the two cluster designs, which we will call out in our recommendations.

* The first design is **dynamic clusters** that scale, or “churn”, a lot. These clusters run batch processing with Spark, or other workloads that create pods for a relatively short time but can vary greatly on the scale at any given time. These clusters create and delete resources like pods and nodes, or churn, at a high rate which adds unique pressures to Kubernetes and critical components.
* The other design is **“static” clusters**. These clusters are often large but have less volatile scaling behavior and are generally running longer-lived jobs, like streaming or training. Avoid interruptions for these workloads is a key concern and care must be taken when making changes.

When we talk about large clusters or high rates of churn, it’s difficult to put a specific number to those phrases because of the [complexity of kubernetes scalability](https://github.com/kubernetes/community/blob/master/sig-scalability/configs-and-limits/thresholds.md). In general, these clusters have >500 nodes and >5000 pods, or are creating/destroying hundreds of resources a minute; however, the scalability constraints are different for every workload (even between two different Spark jobs).
