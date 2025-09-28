---
title: S3 Tables Images
sidebar_position: 14
---

# S3 Tables Images

Specialized Docker images with Apache Iceberg, DuckDB integration, and Jupyter notebook environments for S3 Tables analytics.

## Overview

This blueprint provides Docker images optimized for S3 Tables analytics with Apache Iceberg, DuckDB integration, and interactive Jupyter notebook environments for advanced data analytics.

## Key Features

- **Apache Iceberg**: Full S3 Tables integration
- **DuckDB Engine**: High-performance analytical queries
- **Jupyter Notebooks**: Interactive data exploration
- **Multi-Format Support**: Parquet, Delta, Iceberg tables
- **Visualization Tools**: Built-in plotting and visualization

## Quick Build & Deploy

### 1. Build S3 Tables Image

```bash
cd data-stacks/spark-on-eks/docker

# Build S3 Tables image
docker build -t spark-s3tables:latest -f Dockerfile-S3Table .

# Build Jupyter notebook image
docker build -t jupyter-s3tables:latest -f Dockerfile-S3Table-notebook .
```

### 2. Deploy Jupyter Environment

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jupyter-s3tables
  namespace: spark-team-a
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jupyter-s3tables
  template:
    metadata:
      labels:
        app: jupyter-s3tables
    spec:
      containers:
      - name: jupyter
        image: jupyter-s3tables:latest
        ports:
        - containerPort: 8888
        env:
        - name: S3_TABLES_NAMESPACE
          value: "spark-analytics"
---
apiVersion: v1
kind: Service
metadata:
  name: jupyter-s3tables-svc
  namespace: spark-team-a
spec:
  selector:
    app: jupyter-s3tables
  ports:
  - port: 8888
    targetPort: 8888
EOF
```

### 3. Access Jupyter Interface

```bash
# Port forward to access Jupyter
kubectl port-forward -n spark-team-a svc/jupyter-s3tables-svc 8888:8888

# Open browser to http://localhost:8888
```

## Expected Results

✅ **S3 Tables Integration**: Seamless Iceberg table access
✅ **Interactive Analytics**: Jupyter-based data exploration
✅ **High Performance**: DuckDB analytical engine
✅ **Visualization**: Built-in plotting capabilities

## Related Blueprints

- [S3 Tables](/data-on-eks/docs/datastacks/spark-on-eks/s3tables)
- [Spark Base Images](/data-on-eks/docs/datastacks/spark-on-eks/spark-base-images)

## Additional Resources

- [Apache Iceberg Documentation](https://iceberg.apache.org/docs/latest/)
- [DuckDB Documentation](https://duckdb.org/docs/)
