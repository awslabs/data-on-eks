from argparse import ArgumentParser

import ray
from ray.train import ScalingConfig
from ray.train.torch import TorchTrainer
from ray.train.torch.xla import TorchXLAConfig

# Use training function from NxD llama2 example
#   see: https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/neuronx-distributed/tutorials/training_llama2_7b.html#llama2-7b-tp-zero1-tutorial
from tp_zero1_llama2_7b_hf_pretrain import train_llama


# Collect command-line args
def get_args():
    parser = ArgumentParser()

    # Args expected by train_llama()
    parser.add_argument(
        "--model_path",
        type=str,
        default="/llama2_pretrain",
        help="Model weight and config path.",
    )
    parser.add_argument(
        "--data_dir",
        type=str,
        default="/shared/wikicorpus_llama2_7B_tokenized_4k",
        help="Pre-tokenized dataset directory.",
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        default="/shared/llama2_output",
        help="Directory for checkpoints and logs.",
    )
    parser.add_argument(
        "--metrics_file",
        type=str,
        default="results.json",
        help="training metrics results file",
    )
    parser.add_argument("--batch_size", type=int, default=1, help="Worker batch size.")
    parser.add_argument(
        "--max_steps",
        type=int,
        default=10000,
        help="Maximum total accumulation-steps to run.",
    )
    parser.add_argument(
        "--steps_this_run",
        type=int,
        default=10000,
        help="Exit early at <value> steps and not go to max_steps. -1 to mean no early exit.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=12349,
        help="Random seed. Worker seed is this value + worker rank.",
    )
    parser.add_argument("--lr", type=float, default=3e-4, help="Learning rate.")
    parser.add_argument(
        "--warmup_steps",
        type=int,
        default=100,
        help="Number of warmup accumulation-steps for learning rate .",
    )
    # grad_accum_usteps should be set to global_batch_sz / micro_batch_sz / DP_degree
    #   where DP_degree = num_nodes * 32 / TP_degree
    parser.add_argument(
        "--grad_accum_usteps",
        type=int,
        default=32,
        help="Gradient accumulation micro-steps",
    )
    parser.add_argument(
        "--print_grad_norm",
        default=False,
        action="store_true",
        help="Whether to print grad norm",
    )
    parser.add_argument(
        "--resume_ckpt",
        action="store_true",
        help="Resume from checkpoint at resume_step.",
    )
    parser.add_argument(
        "--tensor_parallel_size", default=8, type=int, help="Tensor parallel size"
    )
    parser.add_argument("--seq_len", default=4096, type=int, help="Sequence length")
    parser.add_argument(
        "--use_mix_precision", action="store_true", help="Use mix precision."
    )
    parser.add_argument("--use_zero_1", action="store_true", help="Use ZeRO-1.")
    parser.add_argument(
        "--num_layers",
        type=int,
        default=-1,
        help="Override number of layers for this LLaMA model to num_layers",
    )
    parser.add_argument(
        "--sequence_parallel_enabled",
        type=bool,
        default=True,
        help="Enable/Disable sequence parallel",
    )
    parser.add_argument(
        "--selective_checkpoint_enabled",
        type=bool,
        default=True,
        help="Enable selective checkpoint",
    )
    parser.add_argument(
        "--use_meta_device_init",
        default=False,
        action="store_true",
        help="use meta device initialization",
    )
    parser.add_argument(
        "--logging_interval",
        default=10,
        type=int,
        help="logging every N steps",
    )
    parser.add_argument(
        "--qkv_linear",
        default=False,
        action="store_true",
        help="Whether to use the QKV Module",
    )
    parser.add_argument(
        "--kv_replicator",
        default=1,
        type=int,
        help="KV replication number",
    )
    parser.add_argument(
        "--checkpoint_freq", type=int, default=100000, help="save checkpoint freq"
    )
    parser.add_argument("--checkpoint_dir", type=str, default=None)
    parser.add_argument(
        "--loading_step", type=int, default=-1, help="load from step, -1 means no load"
    )
    parser.add_argument(
        "--num_kept_checkpoint",
        type=int,
        default=-1,
        help="number of checkpoints kept, old checkpoint will get deleted",
    )

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

    return parser.parse_args()


if __name__ == "__main__":
    args = get_args()

    # Set up Neuron-specific env. variables to customize this training job
    env = {
        "NEURON_CC_FLAGS": "--model-type transformer --distribution-strategy=llm-training",
        "NEURON_FUSE_SOFTMAX": "1",
        "NEURON_RT_ASYNC_EXEC_MAX_INFLIGHT_REQUESTS": "3",
        "NEURON_RT_STOCHASTIC_ROUNDING_EN": "1",
        "MALLOC_ARENA_MAX": "64",
        "CCOM_SOCKET_IFNAME": "eth0",
        "NEURON_COMPILE_CACHE_URL": "/shared/neuron_cache",
    }

    if args.use_mix_precision:
        env["XLA_DOWNCAST_BF16"] = "1"
    else:
        env["XLA_USE_BF16"] = "1"

    # Configure runtime env to use Neuron env vars
    ray.init(runtime_env={"env_vars": env})

    # Limit number of steps during neuron parallel compile runs
    if args.neuron_parallel_compile:
        args.steps_this_run = 10

    trainer = TorchTrainer(
        train_loop_per_worker=train_llama,
        train_loop_config=args,
        torch_config=TorchXLAConfig(
            neuron_parallel_compile=args.neuron_parallel_compile
        ),
        scaling_config=ScalingConfig(
            num_workers=args.num_nodes * 32, resources_per_worker={"neuron_cores": 1}
        ),
    )

    trainer.fit()
