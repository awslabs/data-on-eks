# coding=utf-8
# Copyright (c) 2019 NVIDIA CORPORATION. All rights reserved.
# Copyright 2018 The Google AI Language Team Authors and The HuggingFace Inc. team.
# Modifications Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import os
import sys

current = os.path.dirname(os.path.realpath(__file__))
parent = os.path.dirname(current)
sys.path.append(parent)

import torch
import torch.distributed as dist
import torch_xla.core.xla_model as xm
from data_module import NeuronLightningDataModule
from modeling_llama_nxd import (
    CoreAttention,
    LlamaDecoderLayer,
    LlamaForCausalLM,
    LlamaRMSNorm,
    init_weights,
)
from module_llama import NeuronLlamaLTModule
from pytorch_lightning import Trainer
from pytorch_lightning.callbacks import ModelCheckpoint
from training_utils import (
    create_llama_pretraining_dataset,
    get_learning_rate_scheduler,
    get_mixed_precision_config,
    get_param_groups_by_weight_decay,
    get_sin_cos_matrix,
)
from transformers import LlamaConfig, set_seed
from transformers.optimization import get_linear_schedule_with_warmup
from ray_lt_neuron_xla_strategy import RayLightningNeuronXlaStrategy

import neuronx_distributed as nxd
from neuronx_distributed.lightning import (
    NeuronTensorBoardLogger,
    NeuronTQDMProgressBar,
    NeuronXLAPrecisionPlugin,
    NeuronXLAStrategy,
)
from neuronx_distributed.parallel_layers import mappings
from neuronx_distributed.utils.adamw_fp32_optim_params import AdamW_FP32OptimParams

# For PT autocast.
torch.cuda.is_bf16_supported = lambda: True

# Workaround for NaNs seen with transformers version >= 4.21.0
# https://github.com/aws-neuron/aws-neuron-sdk/issues/593
import transformers.modeling_utils as modeling_utils

if os.environ.get("XLA_USE_BF16") or os.environ.get("XLA_DOWNCAST_BF16"):
    modeling_utils.get_parameter_dtype = lambda x: torch.bfloat16

# adding ray modules
import ray
from ray.train import ScalingConfig
from ray.train.torch import TorchTrainer
from ray.train.torch.xla import TorchXLAConfig

