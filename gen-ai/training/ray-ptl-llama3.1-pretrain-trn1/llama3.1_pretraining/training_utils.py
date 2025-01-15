import json
import math
import os
import queue
import time
from datetime import datetime, timezone
from functools import partial
from itertools import chain
from typing import Any, Dict, List

import datasets
import torch
from torch.utils.data import DistributedSampler
from torch.utils.data.dataloader import DataLoader
from transformers import default_data_collator, set_seed
from neuronx_distributed.parallel_layers.parallel_state import (
    get_tensor_model_parallel_size,
)

try:
    from lr import CosineAnnealing
except ImportError:
    CosineAnnealing = None

from collections import namedtuple

Metric = namedtuple("Metric", ["name", "value", "units", "additional_data"])
remainder = {"input_ids": [], "attention_mask": [], "token_type_ids": []}


# empty list to save remainder from batches to use in next batch
def pack_dataset(dataset, chunk_length=2048):
    print(f"Chunking dataset into chunks of {chunk_length} tokens.")

    def chunk(sample, chunk_length=chunk_length):
        # define global remainder variable to save remainder from batches to use in next batch
        global remainder
        # Concatenate all texts and add remainder from previous batch
        concatenated_examples = {k: list(chain(*sample[k])) for k in sample.keys()}
        concatenated_examples = {k: remainder[k] + concatenated_examples[k] for k in concatenated_examples.keys()}
        # get total number of tokens for batch
        batch_total_length = len(concatenated_examples[list(sample.keys())[0]])

        # get max number of chunks for batch
        if batch_total_length >= chunk_length:
            batch_chunk_length = (batch_total_length // chunk_length) * chunk_length

        # Split by chunks of max_len.
        result = {
            k: [t[i : i + chunk_length] for i in range(0, batch_chunk_length, chunk_length)]
            for k, t in concatenated_examples.items()
        }
        # add remainder to global variable for next batch
        remainder = {k: concatenated_examples[k][batch_chunk_length:] for k in concatenated_examples.keys()}
        
        # prepare labels
        result["labels"] = result["input_ids"].copy()
        
        return result

    # tokenize and chunk dataset
    lm_dataset = dataset.map(
        partial(chunk, chunk_length=chunk_length),
        batched=True,
    )
    print(f"Total number of samples: {len(lm_dataset)}")
    return lm_dataset

def get_learning_rate_scheduler(optimizer, args, last_epoch=-1):
    lr_scheduler = CosineAnnealing(
        optimizer,
        max_steps=args.max_steps,
        min_lr=args.min_lr,
        warmup_steps=args.warmup_steps,
        constant_steps=args.constant_steps,
        last_epoch=last_epoch,
    )
    return lr_scheduler


def get_param_groups_by_weight_decay(model):
    """Get param groups."""
    if hasattr(model, "local_named_parameters"):
        # Zero1 use the first param in opt to decide the device
        param_optimizer = list(model.local_named_parameters())
    else:
        param_optimizer = list(model.named_parameters())
    no_decay = ["bias", "LayerNorm"]  # gamma/beta are in LayerNorm.weight

    optimizer_grouped_parameters = [
        {
            "params": [p for n, p in param_optimizer if not any(nd in n for nd in no_decay)],
            "weight_decay": 0.01,
        },
        {
            "params": [p for n, p in param_optimizer if any(nd in n for nd in no_decay)],
            "weight_decay": 0.0,
        },
    ]
    return optimizer_grouped_parameters


def create_llama_pretraining_dataset(data_dir, mini_batch_size, dp_size, dp_rank, seed):
    # Workaround because python functions are not picklable
    class WorkerInitObj(object):
        def __init__(self, seed):
            self.seed = seed

        def __call__(self, id):
            set_seed(self.seed)

    worker_init = WorkerInitObj(seed)
    train_data = datasets.load_from_disk(data_dir)
    train_sampler = DistributedSampler(
        train_data,
        num_replicas=dp_size,
        rank=dp_rank,
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
    return train_dataloader, None


def create_instruction_based_dataset(data_dir, mini_batch_size, dp_size, dp_rank, seed, tokenizer=None, task=None):
    raw_datasets = datasets.load_dataset(data_dir, split="train")
    if task:
        raw_datasets = raw_datasets.filter(lambda example: example["category"] == task)
    train_and_test_dataset = raw_datasets.train_test_split(test_size=2)
    train_dataset = train_and_test_dataset["train"]
    test_dataset = train_and_test_dataset["test"]
    
    def preprocess_train_dataset(sample):
        instruction = f"### Instruction\n{sample['instruction']}"
        context = f"### Context\n{sample['context']}" if len(sample["context"]) > 0 else None
        response = f"### Answer\n{sample['response']}"
        # join all the parts together
        prompt = "\n".join([i for i in [instruction, context, response] if i is not None])
        model_input = tokenizer(f"{prompt}{tokenizer.eos_token}")
        return model_input

    train_data = train_dataset.shuffle().map(preprocess_train_dataset, remove_columns=train_dataset.column_names)
    train_data = pack_dataset(train_data, chunk_length=2048)

    class WorkerInitObj(object):
        def __init__(self, seed):
            self.seed = seed

        def __call__(self, id):
            set_seed(self.seed)

    worker_init = WorkerInitObj(seed)

    train_sampler = DistributedSampler(
        train_data,
        num_replicas=dp_size,
        rank=dp_rank,
        shuffle=True,
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

    def preprocess_test_dataset(sample):
        instruction = f"### Instruction\n{sample['instruction']}"
        context = f"### Context\n{sample['context']}" if len(sample["context"]) > 0 else None
        response = f"### Answer\n"
        # join all the parts together
        prompt = "\n".join([i for i in [instruction, context, response] if i is not None])
        model_input = tokenizer(prompt, add_special_tokens=False)
        #Find the nearest input length divisible by TP_SIZE
        max_length = len(model_input['input_ids']) - len(model_input['input_ids']) % get_tensor_model_parallel_size() + get_tensor_model_parallel_size()
        #max_length = 128
        tokenizer.pad_token = tokenizer.eos_token
        #add padding to match the length of the nearest input length divisible by TP_SIZE
        model_input = tokenizer(prompt, max_length=max_length, padding='max_length', truncation=True)
        labels = tokenizer(sample["response"])
        model_input["labels"] = labels["input_ids"]
        return model_input

    test_data = test_dataset.map(preprocess_test_dataset, remove_columns=test_dataset.column_names)

    test_sampler = DistributedSampler(
        test_data,
        num_replicas=dp_size,
        rank=dp_rank,
        shuffle=False,
        drop_last=False,
    )
    test_dataloader = DataLoader(
        test_data,
        collate_fn=default_data_collator,
        sampler=test_sampler,
        batch_size=mini_batch_size,
        num_workers=0,
        drop_last=False,
        pin_memory=True,
    )

    return train_dataloader, test_dataloader


def create_partition(num_hidden_layers, pipeline_parallel_size):
    """
    Evenly split the transformer layers between the PP ranks
    """
    assert num_hidden_layers % pipeline_parallel_size == 0
    num_layer_per_partition = num_hidden_layers // pipeline_parallel_size
    pipeline_cuts = []
    current_cut = num_layer_per_partition - 1
    for i in range(pipeline_parallel_size - 1):
        pipeline_cuts.append(f"model.layers.{current_cut}")
        current_cut += num_layer_per_partition
    return pipeline_cuts


def get_sin_cos_matrix(config):
    head_dim = config.hidden_size // config.num_attention_heads
    base = config.rope_theta
    inv_freq = 1.0 / (base ** (torch.arange(0, head_dim, 2).float() / head_dim))
    t = torch.arange(config.max_position_embeddings, dtype=inv_freq.dtype)
    freqs = torch.einsum("i,j->ij", t, inv_freq)
    # Different from paper, but it uses a different permutation in order to obtain the same calculation
    emb = torch.cat((freqs, freqs), dim=-1)
    return emb.cos()[None, None, :, :].to(torch.float32), emb.sin()[None, None, :, :].to(torch.float32)


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


def print_logs(loss, global_norm, args, throughput, logger, total_steps, current_lr, input_ids, start):
    total_norm_cpu = global_norm.cpu().item()
    logger.log(total_steps, loss, total_norm_cpu, current_lr, input_ids, throughput, start)


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
            with open(self.json_file, "r") as json_file:
                content = json_file.read()
                if not content.strip():  # Check if content is empty or contains only whitespace
                    print("File is empty or contains only whitespace.")
                else:
                    result_dict = json.loads(content) or result_dict
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
    def __init__(self, batch_size, world_size, grad_accum_usteps, moving_avg_window_size=10, logging_interval=1):
        """
        Used to calculate the throughput over a moving window. It records the step time
        between two calls and uses that time to calculate the throughput.
        """
        self.seqs_per_iteration = batch_size * world_size * grad_accum_usteps * logging_interval
        self.moving_avg_window_size = math.ceil(moving_avg_window_size / logging_interval)
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


def get_mixed_precision_config(use_gpu_compatible_precision):
    return {
        "use_master_weights": bool(use_gpu_compatible_precision),
        "use_fp32_grad_acc": bool(use_gpu_compatible_precision),
        "use_master_weights_in_ckpt": False,
    }

