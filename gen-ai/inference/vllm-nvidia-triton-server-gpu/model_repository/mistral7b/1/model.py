# Reference from https://github.com/triton-inference-server/vllm_backend

import asyncio
import json
import os
import threading
from typing import AsyncGenerator

import numpy as np
import triton_python_backend_utils as pb_utils
from vllm import SamplingParams
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine
from vllm.utils import random_uuid
import huggingface_hub

# Environment and configuration setup
_VLLM_ENGINE_ARGS_FILENAME = "vllm_engine_args.json"
huggingface_hub.login(token=os.environ.get("HUGGING_FACE_TOKEN", ""))


class TritonPythonModel:
    # initialize method sets up the model configuration, initializes the vLLM engine with the provided parameters,
    # and starts an asynchronous event loop to process requests.
    def initialize(self, args):
        self.logger = pb_utils.Logger
        self.model_config = json.loads(args["model_config"])

        # assert are in decoupled mode. Currently, Triton needs to use
        # decoupled policy for asynchronously forwarding requests to
        # vLLM engine.
        self.using_decoupled = pb_utils.using_decoupled_model_transaction_policy(
            self.model_config
        )
        assert (
            self.using_decoupled
        ), "vLLM Triton backend must be configured to use decoupled model transaction policy"

        # Load engine arguments from the model repository
        engine_args_filepath = os.path.join(
            args["model_repository"], _VLLM_ENGINE_ARGS_FILENAME
        )

        # GPU ID
        gpu_id = args.get("model_instance_device_id", "0")
        os.environ["CUDA_VISIBLE_DEVICES"] = gpu_id

        vllm_engine_config = {
            "model": "mistralai/Mistral-7B-Instruct-v0.2",
            "disable_log_requests": "true",
            "tensor_parallel_size": int(os.environ.get("tensor_parallel_size", 1)),
            "gpu_memory_utilization": float(
                os.environ.get("gpu_memory_utilization", "0.8")
            ),
            "dtype": os.environ.get("dtype", "auto"),
            "max_model_len": int(os.environ.get("max_model_len", 4096)),
            "enforce_eager": True,
        }

        # Create an AsyncLLMEngine from the config from JSON
        self.llm_engine = AsyncLLMEngine.from_engine_args(
            AsyncEngineArgs(**vllm_engine_config)
        )

        output_config = pb_utils.get_output_config_by_name(self.model_config, "TEXT")
        self.output_dtype = pb_utils.triton_string_to_numpy(output_config["data_type"])

        # Counter to keep track of ongoing request counts
        self.ongoing_request_count = 0

        # Starting asyncio event loop to process the received requests asynchronously.
        self._loop = asyncio.get_event_loop()
        self._loop_thread = threading.Thread(
            target=self.engine_loop, args=(self._loop,)
        )
        self._shutdown_event = asyncio.Event()
        self._loop_thread.start()

    def create_task(self, coro):
        """
        The create_task method schedules asynchronous tasks on the
        event loop running in a separate thread.
        """
        assert (
            self._shutdown_event.is_set() is False
        ), "Cannot create tasks after shutdown has been requested"

        return asyncio.run_coroutine_threadsafe(coro, self._loop)

    def engine_loop(self, loop):
        """
        Runs the engine's event loop on a separate thread.
        """
        asyncio.set_event_loop(loop)
        self._loop.run_until_complete(self.await_shutdown())

    async def await_shutdown(self):
        """
        Primary coroutine running on the engine event loop. This coroutine is responsible for
        keeping the engine alive until a shutdown is requested.
        """
        # first await the shutdown signal
        while self._shutdown_event.is_set() is False:
            await asyncio.sleep(5)

        # Wait for the ongoing_requests
        while self.ongoing_request_count > 0:
            self.logger.log_info(
                "Awaiting remaining {} requests".format(self.ongoing_request_count)
            )
            await asyncio.sleep(5)

        self.logger.log_info("Shutdown complete")

    def get_sampling_params_dict(self, params_json):
        """
        This functions parses the dictionary values into their
        expected format.
        """

        params_dict = json.loads(params_json)

        # Special parsing for the supported sampling parameters
        bool_keys = ["ignore_eos", "skip_special_tokens", "use_beam_search"]
        for k in bool_keys:
            if k in params_dict:
                params_dict[k] = bool(params_dict[k])

        float_keys = [
            "frequency_penalty",
            "length_penalty",
            "presence_penalty",
            "temperature",
            "top_p",
        ]
        for k in float_keys:
            if k in params_dict:
                params_dict[k] = float(params_dict[k])

        int_keys = ["best_of", "max_tokens", "n", "top_k"]
        for k in int_keys:
            if k in params_dict:
                params_dict[k] = int(params_dict[k])

        return params_dict

    def create_response(self, vllm_output):
        """
        Responses are created using the create_response
        method and sent back to Triton.
        """
        prompt = vllm_output.prompt
        text_outputs = [
            (prompt + output.text).encode("utf-8") for output in vllm_output.outputs
        ]
        triton_output_tensor = pb_utils.Tensor(
            "TEXT", np.asarray(text_outputs, dtype=self.output_dtype)
        )
        return pb_utils.InferenceResponse(output_tensors=[triton_output_tensor])

    async def generate(self, request):
        """
        Generate method forwards the input prompt to the
        vLLM engine and collects the output.
        """
        response_sender = request.get_response_sender()
        self.ongoing_request_count += 1
        try:
            request_id = random_uuid()
            prompt = pb_utils.get_input_tensor_by_name(request, "PROMPT").as_numpy()[0]
            if isinstance(prompt, bytes):
                prompt = prompt.decode("utf-8")
            stream = pb_utils.get_input_tensor_by_name(request, "STREAM").as_numpy()[0]

            parameters_input_tensor = pb_utils.get_input_tensor_by_name(
                request, "SAMPLING_PARAMETERS"
            )
            if parameters_input_tensor:
                parameters = parameters_input_tensor.as_numpy()[0].decode("utf-8")
            else:
                parameters = request.parameters()

            sampling_params_dict = self.get_sampling_params_dict(parameters)
            sampling_params = SamplingParams(**sampling_params_dict)

            last_output = None
            async for output in self.llm_engine.generate(
                prompt, sampling_params, request_id
            ):
                if stream:
                    response_sender.send(self.create_response(output))
                else:
                    last_output = output

            if not stream:
                response_sender.send(self.create_response(last_output))

        except Exception as e:
            self.logger.log_info(f"Error generating stream: {e}")
            error = pb_utils.TritonError(f"Error generating stream: {e}")
            triton_output_tensor = pb_utils.Tensor(
                "TEXT", np.asarray(["N/A"], dtype=self.output_dtype)
            )
            response = pb_utils.InferenceResponse(
                output_tensors=[triton_output_tensor], error=error
            )
            response_sender.send(response)
            raise e
        finally:
            response_sender.send(flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL)
            self.ongoing_request_count -= 1

    def execute(self, requests):
        """
        Triton core issues requests to the backend via this method.

        When this method returns, new requests can be issued to the backend. Blocking
        this function would prevent the backend from pulling additional requests from
        Triton into the vLLM engine. This can be done if the kv cache within vLLM engine
        is too loaded.
        We are pushing all the requests on mistral7b and let it handle the full traffic.
        """
        for request in requests:
            self.create_task(self.generate(request))
        return None

    def finalize(self):
        """
        Triton virtual method; called when the model is unloaded.
        """
        self.logger.log_info("Issuing finalize to mistral7b backend")
        self._shutdown_event.set()
        if self._loop_thread is not None:
            self._loop_thread.join()
            self._loop_thread = None