def train_llama(args):
    print(f"Namespace: {args}")
    set_seed(args.seed)

    if args.steps_this_run < 0:
        args.steps_this_run = args.max_steps

    pipeline_config = None

    model_config = LlamaConfig.from_pretrained(args.model_path)
    model_config.use_cache = False
    if args.pipeline_parallel_size > 1:
        model_config.return_dict = False
    model_config.sequence_parallel_enabled = args.use_sequence_parallel > 0
    model_config.kv_shared_group_size = args.kv_replicator
    model_config.qkv_linear = args.qkv_linear
    model_config.selective_checkpoint_enabled = args.use_selective_checkpoint > 0
    model_config.max_position_embeddings = max(model_config.max_position_embeddings, args.seq_len)
    model_config.use_flash_attention = args.use_flash_attention > 0
    if args.pretrained_weight is not None:
        model_config.pretrained_ckpt = args.pretrained_weight
    if args.num_layers > 0:
        model_config.num_hidden_layers = args.num_layers
    if args.hidden_size != -1:
        model_config.hidden_size = args.hidden_size
    xm.master_print(model_config)

    pipeline_config = None
    if args.pipeline_parallel_size > 1:
        pipeline_config = {
            "transformer_layer_cls": LlamaDecoderLayer,
            "num_microbatches": args.num_microbatches,
            "output_loss_value_spec": (True, False),
            "input_names": ["input_ids", "attention_mask", "labels"],
            "auto_partition": True,
            "deallocate_pipeline_outputs": args.deallocate_pipeline_outputs > 0,
            "trace_file_path": args.trace_file_path,
            "param_init_fn": None,
            "leaf_module_cls": [LlamaRMSNorm.__name__],
            "autowrap_modules": [mappings],
            "use_zero1_optimizer": args.use_zero1_optimizer > 0,
            "use_optimizer_wrapper": True,
            "broadcast_and_average_loss": args.log_rank0 > 0,
            "fuse_microbatches": args.fuse_microbatches > 0,
        }

    # Create model with different options
    # Either deferred_init or meta device initialization will be required to avoid host OOM for 70B model
    if args.use_meta_device_init > 0:
        model_init_config = {
            "meta_device_init": True,
            "param_init_fn": init_weights,
        }
    else:
        model_init_config = None

    mixed_precision_config = get_mixed_precision_config(args.use_gpu_compatible_precision > 0)

    nxd_config = nxd.neuronx_distributed_config(
        tensor_parallel_size=args.tensor_parallel_size,
        pipeline_parallel_size=args.pipeline_parallel_size,
        pipeline_config=pipeline_config,
        optimizer_config={
            "zero_one_enabled": args.use_zero1_optimizer > 0,
            "grad_clipping": True,
            "max_grad_norm": 1.0,
        },
        sequence_parallel=args.use_sequence_parallel > 0,
        activation_checkpoint_config=CoreAttention if args.use_selective_checkpoint > 0 else "full",
        model_init_config=model_init_config,
        mixed_precision_config=mixed_precision_config,
    )

    opt_cls = AdamW_FP32OptimParams if args.use_fp32_optimizer > 0 else torch.optim.AdamW

    def configure_scheduler(optimizer, warmup_steps, max_steps):  # PTLTODO: check loading scheduler state dict here
        return get_linear_schedule_with_warmup(
            optimizer,
            num_warmup_steps=warmup_steps,
            num_training_steps=max_steps,
            last_epoch=-1,
        )

    scheduler_cls = None
    scheduler_args = ()

    if args.scheduler_type == "linear":
        scheduler_cls = configure_scheduler
        scheduler_args = (args.warmup_steps, args.max_steps)
    elif args.scheduler_type == "cosine":
        scheduler_cls = get_learning_rate_scheduler
        scheduler_args = (args,)
    else:
        raise ValueError(f"Currently We only support scheduler type 'linear' and 'cosine', got {args.scheduler_type}")

    model = NeuronLlamaLTModule(
        nxd_config=nxd_config,
        model_args=(model_config,),
        opt_cls=opt_cls,
        scheduler_cls=scheduler_cls,
        opt_kwargs={
            "lr": args.lr,
            "betas": (args.beta1, args.beta2),
            "weight_decay": args.weight_decay,
            # "capturable": True,
        },
        scheduler_args=scheduler_args,
        train_batch_size=args.train_batch_size,
        grad_accum_steps=args.grad_accum_usteps,
        logging_interval=args.logging_interval,
        log_rank0=args.log_rank0 > 0,
        manual_opt=True,
        use_deferred_init=args.use_deferred_init,
    )

    dm = NeuronLightningDataModule(
        create_llama_pretraining_dataset,
        args.data_dir,
        args.train_batch_size,
        data_args=(args.seed,),
    )

    strategy_cls = RayLightningNeuronXlaStrategy
    strategy = strategy_cls(
        nxd_config=nxd_config,
        save_load_xser=args.save_load_xser,
    )

    plugins = []

    plugins.append(NeuronXLAPrecisionPlugin())

    callbacks = []
    callbacks.append(NeuronTQDMProgressBar())
    if args.save_checkpoint:
        callbacks.append(
            ModelCheckpoint(
                save_top_k=args.num_kept_checkpoint,
                monitor="global_step",
                mode="max",
                every_n_epochs=args.checkpoint_freq,
                dirpath=args.checkpoint_dir,
            )
        )
    if args.steps_this_run == 2:
        trainer = Trainer(
            strategy=strategy,
            max_steps=args.steps_this_run,
            plugins=plugins,
            enable_checkpointing=args.save_checkpoint,
            logger=NeuronTensorBoardLogger(save_dir=args.tb_dir, log_rank0=args.log_rank0 > 0),
            log_every_n_steps=1,
            callbacks=callbacks,
        )
    else:
        trainer = Trainer(
            strategy=strategy,
            max_epochs=args.num_train_epochs,
            plugins=plugins,
            enable_checkpointing=args.save_checkpoint,
            logger=NeuronTensorBoardLogger(save_dir=args.tb_dir, log_rank0=args.log_rank0 > 0),
            log_every_n_steps=1,
            callbacks=callbacks,
        )

    if args.resume_ckpt:
        ckpt_path = os.path.join(
            args.checkpoint_dir,
            f"epoch={args.load_epoch}-step={args.load_step}.ckpt",
        )
        print(f"resume path is {ckpt_path}")
        trainer.fit(model=model, datamodule=dm, ckpt_path=ckpt_path)
    else:
        trainer.fit(model=model, datamodule=dm)

    print("Training finished!")


