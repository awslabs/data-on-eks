# coding=utf-8
# Copyright (c) 2019 NVIDIA CORPORATION. All rights reserved.
# Copyright 2018 The Google AI Language Team Authors and The HugginFace Inc. team.
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

import os
import math
import torch
import sys
import time
import argparse
import json
import queue
from typing import Any, Dict, List
from datetime import datetime, timezone
from collections import namedtuple
import torch_xla
import torch_xla.core.xla_model as xm
from torch.utils.data.dataloader import DataLoader
from torch.utils.data import DistributedSampler
import torch_xla.distributed.parallel_loader as pl
import torch.distributed as dist
import torch_xla.distributed.xla_multiprocessing as xmp
import torch_xla.distributed.xla_backend
import numpy as np
from transformers import (
    AdamW,
    default_data_collator,
    set_seed,
    LlamaConfig,
)
from transformers.optimization import get_linear_schedule_with_warmup

import copy
from torch.utils.tensorboard import SummaryWriter
import inspect
import requests

import neuronx_distributed as nxd
from neuronx_distributed.parallel_layers import parallel_state, layers, grads, checkpointing
from neuronx_distributed.utils.model_utils import move_model_to_device
from neuronx_distributed.parallel_layers.grads import bucket_allreduce_gradients
from neuronx_distributed.parallel_layers.utils import is_pjrt_device
import datasets

from neuronx_distributed.optimizer import NeuronZero1Optimizer
from neuronx_distributed.utils.adamw_fp32_optim_params import AdamW_FP32OptimParams

from modeling_llama_nxd import CoreAttention,LlamaForCausalLM
from logger import Logger

# For PT autocast.
torch.cuda.is_bf16_supported = lambda: True

# Workaround for NaNs seen with transformers version >= 4.21.0
# https://github.com/aws-neuron/aws-neuron-sdk/issues/593
import transformers.modeling_utils as modeling_utils

if os.environ.get("XLA_USE_BF16") or os.environ.get("XLA_DOWNCAST_BF16"):
    modeling_utils.get_parameter_dtype = lambda x: torch.bfloat16

datetime_str = str(datetime.now())
results = {
    "inference_success": 1
}


Metric = namedtuple("Metric", ["name", "value", "units", "additional_data"])


class TrainingMetrics:
    """
    This class is used for logging metrics to a json file. One can provide a 
    dictionary of metrics that needs to be stored, and it wpuld get 
    written to the file.
    Arguments:
        json_file: File used for logging. If no file exists, new file would be created.
    """
    def __init__(self, json_file):
        self.json_file = json_file

    def read_modify_write_file(self, data, key: str = "metrics") -> None:
        """
        data (dict of training parameters or list of metrics): Data to update in the file.
        key (str): the dictionary key under which data is to be recorded
        """
        result_dict = {}
        print(f"Writing data to the provided results file: {self.json_file}")
        if os.path.exists(self.json_file):
            with open(self.json_file) as json_file:
                result_dict = json.loads(json_file.read()) or result_dict
        print(f"Updating with {key} data: {data}")
        if result_dict:
            try:
                # handle internal named entity if present
                results = result_dict[next(iter(result_dict))]
            except Exception:
                results = result_dict
            current = results.get(key)
            if not current:
                results[key] = data
            else:
                if isinstance(current, list):
                    current.extend(data)
                elif isinstance(current, dict):
                    current.update(data)
        else:
            result_dict["results"] = {key: data}
        with open(self.json_file, "w") as json_file:
            json.dump(result_dict, json_file)

    def store_metrics(self, metrics: List[Metric]) -> None:
        """
        Writes collected metrics to the file.
        """
        data = [
            {
                "MetricName": metric.name,
                "MeasuredValue": metric.value,
                "Units": metric.units,
                "Timestamp": datetime.now(timezone.utc).isoformat(),
                "AdditionalData": metric.additional_data,
            }
            for metric in metrics
        ]
        self.update(data=data, key="metrics")

    def store_parameters(self, parameters: Dict[str, Any]) -> None:
        """
        Writes specified model and configuration parameters to the file.
        """
        self.update(data=parameters, key="parameters")

    def update(self, **kwargs: Any) -> None:
        """
        Write specified data to the output file.
        """
        self.read_modify_write_file(**kwargs)


