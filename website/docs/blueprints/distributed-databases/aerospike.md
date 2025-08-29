---
sidebar_position: 5
sidebar_label: Aerospike
---

# Aerospike Database Enterprise on EKS
[Aerospike Database Enterprise Edition](https://aerospike.com) is a high-performance, distributed NoSQL database designed for real-time, mission-critical applications. Integrating Aerospike with Amazon Elastic Kubernetes Service (EKS) combines Aerospike’s robust data management capabilities with Kubernetes orchestration prowess. This integration empowers organizations to harness Aerospike’s predictable sub-millisecond performance and seamless scalability within EKS’s flexible and resilient environment. By leveraging the [Aerospike Kubernetes Operator (AKO)](https://aerospike.com/docs/cloud/kubernetes/operator), deployment and management of Aerospike clusters on EKS are automated, ensuring efficient operations and reduced complexity.

## Key Benefits of Aerospike on EKS
* **Predictable Low Latency**: Aerospike ensures sub-millisecond response times, which is critical for applications requiring immediate data access, such as fraud detection, recommendation engines, and real-time bidding systems.

* **Seamless Scalability**: Aerospike’s Hybrid-Memory Architecture allows for efficient horizontal and vertical scaling, accommodating data growth from terabytes to petabytes without compromising performance. Deploying on EKS enables dynamic resource allocation to meet varying workload demands effectively.

* **High Availability and Resilience**: With features like Cross-Datacenter Replication (XDR), Aerospike provides fine-grained control for asynchronous data replication across geographically dispersed clusters. This ensures data availability and compliance with data locality regulations. EKS enhances this resilience by distributing workloads across multiple availability zones.

* **Operational Efficiency**: The Aerospike Kubernetes Operator automates routine tasks such as configuration, scaling, and upgrading Aerospike clusters. This reduces operational complexity and overhead, allowing teams to focus on delivering value rather than managing infrastructure.

* **Cost Optimization**: Leveraging Aerospike’s efficient use of resources and EKS’s flexible infrastructure, organizations can achieve significant cost savings compared to traditional deployments. Aerospike’s ability to deliver high performance with a reduced hardware footprint translates to lower total cost of ownership.

## Community and Support
For assistance and to engage with the community:
* **Aerospike Documentation**: Comprehensive guides and references are available in the [Aerospike Documentation](https://aerospike.com/docs).

* **GitHub Repository**: Access the AKO source code, report issues, and contribute at the aerospike-kubernetes-operator [GitHub repository](https://github.com/aerospike/aerospike-kubernetes-operator).

* **Community Forum**: Join discussions and seek advice on the [Aerospike Community Forum](https://discuss.aerospike.com).

By deploying Aerospike Database Enterprise Edition on Amazon EKS, organizations can harness the combined strengths of Aerospike’s high-performance data management and Kubernetes orchestration capabilities, resulting in a scalable, resilient, and cost-effective solution for real-time data applications.

## Deploying Aerospike on EKS
To deploy the Aerospike Database Enterprise Edition on an EKS cluster, we recommend using the [Aerospike on EKS blueprint](https://github.com/aerospike/aerospike-terraform-aws-eks) maintained by Aerospike, an AWS Partner and the maintainer of the [Aerospike Kubernetes Operator](https://github.com/aerospike/aerospike-kubernetes-operator).

If you encounter any issues with the blueprint or the operator, please report them on the relevant Aerospike GitHub repository.
