# Spark Gluten+Velox Examples

This folder contains simple Gluten+Velox examples for testing and validation.

## Files

### Docker Images
- `Dockerfile-spark-gluten-velox` - Base Spark 3.5.2 image with Gluten v1.4.0 and Velox backend

### Test Applications
- `test-gluten-velox.yaml` - Small-scale Gluten+Velox test job
- `test-native-spark.yaml` - Equivalent native Spark test job for comparison

## Purpose

These examples are designed for:
- ✅ Validating Gluten+Velox installation and configuration
- ✅ Testing JDK17 module compatibility fixes
- ✅ Verifying Velox backend is properly loaded and used
- ✅ Quick performance comparison on small datasets (scale factor 1.0)

## Usage

1. **Build the base Gluten image:**
   ```bash
   docker buildx build --platform linux/amd64 -f Dockerfile-spark-gluten-velox -t <dockerhubuser>/spark-gluten-velox:latest --load .
   docker push <dockerhubuser>/spark-gluten-velox:latest
   ```

2. **Set environment variables:**
   ```bash
   export S3_BUCKET=your-bucket-name
   ```

3. **Deploy test jobs:**
   ```bash
   # Test Gluten+Velox
   envsubst < test-gluten-velox.yaml | kubectl apply -f -

   # Test Native Spark
   envsubst < test-native-spark.yaml | kubectl apply -f -
   ```

4. **Monitor and compare:**
   ```bash
   kubectl get sparkapps -n spark-team-a
   kubectl logs -n spark-team-a -l spark-app-name=test-gluten-velox --tail=50
   ```

## Key Configurations

### Gluten+Velox Setup
```yaml
# Essential Gluten configuration
"spark.plugins": "org.apache.gluten.GlutenPlugin"
"spark.shuffle.manager": "org.apache.spark.shuffle.sort.ColumnarShuffleManager"
"spark.memory.offHeap.enabled": "true"
"spark.memory.offHeap.size": "4g"

# JDK17 compatibility (critical for Velox native libraries)
"spark.driver.extraJavaOptions": "--add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/sun.misc=ALL-UNNAMED ..."
```

### Validation Points
- ✅ Look for `VeloxSparkPlanExecApi.scala` in execution logs
- ✅ Verify `Components: Velox` in driver startup logs
- ✅ Check for vectorized execution in query plans
- ✅ Monitor performance improvements in window functions and aggregations

For comprehensive TPC-DS benchmarking, see the `analytics/terraform/spark-k8s-operator/examples/benchmark/tpcds-benchmark-spark-gluten-velox` folder.
