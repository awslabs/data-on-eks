# Trino on EKS Blueprint

## Introduction

[Trino](https://trino.io/) is an open-source, fast, distributed query engine designed to run SQL queries for big data analytics over multiple data sources including Amazon S3, relational databases, and data warehouses.

This blueprint deploys Trino on Amazon EKS using:
- ArgoCD for GitOps-based deployment
- AWS IAM Roles for Service Accounts (IRSA) for secure AWS service access
- S3 buckets for data storage and query exchange
- AWS Glue for Hive and Iceberg catalog metadata
- KEDA for query-based autoscaling (optional)
- Karpenter for cost-optimized node provisioning

## Prerequisites

1. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://kubernetes.io/docs/tasks/tools/)
3. [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [Trino CLI](https://trino.io/docs/current/client/cli.html)
   ```bash
   wget https://repo1.maven.org/maven2/io/trino/trino-cli/447/trino-cli-447-executable.jar
   mv trino-cli-447-executable.jar trino
   chmod +x trino
   ```

## Deployment

### Quick Start

1. **Run the deployment script**

   ```bash
   cd data-stacks/trino-on-eks
   ./deploy-blueprint.sh
   ```

   The script will:
   - Check prerequisites (terraform, kubectl, aws cli)
   - Copy base infrastructure files to `terraform/_local`
   - Apply blueprint-specific configuration (`blueprint.tfvars`)
   - Deploy VPC and EKS cluster with Trino-specific Karpenter NodePools
   - Install ArgoCD and deploy Trino via GitOps
   - Display ArgoCD and Trino access credentials

2. **Verify deployment**

   The deployment creates these resources:
   - EKS cluster: `trino-v2`
   - Trino namespace with coordinator and worker pods
   - Karpenter NodePools: `trino-control-karpenter` and `trino-sql-karpenter`
   - S3 buckets for data storage and query exchange
   - IAM roles for secure S3 and Glue access

### Manual Deployment

If you prefer manual steps:

```bash
# Copy base infrastructure
mkdir -p terraform/_local
cp -r ../../infra/terraform/* terraform/_local/

# Apply blueprint overrides
tar -C ./terraform --exclude='_local' --exclude='*.tfstate*' --exclude='.terraform' -cf - . | tar -C ./terraform/_local -xf -

# Deploy infrastructure
cd terraform/_local
terraform init
terraform apply -var-file="blueprint.tfvars" -auto-approve

# Update kubeconfig
aws eks update-kubeconfig --name trino-v2 --region us-west-2
```

## Verification

### Check Deployment Status

```bash
# Check ArgoCD applications (should show Trino as "Healthy")
kubectl get applications -n argocd

# Check Trino pods (should show coordinator and worker as "Running")
kubectl get pods -n trino -o wide

# Verify only Trino components deployed (should return 0)
kubectl get pods --all-namespaces | grep -E "(spark|flink|kafka|datahub|jupyter|ray)" | wc -l

# Check Trino-specific Karpenter NodePools
kubectl get nodepools -n karpenter | grep trino
kubectl get ec2nodeclass -n karpenter | grep trino

# Check nodes are using correct NodePools
kubectl get nodes --show-labels | grep -E "(NodePool.*trino|trino.*NodePool)"
```

### Verify Blueprint Configuration

```bash
# Check terraform outputs
cd terraform/_local
terraform output

# Should show:
# - trino_s3_bucket_id
# - trino_exchange_bucket_id
# - trino_irsa_arn
# - cluster_name = "trino-v2"

# Verify S3 buckets exist
aws s3 ls | grep trino-v2

# Verify IAM role
aws iam get-role --role-name $(terraform output -raw trino_irsa_arn | cut -d'/' -f2)
```

### Access ArgoCD UI

```bash
# Port-forward ArgoCD service
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access UI at https://localhost:8080
# Username: admin
# Password: (output from command above)
```

### Access Trino UI

```bash
# Port-forward Trino service
kubectl port-forward -n trino service/trino 8081:8080

# Access UI at http://localhost:8081
# Username: admin (no password required)
```

### Basic Connectivity Test

1. **Download and setup Trino CLI:**
   ```bash
   curl -L https://repo1.maven.org/maven2/io/trino/trino-cli/447/trino-cli-447-executable.jar -o trino
   chmod +x trino
   ```

2. **Test Trino connection:**
   ```bash
   # With port-forward running (from previous step)
   ./trino http://127.0.0.1:8081 --user admin
   ```

3. **Run basic tests:**
   ```sql
   -- Check catalogs are available
   SHOW CATALOGS;

   -- Should see: hive, iceberg, system, tpch, etc.

   -- Test cluster status
   SELECT * FROM system.runtime.nodes;

   -- Test sample data
   SELECT * FROM tpch.tiny.nation LIMIT 5;

   -- Test S3 and Glue integration
   SHOW SCHEMAS FROM hive;
   SHOW SCHEMAS FROM iceberg;
   ```

## Testing

### Example 1: Hive Connector with NYC Taxi Data

This example demonstrates querying data from AWS Glue catalog using Hive connector.

#### Setup Test Data

```bash
cd examples

# Run setup script to create Glue database and load NYC taxi data
./hive-setup.sh
```

The script will:
- Create S3 bucket with sample data
- Create Glue database `taxi_hive_database`
- Run Glue crawler to infer schema
- Create table metadata in Glue

#### Run Queries

```bash
# Connect to Trino (ensure port-forward is running)
./trino http://127.0.0.1:8080 --user admin
```

In Trino CLI, run these queries:

```sql
-- List available catalogs
SHOW CATALOGS;

-- List schemas in Hive catalog
SHOW SCHEMAS FROM hive;

-- Use the taxi database
USE hive.taxi_hive_database;

-- List tables
SHOW TABLES;

-- Query sample data
SELECT * FROM hive LIMIT 10;

-- Aggregation query
SELECT
    passenger_count,
    COUNT(*) as trip_count,
    AVG(trip_distance) as avg_distance,
    AVG(total_amount) as avg_fare
FROM hive
WHERE passenger_count > 0
GROUP BY passenger_count
ORDER BY passenger_count;

-- Time-based analysis
SELECT
    DATE_FORMAT(tpep_pickup_datetime, '%Y-%m') as month,
    COUNT(*) as trips,
    AVG(trip_distance) as avg_distance
FROM hive
GROUP BY DATE_FORMAT(tpep_pickup_datetime, '%Y-%m')
ORDER BY month;
```

#### Cleanup

```bash
# Remove test resources
./hive-cleanup.sh
```

### Example 2: Create and Query Iceberg Tables

The blueprint includes Iceberg connector for modern table format.

```sql
-- Create Iceberg schema
CREATE SCHEMA IF NOT EXISTS iceberg.iceberg_schema
WITH (LOCATION = 's3://<your-bucket>/iceberg/');

-- Create Iceberg table from Hive data
CREATE TABLE iceberg.iceberg_schema.taxi_trips
WITH (
    FORMAT = 'PARQUET',
    partitioning = ARRAY['month(tpep_pickup_datetime)']
)
AS SELECT * FROM hive.taxi_hive_database.hive;

-- Query Iceberg table
SELECT COUNT(*) FROM iceberg.iceberg_schema.taxi_trips;

-- Time travel query (if supported)
SELECT * FROM iceberg.iceberg_schema.taxi_trips
FOR TIMESTAMP AS OF TIMESTAMP '2024-01-01 00:00:00'
LIMIT 10;
```

### Example 3: TPC-DS Benchmark Queries

Trino includes built-in TPC-DS connector for testing:

```sql
-- Use TPC-DS catalog
USE tpcds.sf1;

-- Show available tables
SHOW TABLES;

-- Run sample TPC-DS query
SELECT
    i_item_id,
    AVG(ss_quantity) avg_sales,
    AVG(ss_list_price) avg_list_price,
    AVG(ss_coupon_amt) avg_coupon,
    AVG(ss_sales_price) avg_sales_price
FROM store_sales, item, date_dim
WHERE ss_item_sk = i_item_sk
    AND ss_sold_date_sk = d_date_sk
    AND d_year = 2000
GROUP BY i_item_id
ORDER BY i_item_id
LIMIT 100;
```

## Monitoring

### Check KEDA Autoscaling

```bash
# View ScaledObject
kubectl get scaledobject -n trino

# View HPA created by KEDA
kubectl get hpa -n trino

# Watch worker scaling
kubectl get pods -n trino -w
```

### Prometheus Metrics

```bash
# Check ServiceMonitor
kubectl get servicemonitor -n trino

# Sample metrics available:
# - trino_execution_QueryManager_QueuedQueries
# - trino_execution_QueryManager_RunningQueries
# - trino_memory_ClusterMemoryManager
```

## Troubleshooting

### Common Issues

1. **Workers not starting**
   ```bash
   # Check worker logs
   kubectl logs -n trino statefulset/trino-worker

   # Check node availability
   kubectl get nodes
   ```

2. **S3 Access Denied**
   ```bash
   # Verify IRSA configuration
   kubectl describe sa trino-sa -n trino

   # Check IAM role
   terraform output trino_irsa_arn
   ```

3. **Glue Catalog Errors**
   ```bash
   # Verify Glue permissions in IRSA role
   aws iam get-role-policy --role-name <irsa-role-name> --policy-name <policy-name>

   # Check Glue database exists
   aws glue get-database --name taxi_hive_database
   ```

4. **Query Failures**
   ```bash
   # Check coordinator logs
   kubectl logs -n trino deployment/trino-coordinator

   # Increase memory if needed
   # Edit infra/terraform/helm-values/trino.yaml
   ```

## Cleanup

```bash
# Clean up example data
cd examples
./hive-cleanup.sh

# Destroy all resources
cd ../../infra/terraform
terraform destroy -auto-approve
```

## Configuration

### Customize Trino Settings

Edit `infra/terraform/helm-values/trino.yaml`:
- Worker count and resources
- JVM heap sizes
- Query memory limits
- Additional catalogs

### Add Custom Catalogs

Add to `additionalCatalogs` in helm-values:
```yaml
additionalCatalogs:
  postgres: |-
    connector.name=postgresql
    connection-url=jdbc:postgresql://postgres:5432/mydb
    connection-user=user
    connection-password=pass
```

## Resources

- [Trino Documentation](https://trino.io/docs/current/)
- [Trino Helm Chart](https://github.com/trinodb/charts)
- [AWS Glue Documentation](https://docs.aws.amazon.com/glue/)
- [KEDA Documentation](https://keda.sh/)
- [Data on EKS](https://github.com/awslabs/data-on-eks)
