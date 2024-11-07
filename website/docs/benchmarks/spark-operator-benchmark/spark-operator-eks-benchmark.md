---
sidebar_position: 1
sidebar_label: Introduction to Spark Benchmarks
---

# Introduction to Spark Benchmarks on Amazon EKS 🚀

This guide walks you through running Apache Spark benchmark tests on Amazon EKS, AWS's managed Kubernetes service. Benchmark tests help evaluate and optimize Spark workloads on EKS comparing benchmark results run across different EC2 instance families of Graviton instances, especially when scaling for performance, cost efficiency, and reliability.
Key Features 📈

- Data Generation for the benchmark tests
- Benchmark Test Execution on Different generation of Graviton Instances (r6g, r7g, r8g)
- Benchmark Results
- Customizable Benchmarks to suit your workloads
- Autoscaling and Cost Optimization Strategies

## 📊 TPC-DS Benchmark for Spark

The TPC-DS benchmark is an industry-standard benchmark created by the Transaction Processing Performance Council (TPC) to evaluate the performance of decision support systems. It is widely used to assess the efficiency of SQL-based data processing engines in handling complex analytical queries. Databricks has optimized TPC-DS for Apache Spark, making it highly relevant for evaluating Spark workloads in cloud and on-premise environments.

The TPC-DS benchmark tests cover a range of complex, data-intensive queries that simulate realistic decision support systems, making it ideal for assessing Spark's performance with structured and semi-structured data.

📈 Some Details on TPC-DS Benchmarks for Spark

The TPC-DS benchmark for Spark on Databricks includes the following features and considerations:

- Dataset Size: TPC-DS provides standardized datasets ranging from a few gigabytes to multiple terabytes, allowing users to test Spark's scalability.
- Query Suite: The benchmark includes 99 queries that simulate real-world decision support scenarios. These queries test Spark's ability to handle joins, aggregations, and complex nested queries efficiently.
- Optimization Techniques: Databricks has implemented various Spark-specific optimizations to improve TPC-DS query performance, such as Catalyst Optimizer, Adaptive Query Execution (AQE), and optimized shuffle operations.
- Execution Environment: The benchmark tests typically run in a distributed environment and cloud platform (such as Amazon EKS), leveraging optimized runtime for Apache Spark.

**Note:** The results of TPC-DS benchmarks on Spark can vary significantly depending on cluster configurations, instance types, and Spark settings.

### ✨ Why We Need the Benchmark Tests

Benchmark tests are crucial for the following reasons:

- Performance Evaluation: They provide an objective measure to evaluate and compare the speed, efficiency, and scalability of Spark engines on various cloud and hardware configurations.

- Optimization Insights: By analyzing benchmark results, users can gain insights into specific areas where Spark might be optimized to handle large-scale, complex analytical queries.

- Infrastructure Comparison: Running TPC-DS on Spark on Amazon EKS allows teams to make data-driven decisions on the best platforms for their data workloads.

- Operational Readiness: Ensures that the Spark setup is ready to handle large datasets and complex analytical tasks, reducing risks in production environments.

### 🎁 What We Offer

With Data-on-EKS blueprints, we offer

- Ready to be deployed Infrastructure-as-Code(Terraform) templates
- Benchmark Test Data Generation Toolkit
- Benchmark Execution Toolkit

### 💰 A Note on Cost

To minimize costs, we recommend terminating the `C5d` instances once the benchmark data generation toolkit completes execution and the data has been successfully stored in the S3 bucket. This approach ensures that resources are only used when necessary, helping to keep expenses under control.

## 🔗 Additional Resources

[TPCDS Specification](https://www.tpc.org/tpcds/default5.asp)