class Throughput:
    """
    Used to calculate the throughput over a moving window. It records the step time
    between two calls and uses that time to calculate the throughput.
    """
    def __init__(
        self, batch_size, world_size, grad_accum_usteps, moving_avg_window_size=10, logging_interval=1
    ):
        self.seqs_per_iteration = batch_size * world_size * grad_accum_usteps*logging_interval
        self.moving_avg_window_size = math.ceil(moving_avg_window_size/logging_interval)
        self.moving_avg_window = queue.Queue()
        self.window_time = 0
        self.start_time = time.time()

    def get_throughput(self):
        step_time = time.time() - self.start_time
        self.start_time += step_time
        self.window_time += step_time
        self.moving_avg_window.put(step_time)
        window_size = self.moving_avg_window.qsize()
        if window_size > self.moving_avg_window_size:
            self.window_time -= self.moving_avg_window.get()
            window_size -= 1
        throughput = window_size * self.seqs_per_iteration / self.window_time
        return throughput


# Workaround because python functions are not picklable
class WorkerInitObj(object):
    def __init__(self, seed):
        self.seed = seed

    def __call__(self, id):
        set_seed(self.seed)

def create_pretraining_dataset(
    data_dir, mini_batch_size, worker_init
):
    train_data = datasets.load_from_disk(os.path.expanduser(data_dir))
    train_sampler = DistributedSampler(
        train_data,
        num_replicas=parallel_state.get_data_parallel_size(),
        rank=parallel_state.get_data_parallel_rank(),
        shuffle=False,
        drop_last=True,
    )
    train_dataloader = DataLoader(
        train_data,
        collate_fn=default_data_collator,
        sampler=train_sampler,
        batch_size=mini_batch_size,
        num_workers=0,
        worker_init_fn=worker_init,
        drop_last=True,
        pin_memory=True,
    )
    return train_dataloader

def get_model(flags):
    model_path, seq_len = flags.model_path, flags.seq_len
    config = LlamaConfig.from_pretrained(model_path)
    config.use_cache = False
    config.kv_shared_group_size = flags.kv_replicator
    config.qkv_linear = flags.qkv_linear
    config.max_position_embeddings = max(config.max_position_embeddings, seq_len)
    if flags.num_layers > 0:
        config.num_hidden_layers = flags.num_layers
    if flags.sequence_parallel_enabled:
        config.sequence_parallel_enabled = True
    if flags.selective_checkpoint_enabled:
        config.selective_checkpoint_enabled = True
    xm.master_print(config)
    model = LlamaForCausalLM(config)
    def get_sin_cos_matrix(config):
        head_dim = config.hidden_size // config.num_attention_heads
        base = 10000
        inv_freq = 1.0 / (base ** (torch.arange(0, head_dim, 2).float() / head_dim))
        t = torch.arange(config.max_position_embeddings, dtype=inv_freq.dtype)
        freqs = torch.einsum("i,j->ij", t, inv_freq)
        # Different from paper, but it uses a different permutation in order to obtain the same calculation
        emb = torch.cat((freqs, freqs), dim=-1)
        return emb.cos()[None, None, :, :].to(torch.float32), emb.sin()[None, None, :, :].to(torch.float32)
    # Here we make sure we use the same sine and cosine matrices for all layers.
    # Making use of same tensors would make the CSE algorithm eliminate the lookup call
    # from layers, keeping only lookup from first layer.
    with torch.no_grad():
        cos, sin = get_sin_cos_matrix(config)
        for layer in model.model.layers:
            layer.self_attn.rotary_emb.cos_cached = cos
            layer.self_attn.rotary_emb.sin_cached = sin
    xm.master_print(model)
    return model

def get_dtype(model) -> str:
    """
    Reference: https://pytorch.org/xla/release/1.12/index.html#xla-tensors-and-bfloat16
    """
    if "XLA_USE_BF16" in os.environ:
        return "torch.bfloat16"
    if "XLA_DOWNCAST_BF16" in os.environ:
        if "torch.float" in str(model.dtype):
            return "torch.bfloat16"
        if "torch.double" in str(model.dtype):
            return "torch.float32"
    return str(model.dtype)    

