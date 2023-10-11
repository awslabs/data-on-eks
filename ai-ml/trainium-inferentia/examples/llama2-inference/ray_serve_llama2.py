from fastapi import FastAPI
from ray import serve

import torch
import os
from transformers import AutoTokenizer

app = FastAPI()

llm_model = "NousResearch/Llama-2-13b-chat-hf"
llm_model_split = "llama-2-13b-chat-hf-split"
neuron_cores=12 # inf2.24xlarge 6 Neurons (12 Neuron cores)

@serve.deployment(num_replicas=1)
@serve.ingress(app)
class APIIngress:
    def __init__(self, llama_model_handle):
        self.handle = llama_model_handle

    @app.get("/infer")
    async def infer(self, sentence: str):
        ref = await self.handle.infer.remote(sentence)
        result = await ref
        return result

@serve.deployment(
    ray_actor_options={"resources": {"neuron_cores": neuron_cores},
                       "runtime_env": {"env_vars": {"NEURON_CC_FLAGS": "--model-type=transformer-inference"}}},
    autoscaling_config={"min_replicas": 1, "max_replicas": 1},
)
class LlamaModel:
    def __init__(self):
        from transformers_neuronx.llama.model import LlamaForSampling
        from transformers_neuronx.module import save_pretrained_split

        if not os.path.exists(llm_model_split):
            print(f"Saving model split for {llm_model} to local path {llm_model_split}")
            self.model = LlamaForSampling.from_pretrained(llm_model)
            save_pretrained_split(self.model, llm_model_split)
        else:
            print(f"Using existing model split {llm_model_split}")

        print(f"Loading and compiling model {llm_model_split} for Neuron")
        self.neuron_model = LlamaForSampling.from_pretrained(llm_model_split, batch_size=1, tp_degree=neuron_cores, amp='f16')
        self.neuron_model.to_neuron()
        self.tokenizer = AutoTokenizer.from_pretrained(llm_model)

    def infer(self, sentence: str):
        input_ids = self.tokenizer.encode(sentence, return_tensors="pt")
        with torch.inference_mode():
            generated_sequences = self.neuron_model.sample(input_ids, sequence_length=2048, top_k=50)
        return [self.tokenizer.decode(seq, skip_special_tokens=True) for seq in generated_sequences]

entrypoint = APIIngress.bind(LlamaModel.bind())
