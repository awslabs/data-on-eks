"""
Example of a vLLM prompt completion service based on the Falcon-7b LLM
to get deployed on Ray Serve.

Adapted from the AnyScale team's repository
https://github.com/ray-project/ray/blob\
/cc983fc3e64c1ba215e981a43dd0119c03c74ff1/doc/source/serve/doc_code/vllm_example.py
"""

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

import huggingface_hub

# Environment and configuration setup
huggingface_hub.login(token=os.environ.get('HUGGING_FACE_TOKEN', ''))
logger = logging.getLogger("ray.serve")

@serve.deployment(name="mistral-deployment", ray_actor_options={"num_gpus": 1}, route_prefix="/")
class VLLMDeployment:
    def __init__(self, **kwargs):
        """
        Construct a VLLM deployment.

        Refer to https://github.com/vllm-project/vllm/blob/main/vllm/engine/arg_utils.py
        for the full list of arguments.

        Args:
            model: name or path of the huggingface model to use
            download_dir: directory to download and load the weights,
                default to the default cache dir of huggingface.
            use_np_weights: save a numpy copy of model weights for
                faster loading. This can increase the disk usage by up to 2x.
            use_dummy_weights: use dummy values for model weights.
            dtype: data type for model weights and activations.
                The "auto" option will use FP16 precision
                for FP32 and FP16 models, and BF16 precision.
                for BF16 models.
            seed: random seed.
            worker_use_ray: use Ray for distributed serving, will be
                automatically set when using more than 1 GPU
            pipeline_parallel_size: number of pipeline stages.
            tensor_parallel_size: number of tensor parallel replicas.
            block_size: token block size.
            swap_space: CPU swap space size (GiB) per GPU.
            gpu_memory_utilization: the percentage of GPU memory to be used for
                the model executor
            max_num_batched_tokens: maximum number of batched tokens per iteration
            max_num_seqs: maximum number of sequences per iteration.
            disable_log_stats: disable logging statistics.
            engine_use_ray: use Ray to start the LLM engine in a separate
                process as the server process.
            disable_log_requests: disable logging requests.
        """
        vllm_engine_config = {
            "model": "mistralai/Mistral-7B-Instruct-v0.2",
            "disable_log_requests": "true",
            "tensor_parallel_size": int(os.environ.get('tensor_parallel_size',1)),
            "gpu_memory_utilization": float(os.environ.get('gpu_memory_utilization', '0.8')),
            "dtype": os.environ.get('dtype', 'auto'),
            "max_model_len": int(os.environ.get('max_model_len', 4096)),
            "enforce_eager": True
        }

        # args = AsyncEngineArgs(**kwargs)
        # self.engine = AsyncLLMEngine.from_engine_args(args)

        # Create an AsyncLLMEngine from the config from JSON
        self.llm_engine = AsyncLLMEngine.from_engine_args(
            AsyncEngineArgs(**vllm_engine_config)
        )

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
        sampling_params = SamplingParams(**request_dict)
        request_id = random_uuid()
        results_generator = self.engine.generate(prompt, sampling_params, request_id)
        if stream:
            background_tasks = BackgroundTasks()
            # Using background_taks to abort the the request
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


# Deployment definition for Ray Serve
deployment = VLLMDeployment.bind(model="mistralai/Mistral-7B-Instruct-v0.2",
                                    dtype="bfloat16",
                                    trust_remote_code=True,
                                    )