def allreduce_sequence_parallel_gradients(optimizer):
    """ All-reduce layernorm parameters across model parallel nodes when sequence parallelism is used.
        Modified from megatron-lm:
        https://gitlab-master.nvidia.com/ADLR/megatron-lm/-/blob/3f91f09bb2ab32f9904b47f46f19d2fc3f518ed8/megatron/training.py#L425
    """
    from neuronx_distributed.parallel_layers.mappings import reduce_from_tensor_model_parallel_region
    grads = []
    for param_group in optimizer.__getstate__()['param_groups']:
        for group, params in param_group.items():
            if group == 'params':
                for p in params:
                    if isinstance(p, torch.Tensor) and p.grad is not None:
                        sequence_parallel_param = getattr(p, 'sequence_parallel_enabled', False)
                        if sequence_parallel_param:
                            grads.append(p.grad.data)
    for grad in grads:
        # sum v.s. average: sum
        reduce_from_tensor_model_parallel_region(grad)

def train_llama(flags):
    set_seed(flags.seed)

    if flags.use_meta_device_init:
        model_init_config = {
            "meta_device_init": True,
            "param_init_fn": init_weights,
        }
    else:
        model_init_config = None

    # Setting up NxD config
    nxd_config = nxd.neuronx_distributed_config(
        tensor_parallel_size=flags.tensor_parallel_size,
        optimizer_config={"zero_one_enabled": flags.use_zero_1, "grad_clipping": True, "max_grad_norm": 1.0},
        sequence_parallel=flags.sequence_parallel_enabled,
        activation_checkpoint_config=CoreAttention if flags.selective_checkpoint_enabled else "full",
        model_init_config=model_init_config,
    )

    # Creating NxD model
    model = nxd.initialize_parallel_model(nxd_config, get_model, flags)

    world_size = parallel_state.get_data_parallel_size()
    is_root = xm.is_master_ordinal(local=False)
    extract_graphs_only = os.environ.get("NEURON_EXTRACT_GRAPHS_ONLY", None)
    worker_init = WorkerInitObj(flags.seed)
    device = xm.xla_device()

    model_dtype = get_dtype(model)
    running_loss = torch.zeros(1, dtype=torch.double).to(device)

    param_optimizer = list(model.named_parameters())
    no_decay = ["bias", "LayerNorm"]  # gamma/beta are in LayerNorm.weight

    optimizer_grouped_parameters = [
        {
            "params": [
                p for n, p in param_optimizer if not any(nd in n for nd in no_decay)
            ],
            "weight_decay": 0.01,
        },
        {
            "params": [
                p for n, p in param_optimizer if any(nd in n for nd in no_decay)
            ],
            "weight_decay": 0.0,
        },
    ]

    if flags.use_mix_precision:
        optimizer_cls = AdamW_FP32OptimParams
    else:
        optimizer_cls = AdamW

    # Creating NxD Optimizer
    optimizer = nxd.initialize_parallel_optimizer(nxd_config, optimizer_cls, optimizer_grouped_parameters, lr=flags.lr)
    optimizer.zero_grad()

    if is_root:
        if not os.path.exists(flags.output_dir):
            os.makedirs(flags.output_dir, exist_ok=True)
        if not extract_graphs_only:
            logger = Logger(flags, world_size, model_dtype)
        metric_writer = TrainingMetrics(flags.metrics_file)
        throughput = Throughput(
            flags.batch_size, world_size, flags.grad_accum_usteps, logging_interval=flags.logging_interval
        )
        print("--------TRAINING CONFIG----------")
        print(flags)
        print("--------MODEL CONFIG----------")
        print(model.config)
        print("---------------------------------")
        metric_writer.store_parameters(
            {
                "Model": model.config.model_type,
                "Model configuration": str(model.config),
                "World size": xm.xrt_world_size(),
                "Data parallel degree": world_size,
                "Batch size": flags.batch_size,
                "Total steps": flags.steps_this_run,
                "Seed": flags.seed,
                "Optimizer": str(optimizer),
                "Data type": model_dtype,
                "Gradient accumulation microsteps": flags.grad_accum_usteps,
                "Warmup steps": flags.warmup_steps,
                "Dataset": os.path.basename(os.path.normpath(flags.data_dir)),
                "Environment variables": {
                    variable: value
                    for variable, value in os.environ.items()
                    if variable.startswith("NEURON") or variable.startswith("XLA")
                },
            }
        )

    def train_loop_fn(
        model, optimizer, train_loader, epoch, global_step, training_ustep, running_loss, use_zero_1
    ):
        for _, data in enumerate(train_loader):
            training_ustep += 1
            input_ids = data["input_ids"]
            attention_mask = data["attention_mask"]
            labels = data["labels"]
            outputs = model(
                input_ids=input_ids,
                attention_mask=attention_mask,
                labels=labels,
            )
            loss = outputs.loss / flags.grad_accum_usteps
            loss.backward()
            running_loss += loss.detach()

            if training_ustep % flags.grad_accum_usteps == 0:
                xm.mark_step()
                # loss averaging
                running_loss_div = running_loss / world_size
                # Collecting loss across all data-parallel ranks
                running_loss_reduced = xm.all_reduce(
                    xm.REDUCE_SUM,
                    running_loss_div,
                    groups=parallel_state.get_data_parallel_group(as_list=True),
                )
                running_loss_reduced_detached = running_loss_reduced.detach()
                running_loss.zero_()

                optimizer.step()
                total_norm = optimizer.grad_norm # Global norm before clipping
                optimizer.zero_grad()
                scheduler.step()
                global_step += 1

                def _print_logs(running_loss_reduced_detached, total_norm):
                    if is_root and not extract_graphs_only:
                        total_norm_cpu = None
                        if flags.print_grad_norm:
                            total_norm_cpu = total_norm.cpu().item()
                        # NOTE: The running_loss is the loss of the global_step
                        logger.log(
                            epoch,
                            global_step,
                            running_loss_reduced_detached.cpu().item(),
                            optimizer.param_groups[0]["lr"],
                            throughput.get_throughput(),
                            total_norm_cpu,
                        )

                if global_step % flags.logging_interval == 0:
                    # Printing the loss inside the step closure. This won't block
                    # the tracing for next step. Also, we are logging every N steps.
                    # This is done to reduce the overhead of copying tensors to CPU.
                    # Tensor copy is expensive since it prevents the next step to start.
                    xm.add_step_closure(
                        _print_logs, (running_loss_reduced_detached, total_norm.detach())
                    )
                # Save checkpoint using checkpoint API
                if (flags.checkpoint_freq > 0) and (global_step % flags.checkpoint_freq == 0):
                    xm.add_step_closure(
                        nxd.save_checkpoint,
                        (
                            flags.checkpoint_dir, # checkpoint directory
                            f"step_{global_step}", # tag
                            model, # model
                            optimizer, # optimizer
                            scheduler, # scheduler
                            {"epoch": epoch, "global_step": global_step, "cli_args": flags.__dict__}, # user content
                            8, # num_workers
                            True, # use_xser
                            flags.num_kept_checkpoint, #num_kept_ckpts
                        )
                    )

                if global_step >= flags.steps_this_run:
                    # NOTE: Prevent runtime "Call to recv failed : Broken pipe" issue
                    xm.mark_step()
                    break

        return (
            global_step,
            training_ustep,
            running_loss,
            running_loss_reduced_detached.cpu().item(),
        )


    train_start = time.time()
    training_ustep = 0

    scheduler = get_linear_schedule_with_warmup(
        optimizer,
        num_warmup_steps=flags.warmup_steps,
        num_training_steps=flags.max_steps,
        last_epoch=-1,
    )

    if flags.resume_ckpt:
        user_content = nxd.load_checkpoint(
            flags.checkpoint_dir,
            tag=f"step_{flags.loading_step}",
            model=model,
            optimizer=optimizer,
            scheduler=scheduler,
        )
        if user_content is not None:
            epoch = user_content["epoch"]
            global_step = user_content["global_step"]
    else:
        global_step = 0
        epoch = 0

    assert os.path.exists(
        os.path.expanduser(flags.data_dir)
    ), "ERROR: Data directory {} doesn't exist!".format(flags.data_dir)

    mini_batch_size = flags.batch_size
    train_dataloader = create_pretraining_dataset(
        flags.data_dir, mini_batch_size, worker_init
    )
    # We wrap the dataloader with MpDeviceLoader. This dataloader should take
    # care of copying the tensors to device and also inserting the mark_step at
    # iteration end.
    train_device_loader = pl.MpDeviceLoader(train_dataloader, device)

    while True:
        xm.master_print(
            "Epoch {} begin {}".format(epoch, time.asctime()),
            flush=True,
        )

        global_step, training_ustep, running_loss, final_loss = train_loop_fn(
            model,
            optimizer,
            train_device_loader,
            epoch,
            global_step,
            training_ustep,
            running_loss,
            flags.use_zero_1,
        )

        if is_root and not extract_graphs_only:
            final_time = time.time()
            time_diff = final_time - train_start
            print(
                "Epoch {} step {} end {} loss {} perf {} seq/sec (at train microstep {} time {} from beginning time {})".format(
                    epoch,
                    global_step,
                    time.asctime(),
                    final_loss,
                    logger.throughputs[-1],
                    training_ustep,
                    final_time,
                    train_start,
                ),
                flush=True,
            )
            additional_data = {
                "Epoch": epoch,
                "Global step": global_step,
                "Microstep": training_ustep,
            }
            metric_data = [
                Metric("Loss", final_loss, "", additional_data),
                Metric(
                    "Throughput", logger.throughputs[-1], "seq/s", additional_data
                ),
            ]
            metric_writer.store_metrics(metric_data)

        if global_step >= flags.steps_this_run:
            if is_root and not extract_graphs_only:
                # record aggregate & final statistics in the metrics file
                additional_data = {
                    "Epoch": epoch,
                    "Global step": global_step,
                    "Microstep": training_ustep,
                }
                average_throughput = round(
                    sum(logger.throughputs) / len(logger.throughputs), 4
                )
                metric_data = [
                    Metric("Final loss", final_loss, "", additional_data),
                    Metric(
                        "Time to train",
                        round(time_diff / 60, 4),
                        "minutes",
                        additional_data,
                    ),
                    Metric(
                        "Average throughput",
                        average_throughput,
                        "seq/s",
                        additional_data,
                    ),
                    Metric(
                        "Peak throughput",
                        max(logger.throughputs),
                        "seq/s",
                        additional_data,
                    ),
                ]
                metric_writer.store_metrics(metric_data)
            return
        
        epoch += 1


