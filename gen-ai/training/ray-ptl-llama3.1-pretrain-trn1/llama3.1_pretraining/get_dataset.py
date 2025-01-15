from datasets import load_dataset
import os
import argparse
from itertools import chain
from transformers import AutoTokenizer

parser = argparse.ArgumentParser()
parser.add_argument('--llama-version', type=int, default=3.1, help='LLaMA version (default: 3.1)')

args = parser.parse_args()
llama_version = args.llama_version

dataset_name = "HuggingFaceFW/fineweb"
#local_download_dir = "~/fineweb/"
sample = "sample-10BT"

block_size = 8192
save_path = "/shared/fineweb_llama3.1_tokenized"
target_dataset_path = save_path + "/" + dataset_name

model_id = "NousResearch/Meta-Llama-3.1-8B"

save_path = os.path.expanduser(save_path)
if not os.path.exists(save_path):
    os.makedirs(save_path)

raw_datasets = load_dataset(dataset_name, cache_dir=target_dataset_path, name=sample, split="train")
tokenizer = AutoTokenizer.from_pretrained(model_id)

column_names = raw_datasets.column_names
text_column_name = "text" if "text" in column_names else column_names[0]

def tokenize_function(examples):
    return tokenizer(examples[text_column_name])

tokenized_datasets = raw_datasets.map(
    tokenize_function,
    batched=True,
    remove_columns=column_names,
)

if block_size > tokenizer.model_max_length:
    print("block_size > tokenizer.model_max_length")
block_size = min(block_size, tokenizer.model_max_length)


# Main data processing function that will concatenate all texts from our dataset and generate chunks of block_size.
def group_texts(examples):
    # Concatenate all texts.
    concatenated_examples = {k: list(chain(*examples[k])) for k in examples.keys()}
    total_length = len(concatenated_examples[list(examples.keys())[0]])
    # We drop the small remainder, and if the total_length < block_size  we exclude this batch and return an empty dict.
    # We could add padding if the model supported it instead of this drop, you can customize this part to your needs.
    total_length = (total_length // block_size) * block_size
    # Split by chunks of max_len.
    result = {
        k: [t[i : i + block_size] for i in range(0, total_length, block_size)] for k, t in concatenated_examples.items()
    }
    result["labels"] = result["input_ids"].copy()
    return result


train_dataset = tokenized_datasets.map(
    group_texts,
    batched=True,
)

print(len(train_dataset))

train_dataset.save_to_disk(save_path)

