# Changes to the Data On EKS blueprint for scale testing
There were a few changes made to the spark-operator blueprint in order to run scale tests.

## Spark Operator
### Update the operator helm version
At the time of our testing `2.1.0` was the most recent helm chart version.

in `addons.tf`:
```sh
  spark_operator_helm_config = {
    version = "2.1.0"
```

### Run spark-operator and webhook on a dedicated node with Taints/Tolerations
Spark-operator consumes a lot of CPU, and the system nodes were small by default.
We reused the `spark_benchmark_ssd` node group in `eks.tf`, updated the instance type and added taints. For our testing we manually scaled this Autoscaling group up and down to accommodate the Spark operator pods.

**Note**: We also saw the Prometheus server in our cluster failing with OOM events due to the amount of metrics being collected. We moved the prometheus pods to a dedicated node using the same selectors/tolerations and disabled the `"spark-job-monitoring"` scrape config in `helm-values/kube-prometheus.yaml` or `helm-values/kube-prometheus-amp-enable.yaml`

in `eks.tf`:
```sh
    # This Group can be used to back the spark operator, we can put it on a stand alone box via to ensure the best performance.
    spark_benchmark_ssd = {
      name        = "spark_benchmark_ssd"
      description = "Managed node group for Spark Benchmarks with NVMEe SSD using x86 or ARM"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      ami_type = "AL2023_x86_64_STANDARD" # x86

      # Node group will be created with zero instances when you deploy the blueprint.
      # You can change the min_size and desired_size to 6 instances
      # desired_size might not be applied through terrafrom once the node group is created so this needs to be adjusted in AWS Console.
      min_size     = var.spark_benchmark_ssd_min_size # Change min and desired to 6 for running benchmarks
      max_size     = 8
      desired_size = var.spark_benchmark_ssd_desired_size # Change min and desired to 6 for running benchmarks

      instance_types = ["c5.9xlarge"] # 36vCPU and 72GiB

      labels = {
        NodeGroupType = "spark_benchmark_ssd"
      }

      taints = {
        benchmark = {
          key      = "spark-benchmark"
          effect   = "NO_SCHEDULE"
          operator = "EXISTS"
        }
      }

      tags = {
        Name          = "spark_benchmark_ssd"
        NodeGroupType = "spark_benchmark_ssd"
      }
    }

  }

```

In the Spark operator we added node selectors, and tolerations to the helm config so the Pods would run on the new nodes

in `addons.tf`:
```sh
  spark_operator_helm_config = {
    version = "2.1.0"
    values = [
      <<-EOT
        controller:
          # -- Node selector for controller pods.
          nodeSelector:
            NodeGroupType: spark_benchmark_ssd
          # -- List of node taints to tolerate for controller pods.
          tolerations:
            - key: spark-benchmark
              operator: Exists
              effect: NoSchedule
        webhook:
          # -- Node selector for controller pods.
          nodeSelector:
            NodeGroupType: spark_benchmark_ssd
          # -- List of node taints to tolerate for controller pods.
          tolerations:
            - key: spark-benchmark
              operator: Exists
              effect: NoSchedule
    ...
```

### Enable the PodMonitor for Spark Operator
In the Spark operator helm config we enabled the PodMonitor object so the kube-prometheus-stack is able to scrape the metrics from the operator.

in `addons.tf` (the spark-operator values)
```yaml
        prometheus:
          metrics:
            enable: true
            port: 8080
            portName: metrics
            endpoint: /metrics
            prefix: ""
          # Prometheus pod monitor for controller pods
          # Note: The kube-prometheus-stack addon must deploy before the PodMonitor CRD is available.
          #       This can cause the terraform apply to fail since the addons are deployed in parallel
          podMonitor:
            # -- Specifies whether to create pod monitor.
            create: true
            labels: {}
            # -- The label to use to retrieve the job name from
            jobLabel: spark-operator-podmonitor
            # -- Prometheus metrics endpoint properties. `metrics.portName` will be used as a port
            podMetricsEndpoint:
              scheme: http
              interval: 5s
      EOT
    ]
  }
```

This may cause creation issues as there is not an explicit dependency between the spark-operator and the kube-prometheus-stack. The Spark-operator chart may try to create the PodMonitor before the CRD is registered.

To avoid that we've added a module to the install script to ensure the CRD is available when we install the data addons

in `install.sh`
```sh
#!/bin/bash

read -p "Enter the region: " region
export AWS_DEFAULT_REGION=$region

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
  "module.eks_blueprints_addons" # install kube-prometheus-first for PodMonitor CRD
)
```

## EKS

### Enable Prefix Delegation
To increase the pod density on the nodes we enabled Prefix delegation in the VPC CNI.
We first tried to enable this configuration in the addons.tf file, however there seems to be a timing issue where the EKS nodegroups are created before the CNI is configured (because the addons are dependent on the EKS cluster module)

To resolve this we moved the CNI and EKS Addon configuration into the EKS module and used the `before_compute = true` option to ensure the prefix delegation was applied first.

in `eks.tf`:
```sh
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.26"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version
[...]

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  cluster_addons = {
    coredns = {
      preserve = true
    }
    vpc-cni = {
      before_compute = true
      preserve = true
      most_recent    = true # To ensure access to the latest settings provided
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = {
      preserve = true
    }
  }
```
