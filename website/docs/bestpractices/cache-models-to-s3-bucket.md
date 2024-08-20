---
title: Store ML models in S3 bucket and use Amazon S3 CSI Driver
sidebar_position: 3
---

Storing a machine learning model in Amazon S3, instead of downloading it from Huggingface, offers several advantages:

1. Reduced Download Latency: Storing the model in S3 can reduce the network latency that may occur when downloading the model from Huggingface, especially when you need to quickly deploy the model or use it across multiple instances simultaneously.

2. Improved Access Speed and Reliability: S3's high availability and global reach mean that the model can be accessed faster and more reliably, particularly when used in conjunction with AWS infrastructure (such as EC2 or Lambda) within the same region.

Refer to the page [Mounpoint S3: Enhancing Amazon S3 File Access for Data & AI Workloads on Amazon EKS](../resources/mountpoint-s3) for learn more about Amazon S3 Mountpoint CSI Driver.

End-to-end Example

TODO: 
- Create a S3 bucket
- Download ML models to the local computer
- Upload the ML models to S3 
- Specify the Kubernetes PV and PVC
- Mount the volume in the Ray Pods
 