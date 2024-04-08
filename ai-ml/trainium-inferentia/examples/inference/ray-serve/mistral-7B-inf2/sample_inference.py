import torch
from transformers import AutoTokenizer
from transformers_neuronx import MistralForSampling, GQA, NeuronConfig

# Set sharding strategy for GQA to be shard over heads
neuron_config = NeuronConfig(
    group_query_attention=GQA.SHARD_OVER_HEADS
)

# Create and compile the Neuron model
model_neuron = MistralForSampling.from_pretrained('mistralai/Mistral-7B-Instruct-v0.2', amp='bf16', neuron_config=neuron_config)
model_neuron.to_neuron()

# Get a tokenizer and exaple input
tokenizer = AutoTokenizer.from_pretrained('mistralai/Mistral-7B-Instruct-v0.2')
text = "[INST] What is your favourite condiment? [/INST]"
encoded_input = tokenizer(text, return_tensors='pt')

# Run inference
with torch.inference_mode():
    generated_sequence = model_neuron.sample(encoded_input.input_ids, sequence_length=256, start_ids=None)
print([tokenizer.decode(tok) for tok in generated_sequence])
