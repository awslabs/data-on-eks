from io import BytesIO
from fastapi import FastAPI
import os

from ray import serve

import torch

app = FastAPI()

neuron_cores = 2

@serve.deployment(name="mistral-deployment", num_replicas=1, route_prefix="/")
@serve.ingress(app)
class APIIngress:
    def __init__(self, mistral_model_handle) -> None:
        self.handle = mistral_model_handle

    @app.get("/infer")
    async def infer(self, sentence: str):
        # Asynchronously perform inference using the provided sentence
        result = await self.handle.infer.remote(sentence)
        return result


@serve.deployment(name="mistral-7b",
    autoscaling_config={"min_replicas": 0, "max_replicas": 6},
    ray_actor_options={
        "resources": {"neuron_cores": neuron_cores},
        "runtime_env": {"env_vars": {"NEURON_CC_FLAGS": "-O1"}},
    },
)
class MistralModel:
    def __init__(self):

        from transformers import AutoTokenizer
        from transformers_neuronx import MistralForSampling, GQA, NeuronConfig
        from huggingface_hub import login

        hf_token = os.getenv('HUGGING_FACE_HUB_TOKEN')
        model_id = os.getenv('MODEL_ID')

        login(token=hf_token)

        # Set sharding strategy for GQA to be shard over heads
        neuron_config = NeuronConfig(
            group_query_attention=GQA.SHARD_OVER_HEADS
        )

        # Create and compile the Neuron model
        self.neuron_model = MistralForSampling.from_pretrained(model_id, amp='bf16', neuron_config=neuron_config)
        self.neuron_model.to_neuron()

        # Get a tokenizer and exaple input
        self.tokenizer = AutoTokenizer.from_pretrained(model_id)


        # Define the method for performing inference with the Mistral model
    def infer(self, sentence: str):

        text = "[INST]" + sentence + "[/INST]"

        # Tokenize the input sentence and encode it
        encoded_input = self.tokenizer.encode(text, return_tensors='pt')

        # Run inference
        with torch.inference_mode():
            generated_sequence = self.neuron_model.sample(encoded_input, sequence_length=512, start_ids=None)

        # Decode the generated sequences and return the results
        return [self.tokenizer.decode(seq) for seq in generated_sequence]

entrypoint = APIIngress.bind(MistralModel.bind())