def _mp_fn(index, args):
    # PK:Ray Changes start
    print (f"_mp_fn.Trace: {dist.is_torchelastic_launched()=}")
    print (f"_mp_fn.Trace: {os.environ.get('WORLD_SIZE')=}")

    # setup_env_vars()

    if not dist.is_torchelastic_launched():
        scaling_config = ScalingConfig(num_workers=32, resources_per_worker={"neuron_cores": 1})
        args.use_ray = True
        trainer = TorchTrainer(
            train_loop_per_worker=lambda: train_llama(args),
            torch_config=TorchXLAConfig(),
            scaling_config=scaling_config
        )
        result = trainer.fit()
        print (f"Training finished with {result=}")
    else:
        args.use_ray = False
        train_llama(args)
    #train_llama(args)

def build_args() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model_path",
        type=str,
        help="Model weight and config path.",
    )
    parser.add_argument(
        "--data_dir",
        type=str,
        help="Pre-tokenized dataset directory.",
    )
    parser.add_argument("--train_batch_size", type=int, default=8, help="Worker batch size.")
    parser.add_argument(
        "--max_steps",
        type=int,
        default=-1,
        help="Maximum total accumulation-steps to run.",
    )
    parser.add_argument(
        "--steps_this_run",
        type=int,
        default=-1,
        help="Exit early at <value> steps and not go to max_steps. -1 to mean no early exit.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=12349,
        help="Random seed. Worker seed is this value + worker rank.",
    )
    parser.add_argument("--lr", type=float, default=4e-4, help="Learning rate.")
    parser.add_argument(
        "--warmup_steps",
        type=int,
        default=2000,
        help="Number of warmup accumulation-steps for learning rate .",
    )
    parser.add_argument(
        "--constant_steps",
        type=int,
        default=None,
        help="Number of constant_steps for learning rate .",
    )
    parser.add_argument(
        "--min_lr",
        type=float,
        default=None,
        help="Minumum value for learning rate. The scheduler" "clip values below this threshold.",
    )
    parser.add_argument(
        "--scheduler_type",
        type=str,
        default=None,
        help="Type of lr scheduler",
    )
    parser.add_argument(
        "--grad_accum_usteps",
        type=int,
        default=1,
        help="Gradient accumulation micro-steps (an accumulation-step has <value> micro-steps.",
    )

    parser.add_argument("--weight_decay", default=0.01, type=float, help="weight decay")
    parser.add_argument("--beta1", default=0.9, type=float, help="beta1 parameter for Adam optimizer")
    parser.add_argument("--beta2", default=0.999, type=float, help="beta2 parameter for Adam optimizer")

    parser.add_argument("--load_step", type=int, default=0, help="step to load checkpoint from")
    parser.add_argument("--load_epoch", type=int, default=0, help="epoch to load checkpoint from")
    parser.add_argument("--tb_dir", type=str, default="/shared/tblogs", help="Directory for log files")
    #parser.add_argument("--log_dir", type=str, default=os.getcwd() + "/llama8B-logs", help="Directory for log files")
    parser.add_argument("--save_checkpoint", action="store_true", help="Save checkpoints")
    parser.add_argument(
        "--num_kept_checkpoint",
        type=int,
        default=10000,
        help="number of checkpoints kept, old checkpoint will get deleted",
    )
    parser.add_argument("--pretrained_weight", type=str, default=None, help="Load dir of pretrained weight")
    parser.add_argument("--checkpoint_freq", type=int, default=10000, help="save checkpoint freq")
    parser.add_argument("--checkpoint_dir", type=str, default=None)
    parser.add_argument("--resume_ckpt", action="store_true", help="Resume from checkpoint at resume_step.")
    parser.add_argument("--save_load_xser", action="store_true", help="save/load with xla serialization")

    parser.add_argument("--tensor_parallel_size", default=2, type=int, help="Tensor parallel size")
    parser.add_argument("--pipeline_parallel_size", default=1, type=int, help="Pipeline parallel size")
    parser.add_argument("--num_microbatches", type=int, default=8, help="num_microbatches")
    parser.add_argument("--seq_len", default=4096, type=int, help="Sequence length")
    parser.add_argument("--trace_file_path", type=str, default=None)
    parser.add_argument("--use_fp32_optimizer", type=int, default=0, help="Use fp32 optimizer.")
    parser.add_argument("--use_zero1_optimizer", type=int, default=0, help="Use ZeRO-1.")
    parser.add_argument("--use_deferred_init", default=0, type=int, help="use torchdistx deferred initialization")
    parser.add_argument("--use_meta_device_init", default=0, type=int, help="use meta device initialization")
    parser.add_argument(
        "--deallocate_pipeline_outputs",
        type=int,
        default=1,
        help="deallocate pipeline output tensors whenever possible",
    )

    parser.add_argument("--logging_interval", type=int, default=1, help="number of warmup_steps")
    parser.add_argument("--log_rank0", type=int, default=0, help="logging in rank 0, note that the issue ")

    parser.add_argument(
        "--num_layers",
        type=int,
        default=-1,
        help="Override number of layers for this LLaMA model",
    )
    parser.add_argument(
        "--hidden_size",
        type=int,
        default=-1,
        help="override model model hidden size",
    )
    parser.add_argument(
        "--use_sequence_parallel",
        default=1,
        type=int,
        help="Enable sequence parallel",
    )
    parser.add_argument(
        "--use_selective_checkpoint",
        default=0,
        type=int,
        help="Enable selective checkpoint",
    )
    parser.add_argument(
        "--qkv_linear",
        default=0,
        type=int,
        help="Use QKV Linear module",
    )
    parser.add_argument(
        "--kv_replicator",
        default=1,
        type=int,
        help="KV replication number",
    )
    parser.add_argument(
        "--use_flash_attention",
        default=0,
        type=int,
        help="Use neuron kernel",
    )
    parser.add_argument(
        "--use_gpu_compatible_precision",
        default=1,
        type=int,
        help="Use gpu compatible precision",
    )
    parser.add_argument(
        "--fuse_microbatches",
        type=int,
        default=0,
        help="Fuse microbatches into a single graph"
    )
    parser.add_argument(
        "--num_train_epochs",
        type=int,
        default=1,
        help="Maximum numer of epochs to run.",
    )

    return parser

if __name__ == "__main__":
    parser = build_args()
    args = parser.parse_args(sys.argv[1:])

    if args.steps_this_run < 0:
        args.steps_this_run = args.max_steps

    os.environ["NEURON_RT_STOCHASTIC_ROUNDING_EN"] = "0" if args.use_gpu_compatible_precision > 0 else "1"
    if args.use_fp32_optimizer:
        os.environ["XLA_DOWNCAST_BF16"] = "1"
    else:
        os.environ["XLA_USE_BF16"] = "1"

    # WORLD_SIZE is set by torchrun

    _mp_fn(0, args)
