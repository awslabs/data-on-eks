from typing import Dict, Optional, List

from fastapi import FastAPI

from vllm.entrypoints.openai.protocol import (
    ChatCompletionRequest,
    ChatCompletionResponse,
    ErrorResponse,
)
from vllm.entrypoints.openai.serving_chat import OpenAIServingChat
from vllm.entrypoints.openai.serving_engine import LoRAModulePath
from vllm.entrypoints.openai.serving_engine import BaseModelPath

import json
from typing import AsyncGenerator
from fastapi import BackgroundTasks
from starlette.requests import Request
from starlette.responses import StreamingResponse, Response, JSONResponse
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine
from vllm.sampling_params import SamplingParams
from vllm.utils import random_uuid


from ray import serve
import os
import logging

from huggingface_hub import login

# Environment and configuration setup
logger = logging.getLogger("ray.serve")

app = FastAPI()

@serve.deployment
@serve.ingress(app)
class VLLMDeployment:
    def __init__(self, **kwargs):
        hf_token = os.getenv("HUGGING_FACE_HUB_TOKEN")
        if not hf_token:
            raise ValueError("HUGGING_FACE_HUB_TOKEN environment variable is not set")
        login(token=hf_token)
        logger.info("Successfully logged in to Hugging Face Hub")

        args = AsyncEngineArgs(
            model=os.getenv("MODEL_ID", "mistralai/Mistral-7B-Instruct-v0.2"),  # Model identifier from Hugging Face Hub or local path.
            dtype="auto",  # Automatically determine the data type (e.g., float16 or float32) for model weights and computations.
            gpu_memory_utilization=float(os.getenv("GPU_MEMORY_UTILIZATION", "0.8")),  # Percentage of GPU memory to utilize, reserving some for overhead.
            max_model_len=int(os.getenv("MAX_MODEL_LEN", "4096")),  # Maximum sequence length (in tokens) the model can handle, including both input and output tokens.
            max_num_seqs=int(os.getenv("MAX_NUM_SEQ", "512")),  # Maximum number of sequences (requests) to process in parallel.
            max_num_batched_tokens=int(os.getenv("MAX_NUM_BATCHED_TOKENS", "32768")),  # Maximum number of tokens processed in a single batch across all sequences (max_model_len * max_num_seqs).
            trust_remote_code=True,  # Allow execution of untrusted code from the model repository (use with caution).
            enable_chunked_prefill=False,  # Disable chunked prefill to avoid compatibility issues with prefix caching.
            tokenizer_pool_size=4,  # Number of tokenizer instances to handle concurrent requests efficiently.
            tokenizer_pool_type="ray",  # Pool type for tokenizers; 'ray' uses Ray for distributed processing.
            # max_parallel_loading_workers=2,  # Number of parallel workers to load the model concurrently.
            pipeline_parallel_size=int(os.getenv("NUM_OF_NODES", "1")),  # Number of pipeline parallelism stages; typically set to 1 unless using model parallelism.
            tensor_parallel_size=int(os.getenv("NUM_OF_GPU", "1")),  # Number of tensor parallelism stages; typically set to 1 unless using model parallelism.
            enable_prefix_caching=True,  # Enable prefix caching to improve performance for similar prompt prefixes.
            enforce_eager=True,
            disable_log_requests=True
        )

        self.response_role = os.getenv("RESPONSE_ROLE", "assistant")
        self.engine_args = args
        self.engine = AsyncLLMEngine.from_engine_args(args)
        self.max_model_len = args.max_model_len
        self.openai_serving_chat = None
        logger.info(f"VLLM Engine initialized with max_model_len: {self.max_model_len}")

    @app.post("/v1/chat/completions")
    async def create_chat_completion(
        self, request: ChatCompletionRequest, raw_request: Request
    ):
        """OpenAI-compatible HTTP endpoint.

        API reference:
            - https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html
        """
        if not self.openai_serving_chat:
            model_config = await self.engine.get_model_config()
            # Determine the name of the served model for the OpenAI client.
            served_model_names = [BaseModelPath(name=self.engine_args.model, model_path=self.engine_args.model)]
            self.openai_serving_chat = OpenAIServingChat(
                self.engine,
                model_config,
                served_model_names,
                self.response_role,
                lora_modules=None,
                prompt_adapters=None,
                request_logger=None,
                chat_template=None,
            )
        logger.info(f"Request: {request}")
        generator = await self.openai_serving_chat.create_chat_completion(
            request, raw_request
        )
        if isinstance(generator, ErrorResponse):
            return JSONResponse(
                content=generator.model_dump(), status_code=generator.code
            )
        if request.stream:
            return StreamingResponse(content=generator, media_type="text/event-stream")
        else:
            assert isinstance(generator, ChatCompletionResponse)
            return JSONResponse(content=generator.model_dump())

deployment = VLLMDeployment.bind()
