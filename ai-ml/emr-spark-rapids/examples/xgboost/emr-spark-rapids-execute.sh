{
    "name": "gpu-ubuntu",
    "virtualClusterId": "o87g6rzxs9c11sfc4x15l2cg7",
    "executionRoleArn": "arn:aws:iam::228924278364:role/emr-eks-job-execution-ROLE",
    "releaseLabel": "emr-6.10.0-spark-rapids-latest",
    "jobDriver": {
      "sparkSubmitJobDriver": {
        "entryPoint": "s3://emrserverless-workshop-228924278364/scripts/nvidia/etl-xgboost-train-transform.py",
        "entryPointArguments": [],
         "sparkSubmitParameters": "--conf spark.kubernetes.container.image=228924278364.dkr.ecr.us-east-1.amazonaws.com/emr-6.10.0-spark-rapids:0.11 --jars=s3://emrserverless-workshop-228924278364/nvidia/xgboost4j-spark_3.0-1.4.2-0.3.0.jar,s3://emrserverless-workshop-228924278364/nvidia/xgboost4j_3.0-1.4.2-0.3.0.jar --conf spark.pyspark.python=/opt/venv/bin/python"
      }
    },
    "configurationOverrides": {
      "applicationConfiguration": [
        {
          "classification": "spark-defaults",
          "properties": {
            "spark.plugins": "com.nvidia.spark.SQLPlugin",
            "spark.executor.extraLibraryPath": "/usr/local/cuda/lib:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:/usr/local/cuda/targets/x86_64-linux/lib:/usr/lib/hadoop/lib/native:/usr/lib/hadooplzo/lib/native:/docker/usr/lib/hadoop/lib/native:/docker/usr/lib/hadoop-lzo/lib/native",
            "spark.executor.instances": "8",
            "spark.executor.cores": "5",
            "spark.executor.memory": "26G",
            "spark.driver.cores": "2",
            "spark.driver.memory": "8G",
            "spark.rapids.shuffle.mode": "MULTITHREADED",
            "spark.rapids.sql.concurrentGpuTasks": "1",
            "spark.rapids.sql.explain":"ALL",
            "spark.rapids.sql.concurrentGpuTasks":"1",
            "spark.rapids.memory.pinnedPool.size":"1G",
            "spark.rapids.memory.gpu.pool":"ASYNC",
            "spark.rapids.memory.gpu.allocFraction":"0.6",
            "spark.rapids.sql.incompatibleOps.enabled": "true",
            "spark.rapids.sql.enabled":"true",
            "spark.rapids.sql.batchSizeBytes": "1gb",
            "spark.executor.resource.gpu.amount": "1",
            "spark.task.cpus":"1",
            "spark.task.resource.gpu.amount": "1",
            "spark.sql.files.maxPartitionBytes": "2gb",
            "spark.driver.maxResultSize": "2gb",
            "spark.sql.adaptive.enabled": "true",
            "spark.executor.memoryOverhead": "2G",
            "spark.locality.wait": "0s",
            "spark.dynamicAllocation.enabled": "false",
            "spark.shuffle.manager": "com.nvidia.spark.rapids.spark331.RapidsShuffleManager",
            "spark.sql.sources.useV1SourceList": "parquet",
            "spark.executor.resource.gpu.vendor": "nvidia.com",
            "spark.eventLog.enabled": "true",
            "spark.eventLog.compress": "true",
            "spark.eventLog.dir": "s3://emrserverless-workshop-228924278364/logs/emr-eks/logs/gpu/",
            "spark.kubernetes.executor.podTemplateFile": "s3://emrserverless-workshop-228924278364/nvidia/pod-templates/pod-template-executor-ubuntu-gpu-node-group.yaml",
            "spark.kubernetes.driver.podTemplateFile": "s3://emrserverless-workshop-228924278364/nvidia/pod-templates/pod-template-driver-ubuntu-gpu-node-group.yaml",
            "spark.local.dir": "/pv-disks/spark",
            "spark.kubernetes.executor.volumes.hostPath.spark-local-dir-1.mount.path": "/pv-disks/spark",
            "spark.kubernetes.executor.volumes.hostPath.spark-local-dir-1.options.path": "/pv-disks/local1"
           }
        }
      ],
      "monitoringConfiguration": {
        "persistentAppUI": "ENABLED",
        "cloudWatchMonitoringConfiguration": {
          "logGroupName": "emr-eks-spark-gpu"
        },
        "s3MonitoringConfiguration": {
          "logUri": "s3://emrserverless-workshop-228924278364/logs/emr-eks/logs/gpu/spark/"
        }
      }
    }
  }
