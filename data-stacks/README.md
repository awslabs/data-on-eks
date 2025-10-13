# Data Stacks for EKS

## Overview

Welcome to the `data-stacks` directory. This directory contains a collection of pre-configured, independently deployable data stacks that can be provisioned on top of the common EKS infrastructure. Each subdirectory represents a specific, ready-to-use data workload, such as Apache Spark, Apache Flink, or Trino.

## Core Concepts: The "Base + Stack" Pattern

This repository uses a layering system to combine shared infrastructure with stack-specific customizations. This allows for both consistency and flexibility.

### The Base Layer (`infra/`)

The `infra/` directory contains the shared, foundational infrastructure for all data stacks. This includes the common EKS cluster, networking (VPC), security configurations, and observability components (e.g., Prometheus, Grafana).

### The Stack Layer (`data-stacks/`)

Each subdirectory within `data-stacks/` is a self-contained stack that builds upon the base layer. It contains all the necessary Terraform configurations and Kubernetes manifests to deploy a specific data tool or platform.

### Intelligent File Layering

When a stack is deployed, a temporary `_local/` directory is created inside the stack's folder. The deployment script layers files to create the final configuration:

1.  **Copy Base:** It starts by copying the entire `infra/` directory into the `_local/` directory.
2.  **Overlay Stack:** It then copies the contents of the current stack directory (e.g., `spark-on-eks/`) on top of the base files.
3.  **Override Logic:** If a file from the stack has the same name and path as a file from the base, the stack's file **completely replaces** the base file. This allows any part of the base infrastructure to be customized for a specific stack's needs.

Here is a practical example:

Suppose the base `infra/terraform/karpenter.tf` defines a default EC2 instance type for worker nodes. If the `spark-on-eks` stack requires a different, memory-optimized instance type, you can create a custom `karpenter.tf` file inside the `data-stacks/spark-on-eks/terraform/` directory.

When `./deploy.sh` is run from `data-stacks/spark-on-eks/`, the custom `karpenter.tf` will replace the base version in the `_local/` directory.

#### Visualization of the Override Process

```
.
├── infra/
│   └── terraform/
│       ├── eks.tf
│       ├── vpc.tf
│       └── karpenter.tf  (Base version)
│
├── data-stacks/
│   └── spark-on-eks/
│       ├── deploy.sh
│       └── terraform/
│           └── karpenter.tf  (Custom version for Spark)
│
└── (Deployment Execution)
    │
    └─> Creates...
        │
        └── data-stacks/spark-on-eks/_local/
            └── terraform/
                ├── eks.tf          (from infra)
                ├── vpc.tf          (from infra)
                └── karpenter.tf  (REPLACED by Spark's version)

```

This approach provides an override capability that goes beyond what is possible with standard Terraform variables, while keeping each stack's configuration clean and isolated.

## How to Deploy a Stack

Deploying a stack is a simple, one-command process.

### Prerequisites

Before you begin, ensure you have the following command-line tools installed and configured:

*   `aws-cli`
*   `kubectl`
*   `terraform`

### Deployment Steps

1.  **Navigate to a Stack Directory:**
    Change into the directory of the stack you wish to deploy.
    ```sh
    cd data-stacks/<stack-name>
    ```
    For example:
    ```sh
    cd data-stacks/spark-on-eks
    ```

2.  **Run the Deployment Script:**
    Execute the deployment script to provision the EKS cluster and the selected data stack.
    ```sh
    ./deploy.sh
    ```

The script will handle the entire process of layering the files, initializing Terraform, and applying the configuration.

## Available Stacks

This repository currently includes the following data stacks:

*   `flink-on-eks`: Provisions an Apache Flink environment for real-time stream processing.
*   `spark-on-eks`: Deploys the Kubernetes Operator for Apache Spark.
*   `trino-on-eks`: Sets up a Trino cluster for distributed SQL queries.
*   `workshop`: A special stack used for a workshop.

## Customization

You can customize any stack by adding or modifying files within its directory. To override a file from the base `infra/` layer, create a file with the **exact same name and relative path** inside the stack's directory. During deployment, your custom file will replace the base version.

This should primarily be used for customizations that are not easily achievable through Terraform variables.

## Contributing

We welcome contributions! If you would like to add a new data stack to this repository, please follow the existing directory structure and patterns. For more detailed contribution guidelines, please refer to the main `CONTRIBUTING.md` file at the root of the repository.
