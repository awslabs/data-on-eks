# File: vllm_serve.py
import json
import logging
import os
from typing import Any, AsyncGenerator, Dict

from fastapi import BackgroundTasks, HTTPException
from ray import serve
from starlette.requests import Request
from starlette.responses import Response, StreamingResponse
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine
from vllm.sampling_params import SamplingParams
from vllm.utils import random_uuid
from huggingface_hub import login

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ray.serve")

# Environment and configuration setup v1
_VLLM_ENGINE_ARGS_FILENAME = "vllm_engine_args.json"

@serve.deployment(
    name="mistral-deployment",
    route_prefix="/vllm",
    ray_actor_options={"num_gpus": 1},
    autoscaling_config={"min_replicas": 1, "max_replicas": 2}
)
class VLLMDeployment:
    def __init__(self):
        hf_token = os.getenv("HUGGING_FACE_HUB_TOKEN")
        if not hf_token:
            raise ValueError("HUGGING_FACE_HUB_TOKEN environment variable is not set")
        login(token=hf_token)
        logger.info("Logged in to Hugging Face")

        model_name = os.getenv("MODEL_ID", "mistralai/Mistral-7B-Instruct-v0.2")
        dtype = os.getenv("DTYPE", "auto")
        tensor_parallel_size = int(os.getenv("TENSOR_PARALLEL_SIZE", "1"))
        gpu_memory_utilization = float(os.getenv("GPU_MEMORY_UTILIZATION", "0.8"))
        max_model_len = int(os.getenv("MAX_MODEL_LEN", "4096"))

        # Configure vLLM engine
        vllm_engine_config = {
            "model": model_name,
            "disable_log_requests": True,
            "tensor_parallel_size": tensor_parallel_size,
            "gpu_memory_utilization": gpu_memory_utilization,
            "dtype": dtype,
            "max_model_len": max_model_len,
            "enforce_eager": True
        }

        logger.info(f"vLLM engine config: {vllm_engine_config}")

        # Create an AsyncLLMEngine from the config
        self.engine = AsyncLLMEngine.from_engine_args(
            AsyncEngineArgs(**vllm_engine_config)
        )

        logger.info("AsyncLLMEngine initialized successfully")

    async def stream_results(self, results_generator) -> AsyncGenerator[bytes, None]:
        num_returned = 0
        async for request_output in results_generator:
            text_outputs = [output.text for output in request_output.outputs]
            assert len(text_outputs) == 1
            text_output = text_outputs[0][num_returned:]
            ret = {"text": text_output}
            yield (json.dumps(ret) + "\n").encode("utf-8")
            num_returned += len(text_output)

    async def may_abort_request(self, request_id) -> None:
        await self.engine.abort(request_id)

    async def __call__(self, request: Request) -> Response:
        try:
            request_dict = await request.json()
        except json.JSONDecodeError:
            raise HTTPException(status_code=400, detail="Invalid JSON")

        prompt = request_dict.pop("prompt", None)
        if prompt is None:
            raise HTTPException(status_code=400, detail="Missing 'prompt' field")

        stream = request_dict.pop("stream", False)
        
        # Map request parameters to SamplingParams
        sampling_params = SamplingParams(
            max_tokens=request_dict.get("max_tokens", 16),
            temperature=request_dict.get("temperature", 1.0),
            top_p=request_dict.get("top_p", 1.0),
            top_k=request_dict.get("top_k", -1),
            presence_penalty=request_dict.get("presence_penalty", 0.0),
            frequency_penalty=request_dict.get("frequency_penalty", 0.0),
            stop=request_dict.get("stop", None),
            ignore_eos=request_dict.get("ignore_eos", False),
        )

        request_id = random_uuid()
        results_generator = self.engine.generate(prompt, sampling_params, request_id)

        if stream:
            background_tasks = BackgroundTasks()
            background_tasks.add_task(self.may_abort_request, request_id)
            return StreamingResponse(
                self.stream_results(results_generator), background=background_tasks
            )

        final_output = None
        async for request_output in results_generator:
            if await request.is_disconnected():
                await self.engine.abort(request_id)
                return Response(status_code=499)
            final_output = request_output

        assert final_output is not None
        prompt = final_output.prompt
        text_outputs = [prompt + output.text for output in final_output.outputs]
        ret = {"text": text_outputs}
        return Response(content=json.dumps(ret))

deployment = VLLMDeployment.bind()