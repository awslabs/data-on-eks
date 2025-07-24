from airflow.providers.cncf.kubernetes.operators.spark_kubernetes import SparkKubernetesOperator

spark_submit = SparkKubernetesOperator(
    task_id='spark_submit_job',
    namespace='spark-team-a',
    application_file='pyspark-pi-job_rendered_1753122826.yaml',
    kubernetes_conn_id='kubernetes_default',
    do_xcom_push=True,
)