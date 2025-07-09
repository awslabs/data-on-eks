from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from datetime import datetime

with DAG(
    dag_id="k8s_example_dag04",
    start_date=datetime(2024, 1, 1),
    schedule="0 12 * * *",  # tous les jours à midi
    catchup=False,
) as dag:

    k8s_task = KubernetesPodOperator(
        namespace="airflow",
        image="python:3.9",
        cmds=["python", "-c"],
        arguments=["print('Hello from Kubernetes!')"],
        name="airflow-test-pod",
        task_id="run_k8s_pod",
        is_delete_operator_pod=True,
    )