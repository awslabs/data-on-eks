#!/bin/bash
aws emr-containers start-job-run \
    --virtual-cluster-id z9tnu40nh6jayaob73ua0nad1 \
    --name=pi \
    --execution-role-arn arn:aws:iam::<ACCOUNT_ID>:role/doeks-workshop-emr-eks-data-team-b \
    --release-label emr-6.8.0-latest \
    --job-driver '{
        "sparkSubmitJobDriver":{
                "entryPoint": "local:///usr/lib/spark/examples/src/main/python/pi.py",
                "sparkSubmitParameters": "--conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.executor.cores=2 --conf spark.driver.cores=1"
        }
    }' \
    --configuration-overrides '{
        "monitoringConfiguration": {
            "persistentAppUI": "ENABLED",
            "cloudWatchMonitoringConfiguration": {
                "logGroupName": "/emr-on-eks-logs/doeks-workshop/emr-data-team-b",
                "logStreamNamePrefix": "default"
            }
        }
    }'
