import json
from typing import AsyncGenerator
from fastapi import BackgroundTasks
from starlette.requests import Request
from starlette.responses import StreamingResponse, Response
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

@serve.deployment(name="mistral-deployment", route_prefix="/vllm",
    ray_actor_options={"num_gpus": 1},
    autoscaling_config={"min_replicas": 1, "max_replicas": 2},
)
class VLLMDeployment:
    def __init__(self, **kwargs):
        hf_token = os.getenv("HUGGING_FACE_HUB_TOKEN")
        logger.info(f"token: {hf_token=}")
        if not hf_token:
            raise ValueError("HUGGING_FACE_HUB_TOKEN environment variable is not set")
        login(token=hf_token)
        logger.info(f"login to HF success")


        args = AsyncEngineArgs(
            model=os.getenv("MODEL_ID", "mistralai/Mistral-7B-Instruct-v0.2"),
            dtype="auto",
            max_model_len=int(os.getenv("MAX_MODEL_LEN", "4096")),
            gpu_memory_utilization=float(os.getenv("GPU_MEMORY_UTILIZATION", "0.8")),
            max_num_seqs=int(os.getenv("MAX_NUM_SEQ", "512")),
            trust_remote_code=True,
        )
        self.engine = AsyncLLMEngine.from_engine_args(args)

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
        """Generate completion for the request.

        The request should be a JSON object with the following fields:
        - prompt: the prompt to use for the generation.
        - stream: whether to stream the results or not.
        - other fields: the sampling parameters (See `SamplingParams` for details).
        """
        request_dict = await request.json()
        prompt = request_dict.pop("prompt")
        stream = request_dict.pop("stream", False)
        # sampling_params = SamplingParams(**request_dict)

        sampling_params = SamplingParams(
            max_tokens=request_dict.get("max_tokens", 2048),  # Default to 2048 if not specified
            temperature=request_dict.get("temperature", 0.7),
            top_p=request_dict.get("top_p", 0.9),
            top_k=request_dict.get("top_k", 50),
            stop=request_dict.get("stop", None),
        )

        request_id = random_uuid()
        results_generator = self.engine.generate(prompt, sampling_params, request_id)
        if stream:
            background_tasks = BackgroundTasks()
            # Using background_tasks to abort the request
            # if the client disconnects.
            background_tasks.add_task(self.may_abort_request, request_id)
            return StreamingResponse(
                self.stream_results(results_generator), background=background_tasks
            )

        # Non-streaming case
        final_output = None
        async for request_output in results_generator:
            if await request.is_disconnected():
                # Abort the request if the client disconnects.
                await self.engine.abort(request_id)
                return Response(status_code=499)
            final_output = request_output

        assert final_output is not None
        prompt = final_output.prompt
        text_outputs = [prompt + output.text for output in final_output.outputs]
        ret = {"text": text_outputs}
        return Response(content=json.dumps(ret))


deployment = VLLMDeployment.bind()
