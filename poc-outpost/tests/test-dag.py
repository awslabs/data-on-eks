from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

def ma_tache():
    print("Hello Airflow!")

with DAG(
    dag_id="exemple_dag",
    start_date=datetime(2024, 1, 1),
    schedule="0 12 * * *",  # tous les jours à midi
    catchup=False,
    tags=["exemple"],
) as dag:
    tache = PythonOperator(
        task_id="dire_bonjour",
        python_callable=ma_tache,
    )