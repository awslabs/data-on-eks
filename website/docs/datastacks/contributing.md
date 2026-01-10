---
sidebar_label: Contribution Guide
---

## Contributing to Data Stacks

This guide explains the repository's structure and the design patterns used for defining and deploying data stacks. The primary goal is to enable developers to easily customize existing stacks or create new ones.

### Core Concept: The Base and Overlay Pattern

The repository uses a "Base + Overlay" pattern to manage infrastructure and data stack deployments.

*   **Base (`infra/`):** This directory contains the foundational Terraform configuration for the EKS cluster, networking, security, monitoring, and other shared resources. It defines the default, common infrastructure for all data stacks.

*   **Overlay (`data-stacks/<stack-name>/`):** Each directory within `data-stacks` represents a specific data analytics stack (e.g., `spark-on-eks`). It contains only the files necessary to *customize* or *extend* the base infrastructure for that particular workload.

This structure can be visualized as follows:

```
data-on-eks/
├── infra/                          # Base infrastructure templates
│   └── terraform/
│       ├── main.tf
│       ├── s3.tf
│       ├── argocd-applications/
│       │   └── *.yaml
│       ├── helm-values/            # Terraform templated YAML files for Helm values
│       │   └── *.yaml
│       └── manifests/              # Terraform templated YAML files for K8s manifests
│           └── *.yaml
│
└── data-stacks/
    └── spark-on-eks/               # Example Data Stack
        ├── _local/                 # Working directory (auto-generated). terraform is executed in this folder
        ├── deploy.sh
        └── terraform/              # Installation script
            ├── s3.tf                   # Overrides infra/terraform/s3.tf
            ├── *.tfvars
            └── argocd-applications/    # Overrides infra/terraform/argocd-applications
                └── *.yaml
```

### Special File Types and Directories within `infra/terraform/`

The `infra/terraform/` directory contains not only standard Terraform configuration (`.tf` files) but also special directories and files that facilitate dynamic configuration and GitOps integration:

*   **`helm-values/`:** This directory contains Helm `values.yaml` files, which are used by ArgoCD to deploy applications. Crucially, these are often **Terraform templated YAML files**. This means Terraform processes them first, populating them with dynamic information (such as the EKS cluster name or other environment-specific details). The rendered Helm values are then embedded directly into the ArgoCD application manifest files before ArgoCD consumes them.

*   **`manifests/`:** Similar to `helm-values`, this directory can contain Kubernetes manifest files that are also **Terraform templated YAML files**. These manifests are *applied directly by Terraform* as part of the `terraform apply` process, typically using the `kubernetes_manifest` or `kubectl_manifest` resources. They are *not* deployed or managed by ArgoCD.

This distinction is important: `helm-values` are for ArgoCD-managed Helm deployments, while `manifests` are for Kubernetes resources directly managed by Terraform.

### Design Philosophy: Why This Pattern?
The current "Base + Overlay" pattern was developed to address several significant challenges faced in previous iterations of this repository:

1.  **Duplication and Inconsistency:** In earlier versions, each data stack (blueprint) was a completely independent Terraform stack. This led to extensive code duplication and inconsistencies across stacks. Even common components, like Karpenter node group specifications, often had slight but divergent configurations.
2.  **High Maintenance Overhead:** Managing and testing a large number of disparate Terraform stacks proved exceptionally difficult. Keeping modules and component versions synchronized across all blueprints was a continuous struggle, often resulting in different module versions being used for similar functionalities across various stacks.
3.  **Difficulty in Upgrades and Validation:** Updating components (e.g., to a new version of a Flink operator) was a complex and error-prone process. It was hard to determine which blueprints were affected and to validate that updates wouldn't introduce regressions.

This file overlay system was designed to overcome these issues, promoting reusability, consistency, and easier maintenance compared to relying solely on Terraform variables or modules.

You might wonder why we use this file overlay system instead of relying solely on Terraform variables or modules.

While a centralized Terraform module was considered, it was ultimately rejected. A single, monolithic module would have to accommodate every potential combination of technologies, quickly becoming large and complex.

For example, DataHub requires Kafka, Elasticsearch, and PostgreSQL. Airflow also uses PostgreSQL, but often with a slightly different configuration. In a monolithic module, these differences would need to be exposed as a complex web of input variables. As more technologies and combinations are added, the number of variables would explode, making the module difficult to understand, maintain, and use.

The overlay pattern provides a clearer separation of concerns. The base provides the common "what," and the stack overlay provides the specialized "how" for that specific context, without overloading a central module with excessive conditional logic and variables.

*   **Simplicity and Discoverability:** Customizing a stack is as simple as creating a file in the stack's directory with the same name and path as the base file you want to change. This makes it very easy to see exactly what a specific stack is overriding without tracing complex variable interpolations or module logic.

*   **Handling Complex Overrides:** While simple changes should be handled by Terraform variables (`.tfvars`), this pattern excels at making complex changes that variables can't handle easily. For example, completely replacing a resource definition, changing provider configurations, or adding entirely new Kubernetes manifests via the ArgoCD integration.

*   **When to Override vs. When to Use Variables:**
    *   **Use `.tfvars` for:** things that are common across many data stacks like instance count, enabling common technologies like ingress-nginx.
    *   **Use file overrides for:** Structural changes to Terraform resources, replacing entire Kubernetes manifests, or adding new files that have no equivalent in the base. **File overrides are a powerful tool and should be used judiciously.**

