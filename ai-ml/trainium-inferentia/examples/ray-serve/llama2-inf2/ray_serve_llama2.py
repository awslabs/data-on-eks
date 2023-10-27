from fastapi import FastAPI
from ray import serve
import torch
import os
from transformers import AutoTokenizer, AutoModelForCausalLM

app = FastAPI()

# Define the Llama model and related parameters
llm_model = "NousResearch/Llama-2-13b-chat-hf"
llm_model_split = "llama-2-13b-chat-hf-split"
neuron_cores = 24  # inf2.24xlarge 6 Neurons (12 Neuron cores) and inf2.48xlarge 12 Neurons (24 Neuron cores)


# Define the APIIngress class responsible for handling inference requests
@serve.deployment(num_replicas=1)
@serve.ingress(app)
class APIIngress:
    def __init__(self, llama_model_handle):
        self.handle = llama_model_handle

    # Define an endpoint for inference
    @app.get("/infer")
    async def infer(self, sentence: str):
        # Asynchronously perform inference using the provided sentence
        ref = await self.handle.infer.remote(sentence)
        # Await the result of the asynchronous inference and return it
        result = await ref
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
        from transformers_neuronx.llama.model import LlamaForSampling
        from transformers_neuronx.module import save_pretrained_split

        # Check if the model split exists locally, and if not, download it
        if not os.path.exists(llm_model_split):
            print(f"Saving model split for {llm_model} to local path {llm_model_split}")
            self.model = AutoModelForCausalLM.from_pretrained(llm_model)
            save_pretrained_split(self.model, llm_model_split)
        else:
            print(f"Using existing model split {llm_model_split}")

        print(f"Loading and compiling model {llm_model_split} for Neuron")
        # Load and compile the Neuron-optimized Llama model
        self.neuron_model = LlamaForSampling.from_pretrained(llm_model_split,
                                                             batch_size=1,
                                                             tp_degree=neuron_cores,
                                                             amp='f16')
        self.neuron_model.to_neuron()
        self.tokenizer = AutoTokenizer.from_pretrained(llm_model)

    # Define the method for performing inference with the Llama model
    def infer(self, sentence: str):
        # Tokenize the input sentence and encode it
        input_ids = self.tokenizer.encode(sentence, return_tensors="pt")
        # Perform inference with Neuron-optimized model
        with torch.inference_mode():
            generated_sequences = self.neuron_model.sample(input_ids,
                                                           sequence_length=2048,
                                                           top_k=50)
        # Decode the generated sequences and return the results
        return [self.tokenizer.decode(seq, skip_special_tokens=True) for seq in generated_sequences]


# Create an entry point for the FastAPI application
entrypoint = APIIngress.bind(LlamaModel.bind())
