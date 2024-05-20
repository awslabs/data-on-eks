import os
import time
import torch
from transformers import AutoTokenizer
from transformers_neuronx.llama.model import LlamaForSampling
from transformers import LlamaForCausalLM, LlamaTokenizer, PreTrainedTokenizerFast
from transformers_neuronx import NeuronConfig
from transformers_neuronx import GQA
from transformers_neuronx import QuantizationConfig
from transformers_neuronx.config import GenerationConfig
from fastapi import FastAPI
from ray import serve
from huggingface_hub import login


app = FastAPI()


# Set this to the Hugging Face model ID
hf_token = os.getenv('HUGGING_FACE_HUB_TOKEN')
model_id = os.getenv('MODEL_ID')
neuron_cores = 24  # inf2.24xlarge 6 Neurons (12 Neuron cores) and inf2.48xlarge 12 Neurons (24 Neuron cores)
neuron_config = NeuronConfig(
                    on_device_embedding=False,
                    attention_layout='BSH',
                    fuse_qkv=True,
                    group_query_attention=GQA.REPLICATED_HEADS,
                    quant=QuantizationConfig(),
                    on_device_generation=GenerationConfig(do_sample=True)
                )


# Define the APIIngress class responsible for handling inference requests
@serve.deployment(num_replicas=1)
@serve.ingress(app)
class APIIngress:
    def __init__(self, llama_model_handle) -> None:
        self.handle = llama_model_handle

    # Define an endpoint for inference
    @app.get("/infer")
    async def infer(self, sentence: str):
        # Asynchronously perform inference using the provided sentence
        result = await self.handle.infer.remote(sentence)
        return result


# Define the LlamaModel class responsible for managing the Llama language model
# Increase the number of replicas for the LlamaModel deployment.
# This will allow Ray Serve to handle more concurrent requests.
@serve.deployment(
    ray_actor_options={
        "resources": {"neuron_cores": neuron_cores},
        "runtime_env": {"env_vars": {"NEURON_CC_FLAGS": "-O1"}},
    },
    autoscaling_config={"min_replicas": 1, "max_replicas": 2},
)
class LlamaModel:
    def __init__(self):
        # Log in to the Hugging Face Hub
        login(token=hf_token)

        # Load and compile the Neuron-optimized Llama model
        self.neuron_model = LlamaForSampling.from_pretrained(
                                model_id,
                                neuron_config=neuron_config,
                                batch_size=1,
                                tp_degree=neuron_cores,
                                amp='f16',
                                n_positions=4096
                            )
        self.neuron_model.to_neuron()

        # Initialize tokenizer for the model
        self.tokenizer = AutoTokenizer.from_pretrained(model_id)

    # Define the method for performing inference with the Llama model
    def infer(self, sentence: str):
        # Tokenize the input sentence and encode it
        input_ids = self.tokenizer.encode(sentence, return_tensors="pt")

        # Perform inference with Neuron-optimized model
        with torch.inference_mode():
            generated_sequences = self.neuron_model.sample(
                                    input_ids,
                                    temperature=0.5,
                                    sequence_length=2048,
                                    top_p=0.9,
                                    no_repeat_ngram_size=3
                                )
        # Decode the generated sequences and return the results
        return [self.tokenizer.decode(seq, skip_special_tokens=True) for seq in generated_sequences]


# Create an entry point for the FastAPI application
entrypoint = APIIngress.bind(LlamaModel.bind())
