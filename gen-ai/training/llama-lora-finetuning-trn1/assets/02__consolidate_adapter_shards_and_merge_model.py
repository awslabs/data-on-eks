from optimum.neuron.distributed.checkpointing import (
    consolidate_model_parallel_checkpoints_to_unified_checkpoint,
)
from transformers import AutoModel
from argparse import ArgumentParser
from shutil import copyfile
import os
import peft

parser = ArgumentParser()
parser.add_argument(
    "-i",
    "--input_dir",
    help="source checkpoint directory containing sharded adapter checkpoint files",
    required=True,
)
parser.add_argument(
    "-o",
    "--output_dir",
    help="destination directory for final merged model (adapters merged into base model)",
    required=True,
)
args = parser.parse_args()

consolidated_ckpt_dir = os.path.join(args.input_dir, "consolidated")

# Consolidate the adapter shards into a PEFT-compatible checkpoint
consolidate_model_parallel_checkpoints_to_unified_checkpoint(
    args.input_dir, consolidated_ckpt_dir
)
copyfile(
    os.path.join(args.input_dir, "adapter_config.json"),
    os.path.join(consolidated_ckpt_dir, "adapter_config.json"),
)

# Load AutoPeftModel using the consolidated PEFT checkpoint
peft_model = peft.AutoPeftModelForCausalLM.from_pretrained(consolidated_ckpt_dir)

# Merge adapter weights into base model, save new pretrained model
merged_model = peft_model.merge_and_unload()
merged_model.save_pretrained(args.output_dir)

# Load the pretrained model and print config
model = AutoModel.from_pretrained(args.output_dir)
print(model)
