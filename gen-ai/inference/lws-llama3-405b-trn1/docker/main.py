from vllm.worker.neuron_worker import Worker
# Internal Amazon implementation; This will be changed to Open AI API entrypoint 
from vllm.entrypoints.bedrock import api_server
import os

def main():
    rank_id = int(os.getenv("NEURON_RANK_ID", "0"))
    if rank_id == 0:
        master()
    else:
        main_worker()


def master():
    args, engine, engine_args = api_server.initialize_worker()
    api_server.run_master(args, engine, engine_args)
    # call asyn llm engine


def main_worker():
    args, engine, engine_args = api_server.initialize_worker()
    worker = engine.engine.model_executor.driver_worker
    while True:
        worker.execute_model()


if "__main__" == __name__:
    main()