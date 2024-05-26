from datasets import load_dataset      # Library for loading datasets
from transformers import AutoTokenizer # Library for handling tokenization
from itertools import chain            # For efficiently iterating through multiple sequences
import os                             # For file and directory operations

# Configuration
dataset_name = "wikicorpus"            # Name of the dataset to load
dataset_config_name = "raw_en"        # Configuration of the dataset (e.g., language)
save_path = "/shared/wikicorpus_llama2_7B_tokenized_4k"  # Path to save tokenized data
tokenizer_path = os.getcwd()         # Path to the tokenizer model (assumed to be in the current directory)

# Ensure Save Directory Exists
save_path = os.path.expanduser(save_path)  # Expand ~ to home directory
tokenizer_path = os.path.expanduser(tokenizer_path)
if not os.path.exists(save_path):         # Create directory if it doesn't exist
    os.makedirs(save_path)

block_size = 4096  # Size of text chunks for processing

# Load Dataset
raw_datasets = load_dataset(dataset_name, dataset_config_name)

# Load Tokenizer
tokenizer = AutoTokenizer.from_pretrained(tokenizer_path)

# Determine Text Column Name
column_names = raw_datasets["train"].column_names
text_column_name = "text" if "text" in column_names else column_names[0]

# Tokenization Function
def tokenize_function(examples):
    return tokenizer(examples[text_column_name])

# Tokenize Dataset
tokenized_datasets = raw_datasets.map(
    tokenize_function,              # Apply tokenization function
    batched=True,                   # Process in batches for efficiency
    remove_columns=column_names,    # Remove original columns after tokenization
    load_from_cache_file=True,     # Load from cache if available
    desc="Running tokenizer on dataset", # Description for progress bar
)

# Adjust Block Size
if block_size > tokenizer.model_max_length:  # Ensure block size doesn't exceed model limit
    print("block_size > tokenizer.model_max_length")
block_size = min(block_size, tokenizer.model_max_length)

# Main data processing function that will concatenate all texts from our dataset and generate chunks of block_size.
def group_texts(examples):
    # Concatenate Texts
    concatenated_examples = {k: list(chain(*examples[k])) for k in examples.keys()}
    total_length = len(concatenated_examples[list(examples.keys())[0]])
    # We drop the small remainder, and if the total_length < block_size  we exclude this batch and return an empty dict.
    # We could add padding if the model supported it instead of this drop, you can customize this part to your needs.
    total_length = (total_length // block_size) * block_size
    # Split by chunks of max_len.
    result = {
        k: [t[i : i + block_size] for i in range(0, total_length, block_size)]
        for k, t in concatenated_examples.items()
    }
    result["labels"] = result["input_ids"].copy()  # Labels are same as input for pretraining
    return result

# Apply Grouping and Chunking
lm_datasets = tokenized_datasets.map(
    group_texts,
    batched=True,
    load_from_cache_file=True,
    desc=f"Grouping texts in chunks of {block_size}",
)

# Extract Training Dataset
train_dataset = lm_datasets["train"]
print(len(train_dataset))

# Save Tokenized Data
train_dataset.save_to_disk(save_path)
