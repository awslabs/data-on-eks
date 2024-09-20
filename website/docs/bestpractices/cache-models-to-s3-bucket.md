---
title: Store ML models in S3 bucket and use Amazon S3 CSI Driver
sidebar_position: 3
---

Storing a machine learning model in Amazon S3, instead of downloading it from Huggingface, offers several advantages:

1. Reduced Download Latency: Storing the model in S3 can reduce the network latency that may occur when downloading the model from Huggingface, especially when you need to quickly deploy the model or use it across multiple instances simultaneously.

2. Improved Access Speed and Reliability: S3's high availability and global reach mean that the model can be accessed faster and more reliably.
3. Reduced Data Transfer Costs with VPC Endpoints: In many cases, using VPC endpoints can help reduce data transfer costs. For data transfer between your VPC and S3 through 5h3 gateway endpoints is free.

Refer to the page [Mounpoint S3: Enhancing Amazon S3 File Access for Data & AI Workloads on Amazon EKS](../resources/mountpoint-s3) to learn more about Amazon S3 Mountpoint CSI Driver.

## End-to-end Example

An end-to-end deployment example can be found in [Stable Diffusion on GPU](../gen-ai/inference/GPUs/stablediffusion-gpus).
