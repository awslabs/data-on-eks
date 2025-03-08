from dataclasses import dataclass, field
from datasets import load_dataset
from peft import LoraConfig
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    set_seed,
)

from optimum.neuron import NeuronHfArgumentParser as HfArgumentParser
from optimum.neuron import NeuronSFTConfig, NeuronSFTTrainer, NeuronTrainingArguments
from optimum.neuron.distributed import lazy_load_for_parallelism


def training_function(script_args, training_args):
    dataset = load_dataset("b-mc2/sql-create-context", split="train")
    dataset = dataset.shuffle(seed=23)
    train_dataset = dataset.select(range(50000))
    eval_dataset = dataset.select(range(50000, 50500))

    def create_conversation(sample):
        system_message = (
            "You are a text to SQL query translator. Users will ask you questions in English and you will generate a "
            "SQL query based on the provided SCHEMA.\nSCHEMA:\n{schema}"
        )
        return {
            "messages": [
                {"role": "system", "content": system_message.format(schema=sample["context"])},
                {"role": "user", "content": sample["question"]},
                {"role": "assistant", "content": sample["answer"]},
            ]
        }

    train_dataset = train_dataset.map(
        create_conversation, remove_columns=train_dataset.features, batched=False
    )
    eval_dataset = eval_dataset.map(
        create_conversation, remove_columns=eval_dataset.features, batched=False
    )

    tokenizer = AutoTokenizer.from_pretrained("meta-llama/Meta-Llama-3-8B-Instruct")
    tokenizer.pad_token = tokenizer.eos_token
    tokenizer.eos_token_id = 128001

    with lazy_load_for_parallelism(tensor_parallel_size=training_args.tensor_parallel_size):
        model = AutoModelForCausalLM.from_pretrained("meta-llama/Meta-Llama-3-8B")

    config = LoraConfig(
        r=8,
        lora_alpha=64,
        lora_dropout=0.05,
        target_modules=[
            "q_proj",
            "k_proj",
            "v_proj",
            "o_proj",
            "gate_proj",
            "up_proj",
            "down_proj",
        ],
        bias="none",
        task_type="CAUSAL_LM",
        use_rslora=True,
    )

    args = training_args.to_dict()

    sft_config = NeuronSFTConfig(
        max_seq_length=1024,
        packing=True,
        **args,
        dataset_kwargs={
            "add_special_tokens": False,
            "append_concat_token": True,
        },
    )

    trainer = NeuronSFTTrainer(
        args=sft_config,
        model=model,
        peft_config=config,
        tokenizer=tokenizer,
        train_dataset=train_dataset,
        eval_dataset=eval_dataset,
    )

    print(trainer.model)
    trainer.model.print_trainable_parameters()

    # Start training
    trainer.train()


@dataclass
class ScriptArguments:
    model_id: str = field(
        # default="meta-llama/Meta-Llama-3-8B",
        default="meta-llama/Meta-Llama-3-8B",
        metadata={
            "help": "The model that you want to train from the Hugging Face hub."
        },
    )


if __name__ == "__main__":
    parser = HfArgumentParser([ScriptArguments, NeuronTrainingArguments])
    script_args, training_args = parser.parse_args_into_dataclasses()

    set_seed(training_args.seed)
    training_function(script_args, training_args)
