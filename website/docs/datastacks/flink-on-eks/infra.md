---
title: Flink Infrastructure Deployment
sidebar_label: Infrastructure
sidebar_position: 2
---

# Flink on EKS Infrastructure Deployment

Complete guide for deploying and configuring the Flink on EKS infrastructure for streaming workloads.

## Overview

The Flink on EKS infrastructure provides a production-ready foundation for Apache Flink streaming workloads on Amazon EKS. It includes:

- **EKS Cluster** with streaming-optimized configurations
- **Flink Operator** for native Kubernetes Flink job management
- **Kafka Cluster** for event streaming and data ingestion
- **State Backend** with S3 storage for fault tolerance
- **Monitoring Stack** with Flink-specific metrics and dashboards

## Quick Start

```bash
# Clone the repository
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/data-stacks/flink-on-eks

# Deploy the infrastructure
./deploy-blueprint.sh

# Verify deployment
kubectl get nodes
kubectl get pods -n flink-operator
```

## Configuration Options

### Blueprint Configuration (`terraform/blueprint.tfvars`)

#### Basic Settings
```hcl
# Deployment configuration
region = "us-west-2"
name   = "flink-on-eks"

# Cluster settings
eks_cluster_version = "1.33"
vpc_cidr           = "10.0.0.0/16"
secondary_cidrs    = ["100.64.0.0/16"]
```

#### Flink-Specific Components
```hcl
# Flink platform
enable_flink_operator       = true   # Flink job management
enable_kafka               = true    # Event streaming
enable_flink_history_server = true   # Job monitoring
```

#### Monitoring & Observability
```hcl
# Monitoring stack
enable_kube_prometheus_stack = true   # Prometheus + Grafana
enable_aws_for_fluentbit    = false  # Log aggregation
```

#### Networking
```hcl
# Networking
enable_ingress_nginx = true   # Load balancing
enable_cert_manager  = false  # TLS management
```

## Architecture Components

### Core Infrastructure

#### Apache Flink Operator
- Native Kubernetes CRDs for Flink jobs
- JobManager and TaskManager management
- State backend configuration
- Checkpoint coordination
- Recovery and scaling

#### Kafka Cluster
- Event streaming platform
- Topic management
- Consumer group coordination
- Schema registry integration
- High availability setup

#### State Management
- S3-backed state storage
- RocksDB local state
- Checkpoint configuration
- Savepoint management
- Recovery mechanisms

## Deployment Process

### 1. Prerequisites Check
```bash
# Required tools
- AWS CLI configured
- Terraform >= 1.0
- kubectl >= 1.28
- Git

# AWS permissions
- EKS management
- VPC and EC2 operations
- IAM role management
- S3 access for state storage
```

### 2. Infrastructure Deployment
```bash
# Automated deployment process
./deploy-blueprint.sh

# Manual step-by-step deployment
cd terraform/_local
terraform init
terraform plan
terraform apply
```

### 3. Post-Deployment Verification
```bash
# Verify cluster
kubectl get nodes
kubectl get pods --all-namespaces

# Check Flink Operator
kubectl get flinkdeployment -n flink-operator

# Check Kafka cluster
kubectl get pods -n kafka

# Access Flink UI
kubectl port-forward svc/flink-jobmanager-ui -n flink-operator 8081:8081
```

## Flink Configuration

### JobManager Configuration
```yaml
# JobManager deployment
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: basic-example
spec:
  image: flink:1.18-java11
  flinkVersion: v1_18
  jobManager:
    replicas: 1
    resource:
      memory: "2048m"
      cpu: 1
  taskManager:
    replicas: 3
    resource:
      memory: "2048m"
      cpu: 1
```

### State Backend Configuration
```yaml
# S3 state backend
flinkConfiguration:
  state.backend: rocksdb
  state.checkpoints.dir: s3://your-bucket/checkpoints
  state.savepoints.dir: s3://your-bucket/savepoints
  execution.checkpointing.interval: 60000
  execution.checkpointing.mode: EXACTLY_ONCE
```

## Kafka Integration

### Kafka Cluster Setup
```yaml
# Kafka cluster configuration
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: my-cluster
spec:
  kafka:
    version: 3.7.0
    replicas: 3
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
```

### Topic Management
```yaml
# Kafka topic for Flink
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: flink-input-topic
  labels:
    strimzi.io/cluster: my-cluster
spec:
  partitions: 12
  replicas: 3
  config:
    retention.ms: 604800000
    segment.ms: 86400000
```

## Monitoring & Observability

### Flink Metrics
- Job execution metrics
- TaskManager resource utilization
- Checkpoint duration and success rate
- Backpressure indicators
- State size monitoring

### Grafana Dashboards
- Flink Job Overview
- TaskManager Metrics
- Kafka Integration Metrics
- State Backend Performance
- Resource Utilization

### Alerting Rules
- FlinkJobFailed
- CheckpointFailure
- HighBackpressure
- TaskManagerDown
- KafkaConsumerLag

## Troubleshooting

### Common Issues

#### Flink Jobs Not Starting
```bash
# Check Flink Operator logs
kubectl logs -n flink-operator deployment/flink-kubernetes-operator

# Check job status
kubectl describe flinkdeployment <job-name> -n flink-operator
```

#### Checkpoint Failures
```bash
# Check S3 permissions
aws s3 ls s3://your-bucket/checkpoints/

# Verify state backend configuration
kubectl logs <jobmanager-pod> -n flink-operator
```

#### Kafka Connection Issues
```bash
# Check Kafka cluster status
kubectl get kafka -n kafka

# Test connectivity
kubectl exec -n kafka my-cluster-kafka-0 -- \
  bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

## Best Practices

### Resource Management
- Right-size JobManager and TaskManager resources
- Configure appropriate parallelism
- Use slot sharing for resource efficiency
- Monitor memory usage and garbage collection

### State Management
- Choose appropriate state backend
- Configure checkpoint intervals wisely
- Monitor state size growth
- Implement state cleanup strategies

### Fault Tolerance
- Enable exactly-once processing
- Configure appropriate restart strategies
- Use savepoints for job updates
- Implement proper error handling

## Cleanup

### Infrastructure Cleanup
```bash
# Complete cleanup
./cleanup.sh

# Manual cleanup
cd terraform/_local
terraform destroy -auto-approve
```

## Next Steps

After deploying the infrastructure:

1. **Submit Streaming Jobs** - Deploy Flink streaming applications
2. **Configure State Backend** - Set up S3 state storage
3. **Monitor Performance** - Set up custom dashboards and alerts
4. **Integrate with Kafka** - Connect to event streams

## Related Examples

- [Real-time WordCount](./wordcount-streaming)
- [Back to Examples](/data-on-eks/docs/datastacks/flink-on-eks/)
