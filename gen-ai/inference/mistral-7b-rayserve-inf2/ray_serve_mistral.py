# Import necessary libraries and modules
from io import BytesIO
from fastapi import FastAPI
import os

from ray import serve

import torch

# Initialize the FastAPI app
app = FastAPI()

# Define the number of Neuron cores to be used
neuron_cores = 2

# Deployment settings for the API ingress using Ray Serve
@serve.deployment(name="mistral-deployment", num_replicas=1, route_prefix="/")
@serve.ingress(app)
class APIIngress:
    # Constructor to initialize the API with a model handle
    def __init__(self, mistral_model_handle) -> None:
        self.handle = mistral_model_handle

    # Define a GET endpoint for inference
    @app.get("/infer")
    async def infer(self, sentence: str):
        # Asynchronously perform inference using the provided sentence and return the result
        result = await self.handle.infer.remote(sentence)
        return result

# Deployment settings for the Mistral model using Ray Serve
@serve.deployment(name="mistral-7b",
    autoscaling_config={"min_replicas": 0, "max_replicas": 6},
    ray_actor_options={
        "resources": {"neuron_cores": neuron_cores},
        "runtime_env": {"env_vars": {"NEURON_CC_FLAGS": "-O1"}},
    },
)
class MistralModel:
    # Constructor to initialize and load the model
    def __init__(self):

        # Import additional necessary modules
        from transformers import AutoTokenizer
        from transformers_neuronx import MistralForSampling, GQA, NeuronConfig
        from huggingface_hub import login

        # Retrieve environment variables for API authentication and model ID
        hf_token = os.getenv('HUGGING_FACE_HUB_TOKEN')
        model_id = os.getenv('MODEL_ID')

        # Log in to the Hugging Face Hub
        login(token=hf_token)

        # Set the sharding strategy for the model to optimize performance
        neuron_config = NeuronConfig(
            group_query_attention=GQA.SHARD_OVER_HEADS
        )

        # Load and compile the Neuron model with specific configuration
        self.neuron_model = MistralForSampling.from_pretrained(model_id, amp='bf16', neuron_config=neuron_config)
        self.neuron_model.to_neuron()

        # Initialize tokenizer for the model
        self.tokenizer = AutoTokenizer.from_pretrained(model_id)

    # Define the inference method to process input text
    def infer(self, sentence: str):
        # Prepare input text with specific format
        text = "[INST]" + sentence + "[/INST]"

        # Tokenize and encode the input text
        encoded_input = self.tokenizer.encode(text, return_tensors='pt')

        # Perform inference in a context that disables gradient calculation
        with torch.inference_mode():
            generated_sequence = self.neuron_model.sample(encoded_input, sequence_length=512, start_ids=None)

        # Decode the generated sequences into human-readable text and return
        return [self.tokenizer.decode(seq) for seq in generated_sequence]

# Bind the model to the API ingress to enable endpoint functionality
entrypoint = APIIngress.bind(MistralModel.bind())
