from airflow import DAG
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.operators.python import PythonOperator
import datetime
import time

def print_hello():
    print("Hello from Python!")


def sleep(duration: int):
    print("Sleeping!")
    time.sleep(duration)

with DAG(
    dag_id='simple_example_dag',
    start_date=datetime.datetime.now(),
    catchup=False,
    tags=["example", "data-on-eks"],
) as dag:
    start_task = BashOperator(
        task_id='start_message',
        bash_command='echo "Starting the DAG!"'
    )

    python_task = PythonOperator(
        task_id='run_python_function',
        python_callable=print_hello
    )

    python_task_sleep = PythonOperator(
        task_id='sleep',
        python_callable=sleep,
        op_kwargs={'duration': 30}
    )

    end_task = BashOperator(
        task_id='end_message',
        bash_command='echo "DAG finished!"'
    )

    start_task >> python_task >> python_task_sleep >> end_task
