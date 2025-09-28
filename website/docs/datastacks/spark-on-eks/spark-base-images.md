---
title: Spark Base Images
sidebar_position: 12
---

# Spark Base Images

Custom Docker images with optimized Spark configurations, pre-installed dependencies, and security hardening for production workloads.

## Overview

This blueprint provides production-ready Spark Docker images with optimized configurations, security hardening, and commonly used dependencies pre-installed for efficient deployment.

## Key Features

- **Optimized Configuration**: Pre-tuned Spark settings for EKS
- **Security Hardening**: Non-root user, minimal attack surface
- **Dependency Management**: Common libraries pre-installed
- **Multi-Architecture**: ARM64 and x86_64 support
- **Layer Optimization**: Efficient Docker layer caching

## Quick Build & Deploy

### 1. Build Custom Spark Image

```bash
# Navigate to data-stacks directory
cd data-stacks/spark-on-eks/docker

# Build optimized Spark image
docker build -t spark-optimized:latest -f Dockerfile .

# Build for ARM64
docker buildx build --platform linux/arm64 -t spark-optimized:latest-arm64 -f Dockerfile .
```

### 2. Push to ECR

```bash
# Create ECR repository
aws ecr create-repository --repository-name spark-optimized

# Get login token
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-west-2.amazonaws.com

# Tag and push
docker tag spark-optimized:latest <account>.dkr.ecr.us-west-2.amazonaws.com/spark-optimized:latest
docker push <account>.dkr.ecr.us-west-2.amazonaws.com/spark-optimized:latest
```

### 3. Deploy Spark Application

```bash
kubectl apply -f - <<EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: custom-spark-app
  namespace: spark-team-a
spec:
  type: Python
  mode: cluster
  image: "<account>.dkr.ecr.us-west-2.amazonaws.com/spark-optimized:latest"
  mainApplicationFile: "s3a://spark-on-eks-data/scripts/sample-job.py"
  driver:
    cores: 2
    memory: "4g"
  executor:
    cores: 4
    instances: 3
    memory: "8g"
EOF
```

## Configuration Details

### Dockerfile Structure

```dockerfile
FROM public.ecr.aws/spark/spark:3.5.0

# Install additional dependencies
USER root
RUN yum update -y && \
    yum install -y python3-pip && \
    pip3 install pandas numpy boto3 pyarrow

# Security hardening
RUN groupadd -r spark && useradd -r -g spark spark
RUN chown -R spark:spark /opt/spark

# Copy optimized configurations
COPY spark-defaults.conf /opt/spark/conf/
COPY log4j2.properties /opt/spark/conf/

# Set non-root user
USER spark

WORKDIR /opt/spark
```

### Optimized Spark Configuration

```properties
# spark-defaults.conf
spark.serializer                    org.apache.spark.serializer.KryoSerializer
spark.sql.adaptive.enabled          true
spark.sql.adaptive.coalescePartitions.enabled  true
spark.kubernetes.allocation.batch.size          50
spark.kubernetes.allocation.batch.delay         1s
spark.dynamicAllocation.enabled     false
spark.kubernetes.container.image.pullPolicy     Always
```

## Expected Results

✅ **Faster Startup**: Reduced container startup time
✅ **Security**: Non-root execution and minimal attack surface
✅ **Consistency**: Standardized dependencies across deployments
✅ **Optimization**: Pre-tuned configurations for EKS

## Related Blueprints

- [Benchmark Suite Images](/data-on-eks/docs/datastacks/spark-on-eks/benchmark-suite-images)
- [S3 Tables Images](/data-on-eks/docs/datastacks/spark-on-eks/s3tables-images)

## Additional Resources

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Spark Docker Guide](https://spark.apache.org/docs/latest/running-on-kubernetes.html#docker-images)