### The Deployment Process

When you run `./deploy.sh` from a stack's directory (e.g., `data-stacks/spark-on-eks/`), it triggers a centralized deployment engine (`infra/terraform/install.sh`) that performs the following steps:

1.  **Workspace Preparation:** The script prepares a working directory named `_local/` inside your stack's `terraform/` folder. It cleans this directory by removing old files but preserves essential Terraform state (`terraform.tfstate*`), plugin caches (`.terraform/`), and lock files (`.terraform.lock.hcl`). This makes subsequent runs much more efficient.

2.  **Foundation Copy:** The script copies the entire `infra/terraform/` directory into the `_local/` workspace.

3.  **Overlay Application:** It then recursively copies your stack-specific files from `data-stacks/<stack-name>/terraform/` into `_local/`, **overwriting any base files that have the same name and path.**

4.  **Terraform Execution:** The script executes Terraform within the `_local/` directory in a specific, multi-stage sequence to ensure stability:
    *   First, it runs `terraform init -upgrade` to prepare the workspace.
    *   Next, it applies core infrastructure with `terraform apply -target=module.vpc`.
    *   Then, it applies the EKS cluster with `terraform apply -target=module.eks`.
    *   Finally, it runs `terraform apply` one last time without a target to deploy all remaining resources.

5.  **GitOps Sync:** It deploys ArgoCD Application manifests from your stack, pointing your GitOps controller to the right resources for continuous delivery.

---

### How to Add a New Data Stack

Here is a step-by-step guide to creating a new stack called `my-new-stack`.

**Step 1: Create the Stack Directory**

The easiest way to start is by copying an existing stack that is similar to what you want to build.

```bash
# Example: copy the spark-on-eks stack to start
cp -r data-stacks/spark-on-eks data-stacks/my-new-stack
```

**Step 2: Customize the Configuration**

Now, modify the files inside `data-stacks/my-new-stack/terraform/`.

*   **To change a simple variable:** Edit the `*.tfvars` file (e.g., `data-stack.tfvars`). This is the preferred method for simple changes.

    ```hcl
    // data-stacks/my-new-stack/terraform/data-stack.tfvars
    cluster_name = "my-new-eks-cluster"
    ```
    **Note on `deployment_id`**: If you copy a stack, the `data-stack.tfvars` file will contain a placeholder like `deployment_id = "abcdefg"`. On your first run of `./deploy.sh`, the script will automatically replace this with a new random ID.

*   **To override a base infrastructure file:** Let's say you want to use a different S3 bucket configuration. The base file is at `infra/terraform/s3.tf`. To override it, simply edit `data-stacks/my-new-stack/terraform/s3.tf`. The deploy script will use your version instead of the base one.

*   **To add a new component:** Create a new file, for example `data-stacks/my-new-stack/terraform/my-new-resource.tf`. This file will be added to the configuration during deployment.

**Step 3: Customize ArgoCD Applications**

The base `infra/argocd-applications` directory contains the default set of ArgoCD `Application` manifests. To customize these for your stack:

1.  Copy the `infra/argocd-applications` directory to `data-stacks/my-new-stack/terraform/argocd-applications`.
2.  Modify the YAML files inside. You might want to:
    *   Change the `source.helm.values` to point to a custom values file.
    *   Change the `destination.namespace`.

During deployment, your stack's `argocd-applications` directory will completely replace the base one.

**Step 4: Deploy and Test**

Run the deployment script from your new stack's directory:

```bash
cd data-stacks/my-new-stack
./deploy.sh
```

Inspect the Terraform plan and apply it. Once complete, check your EKS cluster and ArgoCD UI to verify that your new stack has been deployed as expected.

**Step 5: Cleaning Up a Stack**

Each data stack includes a `cleanup.sh` script, which is the counterpart to `deploy.sh`. This script is responsible for destroying all resources created by the stack to avoid unwanted costs.

The process mirrors the deployment workflow:
1.  The `cleanup.sh` script in your stack directory (e.g., `data-stacks/my-new-stack/`) is a wrapper that navigates into the `_local/` workspace.
2.  It then executes the main `cleanup.sh` engine, which was copied from `infra/terraform/`.

The cleanup engine is more sophisticated than a simple `terraform destroy`. It performs a multi-stage cleanup to ensure resources are removed in the correct order:
*   **Pre-Terraform Cleanup:** It runs `kubectl delete` to immediately remove certain Kubernetes resources.
*   **Targeted Terraform Destroy:** It intelligently targets and destroys specific Kubernetes manifests managed by Terraform first.
*   **Full Terraform Destroy:** It runs a full `terraform destroy` to remove the remaining infrastructure.
*   **EBS Volume Cleanup:** After the destroy command finishes, the script performs a critical final step. It uses the stack's unique `deployment_id` to find and delete any orphaned EBS volumes that may have been left behind by Kubernetes PersistentVolumeClaims (PVCs).

To run the cleanup process:
```bash
cd data-stacks/my-new-stack
./cleanup.sh
```

---
## Other Conventions

### `examples/` Directory
When creating a new stack, you may also see an `examples/` directory. This folder is the conventional place to store usage examples, tutorials, sample code, or queries related to the data stack. It is good practice to include examples to help users get started with your new data stack.
