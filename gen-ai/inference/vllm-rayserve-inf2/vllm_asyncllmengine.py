import os
import json

from fastapi import FastAPI
from fastapi import Body
from ray import serve
from pydantic import BaseModel
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine
from vllm.sampling_params import SamplingParams
from vllm.utils import random_uuid

app = FastAPI()

# Define a model for the sampling parameters
class SamplingParamsModel(BaseModel):
    temperature: float
    top_p: float

# Define a model for the request body
class GenerateRequestModel(BaseModel):
    prompt: str
    sampling_params: SamplingParamsModel

@serve.deployment()
@serve.ingress(app)
class VLLMDeployment:
    def __init__(self):
        engine_args = AsyncEngineArgs(
            model=os.getenv("MODEL_ID", "TinyLlama/TinyLlama-1.1B-Chat-v1.0"),
            disable_log_requests=True,
            tensor_parallel_size=1,
            max_model_len=128,
            block_size=128,
            max_num_seqs=8,
            device="neuron",
            dtype="auto")
        
        self.engine = AsyncLLMEngine.from_engine_args(engine_args)

    @app.post("/generate")
    async def generate(self, request: GenerateRequestModel = Body(...)):
        prompt = request.prompt
        sampling_params_dict = request.sampling_params.dict()
        sampling_params_obj = SamplingParams(**sampling_params_dict)
        
        request_id = random_uuid()
        # Use async for to handle the async generator
        async_gen = self.engine.generate(prompt, sampling_params_obj, request_id)
        results = []
        async for output in async_gen:
            results.append(output)
        
        return results

deployment = VLLMDeployment.bind()