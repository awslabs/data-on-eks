from datetime import datetime, timedelta, timezone
from airflow import DAG
from airflow.exceptions import AirflowException
from airflow.utils import yaml
import os
from airflow.providers.cncf.kubernetes.operators.spark_kubernetes import SparkKubernetesOperator
from airflow.providers.cncf.kubernetes.sensors.spark_kubernetes import SparkKubernetesSensor

with DAG(  
    dag_id="spark_pi",
    start_date=datetime(2025, 10, 24),
    description="submit spark-pi as sparkApplication on kubernetes",
    catchup=False,
    dagrun_timeout=timedelta(minutes=10),
    schedule=timedelta(days=1),
    tags=["example", "data-on-eks"],
) as dag:
    t1 = SparkKubernetesOperator(  
        task_id="pyspark_pi_submit",
        namespace="spark-team-a",
        application_file="spark-pi.yaml",
        dag=dag,
        get_logs=False,
    )
    # xcom in SparkKubernetesOperator is broken as of 3.1.0: https://github.com/apache/airflow/pull/52051
    # t2 = SparkKubernetesSensor(
    #     task_id="pyspark_pi_monitor",
    #     namespace="spark-team-a",
    #     application_name="{{ task_instance.xcom_pull(task_ids='pyspark_pi_submit')['metadata']['name'] }}",
    #     dag=dag,
    # )

    t1
