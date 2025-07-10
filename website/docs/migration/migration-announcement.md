---
id: migration-announcement
title: "🚨 Repository Split: Data on EKS and AI on EKS"
sidebar_position: 0
---

# 🔥 Data on EKS Is Evolving: Introducing AI on EKS

:::note

This is a major announcement about the future of this repository and upcoming changes to the structure of our blueprints.
:::


## 📣 Why the Change?

The **Data on EKS** project has grown significantly over time, supporting both **Data Analytics** and **AI/ML** communities with production-ready blueprints, patterns, and best practices on Amazon EKS.

As the community has grown and the need for more focused content has become clear, we are **splitting this repository into two distinct and specialized projects**:

- 📊 **`data-on-eks`** – This repo (you are here!) will continue to provide **Data Analytics blueprints and patterns**, including Amazon EMR on EKS, Apache Spark, Flink, Kafka, Trino, and other related frameworks.
- 🤖 **`ai-on-eks`** – A new, dedicated repository that will serve **AI/ML workloads**, including Terraform modules, training pipelines, inference serving, LLM deployment patterns, and performance benchmarks for GPUs.


## 🗓️ Timeline

- **Soft Launch of `ai-on-eks`**: _KubeCon EU (London), First Week of April 2025_
- **Full Migration & Public Launch**: _By the end of April 2025_

We will provide a detailed announcement and URLs during and after the soft launch to help contributors and users easily transition.


## 🔎 What You Need to Know

Here’s what this change means for contributors and users:

1. **🚫 AI/ML Pull Requests (PRs) are currently paused** in this repository. Please hold off on submitting new AI-related blueprints or modules until the `ai-on-eks` repo is publicly available.
2. **✅ Existing AI blueprints will remain temporarily available**  in this `data-on-eks` repository. Once the new `ai-on-eks` repo is fully launched, all new content and updates will be made there instead.
3. **📦 Once the migration is complete**, updates to existing AI/ML blueprints will no longer be made in the `data-on-eks` repo. However, we will retain these blueprints here temporarily until all related blogs and documentation have been updated to reference the new `ai-on-eks` repository.
4. **🔗 Existing AWS blogs, workshops, and documentation** that currently point to the `data-on-eks` repository will remain unchanged to avoid breaking links. We will raise separate issues to update these references to the new `ai-on-eks` repository over time, depending on resource availability.
5. **💬 Going forward, all new issues related to AI on EKS**, whether for new content or updates to existing blueprints should be opened in the `ai-on-eks` repository. We will not address AI on EKS related issues in `data-on-eks` unless the specific blueprint or content exists only in this repo and hasn’t yet been migrated.


## ✅ What Stays in This Repo?

This repository (`data-on-eks`) will continue to focus on:

- 📊 Data Analytics Patterns: Spark, Trino, Flink, and other analytics frameworks on EKS

- 🔁 Streaming Platforms: Kafka, Apache Pulsar, and other event-driven systems

- 🧩 Job Schedulers: Kubernetes-native job orchestration using tools like Apache Airflow and YuniKorn

- 🗃️ Distributed Databases: Scalable data stores such as Apache Pinot, ClickHouse, and PostgreSQL on EKS

- 📦 Terraform Modules: Infrastructure as code templates related to data workloads

- 🌐 Website & Documentation Content: Including this Docusaurus site

- 🛠️ Best Practices, Benchmarks & Resources: All content specific to data infrastructure and operations

## 🚀 What’s Moving to the New ai-on-eks Repository?

The following components are being migrated to the new ai-on-eks repository (coming soon):

- 🤖 [AI on EKS](https://awslabs.github.io/data-on-eks/docs/gen-ai) Section: Including model training, inference, and serving patterns currently hosted under
/docs/gen-ai

- 🛠️ [AI Terraform Modules](https://github.com/awslabs/data-on-eks/tree/main/ai-ml): IaC templates used to deploy end-to-end AI workloads

- 🧠 [Gen AI Patterns](https://github.com/awslabs/data-on-eks/tree/main/gen-ai): Code for Training and Inference patterns

- 🛠️ AI-Specific Best Practices: Guidance, architecture recommendations, and scaling patterns tailored to AI/ML use cases on EKS

## ❤️ Thank You

We deeply appreciate your feedback, support, and contributions to the **Data on EKS** project. This change helps us build more focused, scalable, and production-grade solutions for both Data and AI/ML workloads.

Stay tuned for more details as we approach KubeCon EU in April. We can’t wait to share what’s next with you!

— *The Data & AI on EKS Maintainers*