def _mp_fn(index, flags):
    torch.set_default_tensor_type("torch.FloatTensor")
    train_llama(flags)
    xm.rendezvous("_mp_fn finished")


if __name__ == "__main__":
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
    parser.add_argument(
        "--output_dir",
        type=str,
        default="./output",
        help="Directory for checkpoints and logs.",
    )
    parser.add_argument(
        "--metrics_file",
        type=str,
        default="results.json",
        help="training metrics results file",
    )
    parser.add_argument("--batch_size", type=int, default=8, help="Worker batch size.")
    parser.add_argument(
        "--max_steps",
        type=int,
        help="Maximum total accumulation-steps to run.",
    )
    parser.add_argument(
        "--steps_this_run",
        type=int,
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
        "--grad_accum_usteps",
        type=int,
        default=64,
        help="Gradient accumulation micro-steps (an accumulation-step has <value> micro-steps.",
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
        help="Resume from checkpoint at resume_step."
    )
    parser.add_argument(
        "--tensor_parallel_size",
        default=2,
        type=int,
        help="Tensor parallel size"
    )
    parser.add_argument(
        "--seq_len",
        default=2048,
        type=int,
        help="Sequence length"
    )
    parser.add_argument(
        "--use_mix_precision", action="store_true", help="Use mix precision."
    )
    parser.add_argument(
        "--use_zero_1", action="store_true", help="Use ZeRO-1."
    )
    parser.add_argument(
        "--num_layers",
        type=int,
        default=-1,
        help="Override number of layers for this LLaMA model",
    )
    parser.add_argument(
        "--sequence_parallel_enabled",
        default=False,
        action="store_true",
        help="Enable sequence parallel",
    )
    parser.add_argument(
        "--selective_checkpoint_enabled",
        default=False,
        action="store_true",
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
        default=1,
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

    #Checkpointing
    parser.add_argument("--checkpoint_freq", type=int, default=100000, help="save checkpoint freq")
    parser.add_argument("--checkpoint_dir", type=str, default=None)
    parser.add_argument("--loading_step", type=int, default=-1, help="load from step, -1 means no load")
    parser.add_argument("--num_kept_checkpoint", type=int, default=-1, help="number of checkpoints kept, old checkpoint will get deleted")
    
    args = parser.parse_args(sys.argv[1:])

    if args.steps_this_run < 0:
        args.steps_this_run = args.max_steps

    os.environ["NEURON_RT_STOCHASTIC_ROUNDING_EN"] = "1"
    if args.use_mix_precision:
        os.environ["XLA_DOWNCAST_BF16"]="1"
    else:
        os.environ["XLA_USE_BF16"]="1"


    # WORLD_SIZE is set by torchrun
    if os.environ.get("WORLD_SIZE"):
        if is_pjrt_device():
            import torch_xla.experimental.pjrt_backend
            dist.init_process_group("xla", init_method="pjrt://")
        else:
            dist.init_process_group("xla") 
        _mp_fn(0, args)
    else:
        xmp.spawn(_mp_fn, args=(args,))
