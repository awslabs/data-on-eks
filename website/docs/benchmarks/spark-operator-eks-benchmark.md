---
sidebar_position: 3
sidebar_label: Kubeflow Spark Operator Benchmarks
---

# Kubeflow Spark Operator Benchmarks 🚀
This document serves as a comprehensive guide for conducting a scale test for the Kubeflow Spark Operator on Amazon EKS. The primary objective is to evaluate the performance, scalability, and stability of the Spark Operator under heavy workloads by submitting thousands of jobs and analyzing its behavior under stress.

This guide provides a step-by-step approach to:

- Steps to **configure the Spark Operator** for high-scale job submissions.
- **Infrastructure setup** modifications for performance optimization.
- Load testing execution details using **Locust**.
- **Grafana dashboard** for monitoring Spark Operator metrics and Kubernetes metrics

### ✨ Why We Need the Benchmark Tests
Benchmark testing is a critical step in assessing the efficiency and reliability of the Spark Operator when handling large-scale job submissions. These tests provide valuable insights into:

- **Identifying performance bottlenecks:**  Pinpointing areas where the system struggles under heavy loads.
- **Ensuring optimized resource utilization:** Ensuring that CPU, memory, and other resources are used efficiently.
- **Evaluating system stability under heavy workloads:** Testing the system’s ability to maintain performance and reliability under extreme conditions.

By conducting these tests, you can ensure that the Spark Operator is capable of handling real-world, high-demand scenarios effectively.

### Prerequisites

