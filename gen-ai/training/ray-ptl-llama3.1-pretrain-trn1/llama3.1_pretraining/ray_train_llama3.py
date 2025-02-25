from argparse import ArgumentParser

import ray
from ray.train import ScalingConfig
from ray.train.torch import TorchTrainer
# from ray.train.torch.xla import TorchXLAConfig
from ray_neuron_xla_config_20 import NewTorchXLAConfig as TorchXLAConfig

# Use training function from NxD llama2 example
#   see: https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/neuronx-distributed/tutorials/training_llama2_7b.html#llama2-7b-tp-zero1-tutorial
from run_llama_nxd_ptl import train_llama, build_args as build_model_args
import os
import os

# Collect command-line args
def add_args(parser: ArgumentParser) -> None:
    # Additional args added for this Ray Train example
    parser.add_argument(
        "--neuron_parallel_compile",
        action="store_true",
        default=False,
        help="Enable Neuron parallel compilation to pre-populate the Neuron cache",
    )
    parser.add_argument(
        "--num_nodes",
        type=int,
        default=2,
        help="Number of trn1 nodes to use for training",
    )

def get_args():
    parser = build_model_args()
    add_args(parser)
    return parser.parse_args()

if __name__ == "__main__":
    args = get_args()
    args.use_ray = True

    num_cores_per_node = 32
    num_workers = args.num_nodes * num_cores_per_node
    num_cores_per_node_env_value = str(num_cores_per_node)
    num_workers_env_value = str(num_workers)

    # Set up Neuron-specific env. variables to customize this training job
    env = {
        "NEURON_CC_FLAGS": "--model-type transformer --distribution-strategy=llm-training",
        "NEURON_FUSE_SOFTMAX": "1",
        "NEURON_RT_ASYNC_EXEC_MAX_INFLIGHT_REQUESTS": "16",
        "NEURON_RT_STOCHASTIC_ROUNDING_EN": "1",
        "MALLOC_ARENA_MAX": "64",
        "CCOM_SOCKET_IFNAME": "eth0",
        "NEURON_COMPILE_CACHE_URL": "/shared/neuron_compile_cache/",
        # These were usually set inside a slurm script, I don't yet know the significance or relevance/need of these variables
        "NUM_NEURONCORES":num_cores_per_node_env_value,
        "NEURON_RT_NUM_CORES":num_cores_per_node_env_value,
        "TPU_NUM_DEVICES":num_cores_per_node_env_value,
        "TPU_CHIPS_PER_HOST_BOUNDS":num_cores_per_node_env_value,
        # These were needed for Ray Train to work on pytorch 2+.
        "NEURON_PJRT_WORLD_SIZE":num_workers_env_value,
        "PJRT_LOCAL_PROCESS_COUNT": num_cores_per_node_env_value
    }

    if args.use_fp32_optimizer:
        env["XLA_DOWNCAST_BF16"] = "1"
    else:
        env["XLA_USE_BF16"] = "1"

    # Configure runtime env to use Neuron env vars
    ray.init(runtime_env={"env_vars": env})

    # Limit number of steps during neuron parallel compile runs
    if args.neuron_parallel_compile:
        args.steps_this_run = 2

    trainer = TorchTrainer(
        train_loop_per_worker=train_llama,
        train_loop_config=args,
        torch_config=TorchXLAConfig(
            neuron_parallel_compile=args.neuron_parallel_compile
        ),
        scaling_config=ScalingConfig(
            num_workers=num_workers, resources_per_worker={"neuron_cores": 1}
        ),
    )

    trainer.fit()
