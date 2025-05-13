---
sidebar_position: 2
sidebar_label: Trino on EKS Best Practices
---
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import CollapsibleContent from '../../../src/components/CollapsibleContent';

# Trino on EKS Best Practices
[Trino](https://trino.io/) deployment on [Amazon Elastic Kubernetes Service](https://aws.amazon.com/eks/) (EKS) delivers distributed query processing with cloud-native scalability. Organizations can optimize costs by selecting specific compute instances and storage solutions that match their workload requirements while they  combine the power of Trino with the scalability and flexibility of EKS using [Karpenter](https://karpenter.sh/).

This guide provides prescriptive guidance for deploying Trino on EKS. It focuses on achieving high scalability and low cost through optimal configurations, effective resource management, and cost-saving strategies. We cover detailed configurations for popular file formats such as Hive and Iceberg. These configurations ensure seamless data access and optimize performance. Our goal is to help you set up a Trino deployment that is both efficient and cost-effective.

We have a [deployment-ready blueprint](https://awslabs.github.io/data-on-eks/docs/blueprints/distributed-databases/trino) for deploying Trino on EKS, which incorporates the best practices discussed here.

Refer to these best practices for the rational and further optimization/fine-tuning.

<CollapsibleContent header={<h2><span>Trino Fundamentals</span></h2>}>
This section covers Trino's core architecture, capabilities, use cases, and ecosystem with references.

### Core Architecture

Trino is a powerful distributed SQL query engine designed for high-performance analytics and big data processing. Some of the key components are 

- Distributed coordinator-worker model
- In-memory processing architecture
- MPP (Massively Parallel Processing) execution
- Dynamic query optimization engine
- More details can be found [here](https://trino.io/docs/current/overview/concepts.html#architecture)

### Key Capabilities

Trino offers several features that enhance data processing capabilities.

- Query Federation
- Simultaneous queries across multiple data sources
- Support for heterogeneous data environments
- Real-time data processing capabilities
- Unified SQL interface for diverse data sources

### Connectors Ecosystem

Trino enables SQL querying of diverse data sources by configuring a catalog with the appropriate connector and connecting through standard SQL clients.

- 50+ [production-ready connectors](https://trino.io/ecosystem/data-source) including:
  - Cloud storage (AWS S3)
  - Relational databases (PostgreSQL, MySQL, SQL Server)
  - NoSQL stores (MongoDB, Cassandra)
  - Data lakes (Apache Hive, Apache Iceberg, Delta Lake)
  - Streaming platforms (Apache Kafka)

### Query Optimizations

- Advanced cost-based optimizer
- Dynamic filtering
- Adaptive query execution
- Sophisticated memory management
- Columnar processing support
- Read more [here](https://trino.io/docs/current/optimizer.html)

### Use Cases

Trino addresses these key use cases:

- Interactive analytics
- Data lake queries
- ETL processing
- Ad-hoc analysis
- Real-time dashboards
- Cross-platform data federation

</CollapsibleContent>

<CollapsibleContent header={<h2><span>EKS Cluster Configuration</span></h2>}>

## Creating the EKS Cluster

- Cluster Scope: Deploy the EKS cluster across multiple AZs for redundancy.
- Control Plane Logging: Enable control plane logging for audit and diagnostic purposes.
- Kubernetes Version: Use latest EKS version

### EKS Add-ons

Use [Amazon EKS-managed add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html) through the EKS API instead of open-source Helm charts. The EKS team maintains these add-ons and automatically updates them to align with your EKS cluster versions.
- VPC CNI: Install and configure the [Amazon VPC CNI](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) plugin with custom settings to optimize IP address usage.
- CoreDNS: Ensure CoreDNS is deployed for internal DNS resolution.
- KubeProxy: Deploy KubeProxy for Kubernetes network proxy functionality.

:::tip
When you are planning to launch a EKS cluster and deploy Trino follow these configuration details
:::

### Provisioning
You can provision and scale underlying compute resources by using Karpenter or [Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html) (MNG)

#### Managed Node Groups for essential components
MNG uses Launch Templates, leverages Auto Scaling Groups, and integrates with Kubernetes Cluster Autoscaler.

#### On-Demand Node Group
- Set up a managed node group for On-demand instances to run critical components like the Trino coordinator and at least one worker. This setup ensures stability and reliability for core operations.
  - **Use Case**: Ideal for running the Trino coordinator and an essential worker node.

#### Spot Instance Node Group
- Configure a managed node group for Spot instances to add additional worker nodes cost-effectively. Spot instances are suitable for handling variable workloads while reducing expenses.
  - **Use Case**: Best for scaling worker nodes for non SLA bound, cost-sensitive tasks.

#### Additional Configurations
- **Single AZ Deployment**: Deploy node groups within a single Availability Zone to minimize data transfer costs and reduce latency.
- **Instance Types**: Select instance types that match your workload's needs, such as r6g.4xlarge for memory-intensive workloads.

### Karpenter for Node Scaling
Karpenter provisions nodes in under 60 seconds, supports mixed instance/architecture, leverages native EC2 APIs, and offers dynamic resource allocation.

#### Node Pool Setup
Use Karpenter to create a dynamic node pool that includes both spot and on-demand instances. Apply labels to ensure Trino workers and the coordinator are spun up on the appropriate instance types (on-demand or spot) as needed.
<details>
  <summary> Example Karpenter Node Pool with EC2 Graviton Instances</summary>
  ```
  apiVersion: karpenter.sh/v1
  kind: NodePool
  metadata:
  name: trino-sql-karpenter
  spec:
  template:
  metadata:
  labels:
  NodePool: trino-sql-karpenter
  spec:
  nodeClassRef:
  group: karpenter.k8s.aws
  kind: EC2NodeClass
  name: trino-karpenter
  requirements:
  - key: "karpenter.sh/capacity-type"
  operator: In
  values: ["on-demand"]
  - key: "kubernetes.io/arch“
  operator: In
  values: ["arm64"]
  - key: "karpenter.k8s.aws/instance-category"
  operator: In
  values: ["r"]
  - key: "karpenter.k8s.aws/instance-family"
  operator: In
  values: ["r6g", "r7g", "r8g"]
  - key: "karpenter.k8s.aws/instance-size"
  operator: In
  values: ["2xlarge", "4xlarge"]
  disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 60s
  limits:
  cpu: "1000"
  memory: 1000Gi
  weight: 100
  ```
</details>

Example of a Karpenter Node Pool setup can be also viewed in the [DoEKS repository](https://github.com/awslabs/data-on-eks/blob/f8dda1ae530902b77ee123661265caa09d97969b/distributed-databases/trino/karpenter.tf#L100) and the [EC2 Node Class configuration](https://github.com/awslabs/data-on-eks/blob/f8dda1ae530902b77ee123661265caa09d97969b/distributed-databases/trino/karpenter.tf#L65).

### Mixed Instances
Configure mixed instance types within the same instance pool to enhance flexibility and ensure access to a range of instance sizes, from small to large, based on workload demands.


:::tip[Key Recommendations]
:::
- Use Karpenter: For better scaling and simplified management of Trino clusters, prefer using Karpenter. It provides faster node provisioning, enhanced flexibility with mixed instance types, and better resource efficiency. Karpenter delivers superior scaling capabilities compared to MNG, making it the preferred choice for scaling secondary(worker) nodes in analytics applications.
- Dedicated Nodes: Deploy one Trino pod per node to fully utilize available resources.
- DaemonSet Resource Allocation: Reserve enough CPU and memory for essential system DaemonSets to maintain node stability.
- Coordinator Placement: Always run the Trino coordinator on an on-demand node to guarantee reliability.
- Worker Distribution: Use a mix of On-Demand and Spot instances for worker nodes to balance cost-effectiveness with availability.
- Managed Node Groups Usage : MNG should be used for components of the workloads resiliency purposes and other components of the cluster like observability tools.
</CollapsibleContent>

<CollapsibleContent header={<span><h2>Trino on EKS Setup</h2></span>}>
Helm streamlines your Trino deployment on EKS. We recommend installing through Helm using either the [official Helm chart](https://github.com/trinodb/charts) or community charts for configuration management.

## Setup

* Install Trino using the official Helm chart or community charts
* Create distinct Helm releases for each cluster (ETL, Interactive, BI)

### Configuration Steps

* Define unique `values.yaml` files per cluster
* Configure pod resources:
  * Set CPU/memory requests
  * Set CPU/memory limits
  * Specify coordinator resources
  * Specify worker resources
* Set pod scheduling:
  * Configure nodeSelector
  * Configure affinity rules

### Deployment

Use separate Helm configurations for each workload type, with their respective values files. For example
```
# ETL Cluster
helm install etl-trino trino-chart -f etl-values.yaml

# Interactive Cluster
helm install interactive-trino trino-chart -f interactive-values.yaml

# BI Cluster
helm install analytics-trino trino-chart -f analytics-values.yaml
```

Trino operates as a distributed query engine with a massively parallel processing (MPP) architecture. The system consists of two primary components: a coordinator and multiple workers.

#### The coordinator serves as the central management node that:

- Handles incoming queries
- Parses and plans query execution
- Schedules and monitors workloads
- Manages worker nodes
- Consolidates results for end-users

#### Workers are execution nodes that:

- Execute assigned tasks
- Process data from various sources
- Share intermediate results
- Communicate with data source connectors
- Register with the coordinator through a discovery service

When deployed on EKS, both coordinator and worker components run as pods within an EKS cluster. The system stores schemas and references in a catalog, which enables access to various data sources through specialized connectors. This architecture enables Trino to distribute query processing across multiple nodes, resulting in improved performance and scalability for large-scale data operations.


### Trino Coordinator Configuration

Coordinators handle query planning and orchestration, requiring fewer resources than worker nodes. Coordinator pods need fewer resources than workers as they focus on query planning rather than data processing. Below are the key configuration settings for high availability and efficient resource usage.

#### Resource Configuration sufficient for query planning and coordination tasks

* Memory: 40Gi
* CPU: 4-6 cores

#### High Availability Settings

* Replicas: 2 coordinator instances
* Pod Disruption Budget: Ensures coordinator availability during maintenance
* Pod Anti-Affinity: Schedules coordinators on separate nodes
* Always configure Pod Anti-Affinity to prevent multiple coordinators from running on the same node, improving fault tolerance.

### Exchange Manager Configuration

- Handles intermediate data during query execution.
- Offloads data to external storage to improve fault tolerance and scalability.

#### Configuring Exchange Manager with S3

#### S3 Settings
- Set to `s3://your-exchange-bucket`
- `exchange.s3.region`: Set to your AWS region
- `exchange.s3.iam-role`: Use IAM roles for S3 access
- `exchange.s3.max-error-retries`: Increase for resilience
- `exchange.s3.upload.part-size`: Adjust to optimize performance (e.g., 64MB)
#### Recommendations
- Security - Ensure IAM roles have least privilege necessary
- Performance - Tune `upload.part-size` and concurrent connections
- Cost Management - Monitor S3 costs and implement lifecycle policies

## Trino Pod Resource Requests vs Limits

Kubernetes uses resource requests and limits to manage container resources effectively. Here's how to optimize them for different Trino pod types:

### Worker Pods

- Set resources.requests slightly lower than resources.limits (e.g., 10-20% difference).
- This approach ensures efficient resource allocation while preventing resource exhaustion.

### Coordinator Pods

- Configure resource limits 20-30% higher than requests.
- This strategy accommodates occasional usage spikes, providing burst capacity while maintaining predictable scheduling.

### Benefits of This Strategy

- Improves scheduling: Kubernetes makes informed decisions based on accurate resource requests, optimizing pod placement.
- Protects resources: Well-defined limits prevent resource exhaustion, safeguarding other cluster workloads.
- Handles bursts: Higher limits allow smooth management of transient resource spikes.
- Enhances stability: Appropriate resource allocation reduces the risk of pod evictions and improves overall cluster stability.


### AutoScaling Configuration

We recommend implementing [KEDA](https://keda.sh/) for event-driven scaling in Trino clusters to enable dynamic workload management. The combination of KEDA and Karpenter on Amazon EKS creates a powerful autoscaling solution that eliminates scaling challenges. While KEDA manages fine-grained pod scaling based on real-time metrics, Karpenter handles efficient node provisioning. Together, they replace manual scaling processes, delivering both improved performance and cost optimization.

#### Configuring Keda
- Add Keda helm release to the cluster
- Add JVM / JMX Exporter configuration to Trino Helm value, enable serviceMonitor
```
configProperties: |-
      hostPort: localhost:{{- .Values.jmx.registryPort }}
      startDelaySeconds: 0
      ssl: false
      lowercaseOutputName: false
      lowercaseOutputLabelNames: false
      whitelistObjectNames: ["trino.execution:name=QueryManager","trino.execution:name=SqlTaskManager","trino.execution.executor:name=TaskExecutor","trino.memory:name=ClusterMemoryManager","java.lang:type=Runtime","trino.memory:type=ClusterMemoryPool,name=general","java.lang:type=Memory","trino.memory:type=MemoryPool,name=general"]
      autoExcludeObjectNameAttributes: true
      excludeObjectNameAttributes:
        "java.lang:type=OperatingSystem":
          - "ObjectName"
        "java.lang:type=Runtime":
          - "ClassPath"
          - "SystemProperties"
      rules:
      - pattern: ".*"
```
- Deploy KEDA scaledObject for trino, tracking CPU and QueuedQueries. The 'target' CPU percentage here is set at 85%, to leverage the physical cores of Graviton instances.
```
triggers:
  - type: cpu
    metricType: Utilization
    metadata:
      value: '85'  # Target CPU utilization percentage
  - type: prometheus
    metricType: Value
    metadata:
      serverAddress: http://kube-prometheus-stack-prometheus.kube-prometheus-stack.svc.cluster.local:9090
      threshold: '1'
      metricName: queued_queries
      query: sum by (job) (avg_over_time(trino_execution_QueryManager_QueuedQueries{job="trino"}[1m]))
```

## File Caching

File caching provides three major benefits to storage systems and query operations. First, it reduces the storage load by preventing repetitive retrievals of the same files, as cached files can be reused across multiple queries on the same worker. Second, it can significantly improve query performance by eliminating repeated network transfers and allowing access to local file copies, particularly beneficial when the original storage is in a different network or region. Finally, it leads to reduced query costs by minimizing network traffic and storage access.

This is a basic configuration for implementing File Caching.

```
fs.cache.enabled=true
fs.cache.directories=/tmp/cache/
fs.cache.preferred-hosts-count=10 # The cluster size determines the host count. We recommend keeping host count small to maintain optimal performance.
```

:::note
Configure instances with Local SSD storage for cache directories to significantly improve I/O speed and overall query performance.
:::

</CollapsibleContent>

<CollapsibleContent header={<h2><span>Compute, Storage, and Networking Best Practices</span></h2>}>

<CollapsibleContent header={<span><h2>Compute Best Practices</h2></span>}>

## Compute Choices

Amazon Elastic Compute Cloud (EC2) offers diverse computing options through its instance families and processors, including standard, compute-optimized, memory-optimized, and I/O-optimized configurations. You can purchase these instances through [flexible pricing models](https://aws.amazon.com/ec2/pricing/): On-Demand, Compute Savings Plan, Reserved, or Spot instances. Choosing the appropriate instance type optimizes your costs, maximizes performance, and supports sustainability goals. EKS enables you to match these compute resources precisely to your workload requirements. For Trino distributed clusters specifically, your compute selection directly impacts cluster performance.

:::tip[Key Recommendations]
:::
- Use [AWS Graviton-based Instances](https://aws.amazon.com/ec2/graviton/): Graviton instances lowers cost of instances while improving performance, it also helps to meet with sustainability goals
- Use Karpenter: For better scaling and simplified management of Trino clusters, prefer using Karpenter.
- Diversify the Spot Instances to maximize your savings. [More details can be found in EC2 Spot Best Practices](https://aws.amazon.com/blogs/compute/best-practices-to-optimize-your-amazon-ec2-spot-instances-usage/). Use [Fault-Tolerant execution](http://localhost:3000/data-on-eks/docs/blueprints/distributed-databases/trino#example-3-optional-fault-tolerant-execution-in-trino) with EC2 Spot Instances

</CollapsibleContent>

<CollapsibleContent header={<span><h2>Networking  Best Practices</h2></span>}>

## Plan for networking

Trino's distributed nature across pods requires implementation of networking best practices to ensure optimal performance. Proper implementation improves resiliency, prevents IP exhaustion, reduces pod initialization errors, and minimizes latency. Pod networking forms the core of Kubernetes operations. Amazon EKS uses the VPC CNI plugin, operating in underlay mode where pods and hosts share the network layer. This ensures consistent IP addressing across both cluster and VPC environments.

### VPC CNI Addon
The Amazon VPC CNI plugin can be customized to manage IP address allocation efficiently. By default, the Amazon VPC CNI assigns two Elastic Network Interfaces (ENIs) per node. These ENIs reserve numerous IP addresses, particularly on larger instance types. Since Trino typically needs only one pod per node plus a few IP addresses for DaemonSet pods (for logging and networking), you can configure the CNI to limit IP address allocation and reduce overhead.

The following settings to the VPC CNI Addon can be applied using the EKS API, Terraform, or any other Infrastructure-as-Code (IaC) tool. For more in-depth details, refer to the official documentation:VPC CNI Prefix and IP Target.

### Configuring the VPC CNI Addon

Limit IP Addresses per Node by adjusting the configuration to allocate only the required number of IPs:
- MINIMUM_IP_TARGET: Set this to the expected number of pods per node (e.g., 30).
- WARM_IP_TARGET: Set to 1 to keep the warm IP pool minimal.
- ENABLE_PREFIX_DELEGATION: Improve IP address efficiency by assigning IP prefixes to worker nodes rather than individual secondary IP addresses. This approach reduces Network Address Usage (NAU) within your VPC by utilizing a smaller, more concentrated pool of IP addresses.

#### Sample VPC CNI Configuration

```
vpc-cni = {
  preserve = true
  configuration_values = jsonencode({
    env = {
      MINIMUM_IP_TARGET           = "30"
      WARM_IP_TARGET              = "1"
      ENABLE_PREFIX_DELEGATION    = "true"
    }
  })
}
```

:::tip[Key Recommendations]
:::
<b>Enable prefix delegation:</b> VPC CNI plugin supports prefix delegation, which assigns blocks of 16 IPv4 addresses (/28 prefix) to each node. This feature reduces the number of ENIs required per node. By using prefix delegation, you can lower your EC2 Network Address Usage (NAU), reduce network management complexity, and decrease operational costs.

#### For more best practices related to Networking, [refer to our Networking guide](../networking/networking.md)

</CollapsibleContent>

<CollapsibleContent header={<span><h2>Storage Best Practices</h2></span>}>

This sections focuses on AWS services for optimal storage management with Trino on EKS.

## Amazon S3 as Primary Storage

- Use S3 Standard for frequently accessed data in Trino queries
- Implement S3 Intelligent-Tiering for data with varying access patterns
- Enable S3 server-side encryption (SSE-S3 or SSE-KMS) for data at rest
- Configure appropriate bucket policies and access through IAM roles
- Use S3 bucket prefixes strategically for better query performance
- Use Trino with S3 Select to improve query performance
- 

### EBS Storage for Coordinator and Workers

- Use gp3 EBS volumes for better performance/cost ratio
- Enable EBS encryption using KMS
- Size EBS volumes based on spill directory requirements
- Consider using EBS snapshots for backup strategy

### Performance Optimization

- Implement S3 Select for improved query performance on specific workloads
- Use AWS Partition Indexes for large datasets
- Enable S3 request metrics in CloudWatch for monitoring
- Configure appropriate read/write IOPS for gp3 volumes
- Use S3 prefixes to partition data effectively

### Data Lifecycle Management

- Implement S3 Lifecycle policies for automated data management
- Use S3 Storage classes appropriately:
    - Standard for hot data
    - Intelligent-Tiering for variable access patterns
    - Standard-IA for less frequently accessed data
- Configure versioning for critical datasets

### Cost Optimization

- Use S3 storage class analysis to optimize storage costs
- Monitor and optimize S3 request patterns
- Implement S3 lifecycle policies to move older data to cheaper storage tiers
- Use Cost Explorer to track storage spending

### Security and Compliance

- Implement VPC Endpoints for S3 access
- Use AWS KMS for encryption key management
- Enable S3 access logging for audit purposes
- Configure appropriate IAM roles and policies
- Enable AWS CloudTrail for API activity monitoring

:::note
Remember to adjust these practices based on your specific workload characteristics and requirements.
:::

#### For detailed understanding of best practices related to S3, [refer to the Best Practices for Trino with Amazon S3](https://trino.io/assets/blog/trino-fest-2024/aws-s3.pdf)

</CollapsibleContent>

</CollapsibleContent>

<CollapsibleContent header={<span><h2>Configuring Trino Connectors</h2></span>}>
Trino connects to data sources through specialized adapters called connectors. The Hive and Iceberg connectors enable Trino to read columnar file formats like Parquet and ORC (Optimized Row Columnar). Proper connector configuration ensures optimal query performance and system compatibility.

:::tip[Key Recommendations]
:::
- **Isolation**: Use separate catalogs for different data sources or environments
- **Security**: Implement appropriate authentication and authorization mechanisms
- **Performance**: Optimize connector settings based on data formats and query patterns
- **Resource Management**: Adjust memory and CPU settings to match the workload requirements of each connector

Integrating Trino with file formats like Hive and Iceberg on Amazon EKS requires careful configuration and adherence to best practices. Set up connectors correctly and optimize resource allocation to ensure data access efficiency. Fine-tune query performance settings to achieve high scalability while keeping costs low. These steps are crucial for maximizing Trino's capabilities on EKS. Tailor configurations to your specific workloads, focusing on factors such as data volume and query complexity. Continuously monitor system performance and adjust settings as needed to maintain optimal results.

<CollapsibleContent header={<span><h2>Hive</h2></span>}>

## Hive Connector Configuration

The Hive connector allows Trino to query data stored in a Hive data warehouse, typically using file formats like Parquet, ORC, or Avro stored on HDFS or Amazon S3.

### Hive Configuration Parameters

- **Connector Name**: `hive`
- **Metastore**: Use AWS Glue Data Catalog as the metastore.
- **File Formats**: Support for Parquet, ORC, Avro, and others.
- **S3 Integration**: Configure S3 permissions for data access.

### Sample Hive Catalog Configuration

```
connector.name=hive
hive.metastore=glue
hive.metastore.glue.region=us-west-2
hive.s3.aws-access-key=YOUR_ACCESS_KEY
hive.s3.aws-secret-key=YOUR_SECRET_KEY
hive.s3.iam-role=arn:aws:iam::123456789012:role/YourIAMRole
hive.s3.endpoint=s3.us-west-2.amazonaws.com
hive.s3.path-style-access=true
hive.s3.ssl.enabled=true
hive.security=legacy
```

:::tip[Key Recommendations]
:::
### Metastore Configuration

- Use AWS Glue as the Hive metastore for scalability and ease of management
- Set `hive.metastore=glue` and specify the region

### Authentication

- Use IAM roles (`hive.s3.iam-role`) for secure access to S3
- Ensure the IAM role has the least privileges necessary

### Performance Optimizations

- **Parquet and ORC**: Use columnar file formats like Parquet or ORC for better compression and query performance
- **Partitioning**: Partition tables based on frequently filtered columns to reduce query scan times
- **Caching**:
  - Enable metadata caching with `hive.metastore-cache-ttl` to reduce metastore calls
  - Configure `hive.file-status-cache-size` and `hive.file-status-cache-ttl` for file status caching

### Data Compression

- Enable compression for data stored in S3 to reduce storage costs and improve I/O performance

### Security Considerations

- **Encryption**: Use server-side encryption (SSE) or client-side encryption for data at rest in S3

- **Access Control**: Implement fine-grained access control using Ranger or AWS Lake Formation if necessary

- **SSL/TLS** Ensure `hive.s3.ssl.enabled=true` to encrypt data in transit
</CollapsibleContent>

<CollapsibleContent header={<span><h2>Iceberg</h2></span>}>

## Iceberg Connector Configuration
The Iceberg connector allows Trino to interact with data stored in Apache Iceberg tables, which is designed for large analytic datasets and supports features like schema evolution and hidden partitioning.

### Configuration Parameters

- **Connector Name**: iceberg
- **Catalog Type**: Use AWS Glue or Hive metastore
- **File Formats**: Parquet, ORC, or Avro
- **S3 Integration**: Configure S3 settings similar to the Hive connector

### Sample Iceberg Catalog Configuration

```properties
connector.name=iceberg
iceberg.catalog.type=glue
iceberg.file-format=PARQUET
iceberg.catalog.glue.region=us-west-2
iceberg.catalog.glue.iam-role=arn:aws:iam::123456789012:role/YourIAMRole
iceberg.register-table-procedure.enabled=true
hive.s3.aws-access-key=YOUR_ACCESS_KEY
hive.s3.aws-secret-key=YOUR_SECRET_KEY
hive.s3.iam-role=arn:aws:iam::123456789012:role/YourIAMRole
hive.s3.endpoint=s3.us-west-2.amazonaws.com
hive.s3.path-style-access=true
hive.s3.ssl.enabled=true
```

:::tip[Key Recommendations]
:::

### Catalog Configuration
- Use AWS Glue as the catalog for centralized schema management
- Set `iceberg.catalog.type=glue` and specify the region
- Use Iceberg REST Catalog protocol
 `iceberg.catalog.type=rest`
  `iceberg.rest-catalog.uri=https://iceberg-with-rest:8181/'` 

####   File Format
- Use Parquet or ORC for optimal performance
- Set `iceberg.file-format=PARQUET`

#### Schema Evolution
- Iceberg supports schema evolution without table rewrites
- Ensure `iceberg.register-table-procedure.enabled=true` to allow table registration

#### Partitioning
- Utilize hidden partitioning features of Iceberg to simplify query syntax and improve performance

#### Authentication
- Use IAM roles for secure access to S3 and Glue
- Ensure roles have necessary permissions for Iceberg operations

### Performance Optimizations

#### Snapshot Management
- Regularly expire old snapshots to prevent performance degradation
- Use `iceberg.expire-snapshots.min-snapshots-to-keep` and `iceberg.expire-snapshots.max-ref-age` settings

#### Metadata Caching
- Enable caching to reduce calls to the metastore
- Adjust `iceberg.catalog.cache-ttl` for caching duration

#### Parallelism
- Configure split sizes and parallelism settings to optimize read performance
- Adjust `iceberg.max-partitions-per-scan` and `iceberg.max-splits-per-node`

### Security Considerations

#### Data Encryption
- Implement encryption at rest and in transit

#### Access Control
- Apply fine-grained permissions using IAM policies

#### Compliance
- Ensure compliance with data governance policies when using schema evolution features

</CollapsibleContent>
</CollapsibleContent>

<CollapsibleContent header={<span><h2>Large Scale Query Optimizations</h2></span>}>

## Guide

A generic huide for optimizing large-scale queries in Trino can be found below. For more details refer to [query optimizer](https://trino.io/docs/current/optimizer.html)

### Memory Management
- Ensure proper allocation from container to query level
- Enable memory spilling with optimized thresholds

### Query Optimization
- Increase initialHashPartitions for better parallelism
- Use automatic join distribution and reordering
- Optimize split batch sizes for efficient processing

### Resource Management
- Enforce one pod per node for maximum resource utilization
- Allocate sufficient CPU while reserving resources for system processes
- Optimize garbage collection settings

### Exchange Management
- Use S3 with optimized settings for exchange data
- Increase concurrent connections and adjust upload part sizes

:::tip[Key Recommendations]
:::
- **Monitoring**: Use tools like Prometheus and Grafana for real-time metrics
- **Testing**: Simulate workloads/run POCs to validate configurations before production
- **Instance Selection**: Consider latest generation Graviton instances (Graviton3, Graviton4) for improved price-performance.
- **Network Bandwidth**: Ensure instances provide adequate network bandwidth to prevent bottlenecks

</CollapsibleContent>