- Before running the benchmark tests, ensure you have deployed the **Spark Operator** EKS cluster by following the instructions [here](https://awslabs.github.io/data-on-eks/docs/blueprints/data-analytics/spark-operator-yunikorn#deploy).
- Access to the necessary AWS resources and permissions to modify EKS configurations.
- Familiarity with **Terraform**, **Kubernetes**, and **Locust** for load testing.

### Updates to the Cluster

To prepare the cluster for benchmark testing, apply the following modifications:

**Step 1: Update Spark Operator Helm Configuration**

Uncomment the specified Spark Operator Helm values in the file [analytics/terraform/spark-k8s-operator/addons.tf](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/addons.tf) (from the `-- Start` to `-- End` section). Then, run terraform apply to apply the changes.

These updates ensure that:
- The Spark Operator and webhook pods are deployed on a dedicated `c5.9xlarge` instance using Karpenter.
- The instance provides `36 vCPUs` to handle `6000` application submissions.
- High CPU and memory resources are allocated for both the Controller pod and Webhook pods.

Here’s the updated configuration:

```yaml
enable_spark_operator = true
  spark_operator_helm_config = {
    version = "2.1.0"
    timeout = "120"
    values = [
      <<-EOT
        controller:
          replicas: 1
          # -- Reconcile concurrency, higher values might increase memory usage.
          # -- Increased from 10 to 20 to leverage more cores from the instance
          workers: 20
          # -- Change this to True when YuniKorn is deployed
          batchScheduler:
            enable: false
            # default: "yunikorn"
#  -- Start: Uncomment this section in the code for Spark Operator scale test
          # -- Spark Operator is CPU bound so add more CPU or use compute optimized instance for handling large number of job submissions
          nodeSelector:
            NodeGroupType: spark-operator-benchmark
          resources:
            requests:
              cpu: 33000m
              memory: 50Gi
        webhook:
          nodeSelector:
            NodeGroupType: spark-operator-benchmark
          resources:
            requests:
              cpu: 1000m
              memory: 10Gi
#  -- End: Uncomment this section in the code for Spark Operator scale test
        spark:
          jobNamespaces:
            - default
            - spark-team-a
            - spark-team-b
            - spark-team-c
          serviceAccount:
            create: false
          rbac:
            create: false
        prometheus:
          metrics:
            enable: true
            port: 8080
            portName: metrics
            endpoint: /metrics
            prefix: ""
          podMonitor:
            create: true
            labels: {}
            jobLabel: spark-operator-podmonitor
            podMetricsEndpoint:
              scheme: http
              interval: 5s
      EOT
    ]
  }
```

**Step 2: Prometheus Best practices for Large scale clusters**

- To efficiently monitor 32,000+ pods across 200 nodes, Prometheus should run on a dedicated node with increased CPU and memory allocation. Ensure Prometheus is deployed on core node groups using NodeSelectors in the Prometheus Helm chart. This prevents interference from workload pods.
- At scale, **Prometheus** can consume significant CPU and memory, so running it on dedicated infrastructure ensures it doesn’t compete with your apps. It’s common to dedicate a node or node pool solely to monitoring components (Prometheus, Grafana, etc.) using node selectors or taints.
- Prometheus is memory-intensive and, when monitoring hundreds or thousands of pods, will also demand substantial CPU​
- Allocating dedicated resources (and even using Kubernetes priority classes or QoS to favor Prometheus) helps keep your monitoring reliable under stress.
- Please note that full observability stack (metrics, logs, tracing) might consume roughly one-third of your infrastructure resources at scale​, so plan capacity accordingly.
- Allocate ample memory and CPU from the start, and prefer requests without strict low limits for Prometheus. For example, if you estimate Prometheus needs `~8 GB`, don’t cap it at `4 GB`. It’s better to reserve an entire node or a large chunk of one for Prometheus.

**Step 3: Configure VPC CNI for High Pod Density:**

Modify [analytics/terraform/spark-k8s-operator/eks.tf](https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/eks.tf) to enable `prefix delegation` in the `vpc-cni` addon. This increases the pod capacity per node from `110 to 200`.

```hcl
cluster_addons = {
  vpc-cni = {
    configuration_values = jsonencode({
      env = {
        ENABLE_PREFIX_DELEGATION = "true"
        WARM_PREFIX_TARGET       = "1"
      }
    })
  }
}
```

**Important Note:** After making these changes, run `terraform apply` to update the VPC CNI configuration.

**Step 4: Create a Dedicated Node Group for Spark Load Testing**

We have created a dedicated Managed node group called **spark_operator_bench** for placing the Spark Jobs pods. Configured a `200-node` managed node group with `m6a.4xlarge` instances for Spark load test pods. The user-data has been modified to allow up to `220 pods per node`.

**Note:** This step is informational only, and no changes need to be applied manually.

```hcl
spark_operator_bench = {
  name        = "spark_operator_bench"
  description = "Managed node group for Spark Operator Benchmarks with EBS using x86 or ARM"

  min_size     = 0
  max_size     = 200
  desired_size = 0
  ...

  cloudinit_pre_nodeadm = [
    {
      content_type = "application/node.eks.aws"
      content      = <<-EOT
        ---
        apiVersion: node.eks.aws/v1alpha1
        kind: NodeConfig
        spec:
          kubelet:
            config:
              maxPods: 220
      EOT
    }
  ]
...

}
```

**Step 5: Manually Update Node Group Min Size to 200**

:::caution

Running 200 nodes can incur significant costs. If you plan to run this test independently, carefully estimate the expenses in advance to ensure budget feasibility.

:::

Initially, set `min_size = 0`. Before starting the load test, update `min_size` and `desired_size` to `200` in the AWS console. This pre-creates all nodes required for the load test, ensuring all DaemonSets are running.

### Load Test Configuration and Execution

To simulate high-scale concurrent job submissions, we developed **Locust** scripts that dynamically create Spark Operator templates and submit jobs concurrently by simulating multiple users.

**Step 1: Set Up a Python Virtual Environment**
On your local machine (Mac or desktop), create a Python virtual environment and install the required dependencies:

```
cd analytics/terraform/spark-k8s-operator/examples/benchmark/spark-operator-benchmark-kit
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

**Step 2: Run the Load Test**
Execute the following command to start the load test:

```sh
locust --headless --only-summary -u 3 -r 1 \
--job-limit-per-user 2000 \
--jobs-per-min 1000 \
--spark-namespaces spark-team-a,spark-team-b,spark-team-c
```

This command:
- Starts a test with **3 concurrent users**.
- Each user submits **2000 jobs** at a rate of **1000 jobs per minute**.
- Total of **6000 jobs** are submitted by this command. Each Spark job consists of **6 pods** (1 Driver and 5 executor pods)
- Generates **36,000 pods** across **200 nodes** using **3 namespaces**.

- Locust script uses the Spark job template located at: `analytics/terraform/spark-k8s-operator/examples/benchmark/spark-operator-benchmark-kit/spark-app-with-webhook.yaml`.

- Spark job uses a simple `spark-pi-sleep.jar` that sleeps for a specified duration. The testing image is available at: `public.ecr.aws/data-on-eks/spark:pi-sleep-v0.0.2`

### Results Verification
The load test runs for approximately 1 hour. During this time, you can monitor the Spark Operator metrics, cluster performance and resource utilization using Grafana. Follow the steps below to access the monitoring dashboard:

**Step1: Port-forward Grafana Service**
Run the following command to create a local port-forward, making Grafana accessible from your local machine:

```sh
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n kube-prometheus-stack
```
This maps port 3000 on your local system to Grafana's service inside the cluster.

**Step2: Access Grafana**
To log into Grafana, retrieve the secret name storing the admin credentials:

```bash
terraform output grafana_secret_name
```

Then, use the retrieved secret name to fetch credentials from AWS Secrets Manager:

```bash
aws secretsmanager get-secret-value --secret-id <grafana_secret_name_output> --region $AWS_REGION --query "SecretString" --output text
```

**Step 3: Access Grafana Dashboard**
1. Open a web browser and navigate to http://localhost:3000.
2. Enter username as `admin` and password as the retrieved password from the previous command.
3. Navigate to the Spark Operator Load Test Dashboard to visualize:

- The number of Spark jobs submitted.
- Cluster-wide CPU and memory consumption.
- Pod scaling behavior and resource allocation.

## Summary of Results

:::tip

For a detailed analysis, refer to the [Kubeflow Spark Operator Website](https://www.kubeflow.org/docs/components/spark-operator/overview/)

:::

**CPU Utilization:**

- The Spark Operator controller pod is CPU-bound, utilizing all 36 cores during peak processing.
- CPU constraints limit job processing speed, making compute power a key factor for scalability.

**Memory Usage:**
- Memory consumption remains stable, regardless of the number of applications processed.
- This indicates that memory is not a bottleneck, and increasing RAM would not improve performance.

**Job Processing Rate:**
- The Spark Operator processes applications at ~130 apps per minute.
- The processing rate is capped by CPU limitations, preventing further scaling without additional compute resources.

**Time to Process Jobs:**
- ~15 minutes to process 2,000 applications.
- ~30 minutes to process 4,000 applications.
- These numbers align with the observed 130 apps per minute processing rate.

**Work Queue Duration Metric Reliability:**
- The default work queue duration metric becomes unreliable once it exceeds 16 minutes.
- Under high concurrency, this metric fails to provide accurate insights into queue processing times.

**API Server Performance Impact:**
- Kubernetes API request duration increases significantly under high workload conditions.
- This is caused by Spark querying executor pods frequently, not a limitation of the Spark Operator itself.
- The increased API server load affects job submission latency and monitoring performance across the cluster.

## Cleanup

**Step 1: Scale Down Node Group**

To avoid unnecessary costs, first scale down the **spark_operator_bench** node group by setting its minimum and desired node count to zero:

1. Log in to the AWS Console.
2. Navigate to the EKS section.
3. Locate and select the **spark_operator_bench** node group.
4. Edit the node group and update the Min Size and Desired Size to 0.
5. Save the changes to scale down the nodes.

**Step 2: Destroy the Cluster**
Once the nodes have been scaled down, you can proceed with cluster teardown using the following script:

```sh
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator && chmod +x cleanup.sh
./cleanup.sh
```
