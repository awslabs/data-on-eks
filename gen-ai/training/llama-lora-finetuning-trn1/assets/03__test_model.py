from datasets import load_dataset
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
)
import subprocess
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument(
    "-m",
    "--model",
    help="path to the fine-tuned model that includes merged LoRA adapters",
    required=True,
)

args = parser.parse_args()
MODEL_ORIG_PATH = "meta-llama/Meta-Llama-3-8B"
TOKENIZER_PATH = "meta-llama/Meta-Llama-3-8B-Instruct"

dataset = load_dataset("b-mc2/sql-create-context", split="train")
dataset = dataset.shuffle(seed=23)
eval_dataset = dataset.select(range(50000,50500))

def create_conversation(sample):
    # Convert dataset to OAI messages
    system_message = (
        "You are an text to SQL query translator. Users will ask you questions in English and you will generate a "
        "SQL query based on the provided SCHEMA.\nSCHEMA:\n{schema}"
    )
    return {
        "messages": [
            {"role": "system", "content": system_message.format(schema=sample["context"])},
            {"role": "user", "content": sample["question"]},
            {"role": "assistant", "content": sample["answer"]},
        ]
    }

eval_dataset = eval_dataset.map(create_conversation, remove_columns=eval_dataset
                            .features, batched=False)

tokenizer = AutoTokenizer.from_pretrained(TOKENIZER_PATH)
tokenizer.pad_token = tokenizer.eos_token

model_orig = AutoModelForCausalLM.from_pretrained(MODEL_ORIG_PATH)
tuned_model = AutoModelForCausalLM.from_pretrained(args.model)

for n in [94, 99, 123]:
    example = tokenizer.apply_chat_template(eval_dataset
                                        [n]['messages'][0:-1], tokenize=False, add_generation_prompt=True, return_tensors="pt")
    example_tokenized = tokenizer.apply_chat_template(eval_dataset
                                                    [n]['messages'][0:-1], tokenize=True, add_generation_prompt=True, return_tensors="pt")
    prompt_len = len(example_tokenized[0])

    subprocess.run("clear")
    print(f"######### PROMPT:\n\n{example}")
    print()
    print()
    print("Generating output for the prompt using the base model and the new fine-tuned model. Please wait...")
    print()
    print()

    outputs = tuned_model.generate(example_tokenized, max_new_tokens=50, pad_token_id=128001)
    outputs_orig = model_orig.generate(example_tokenized, max_new_tokens=50, pad_token_id=128001)

    print(f"######### BASE MODEL OUTPUT:\n\n{tokenizer.decode(outputs_orig[0][prompt_len:])}")
    print()
    print()
    print(f"######### FINETUNED MODEL OUTPUT:\n\n{tokenizer.decode(outputs[0][prompt_len:])}")
    print()
    _ = input("Press <ENTER> to continue")
