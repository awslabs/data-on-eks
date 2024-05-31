# kubectl -n vllm-llama2 port-forward svc/nvidia-triton-server-triton-inference-server 8001:8001

# python3 triton-client.py --model-name mistral7b --input-prompts prompts.txt --results-file mistral_results.txt

# python3 triton-client.py --model-name llama2 --input-prompts prompts.txt --results-file llama2_results.txt

import argparse
import asyncio
import json
import sys
from os import system

import numpy as np
import tritonclient.grpc.aio as grpcclient
from tritonclient.utils import *


def create_request(prompt, stream, request_id, sampling_parameters, model_name, send_parameters_as_tensor=True):
    inputs = []
    prompt_data = np.array([prompt.encode("utf-8")], dtype=np.object_)
    try:
        inputs.append(grpcclient.InferInput("PROMPT", [1], "BYTES"))
        inputs[-1].set_data_from_numpy(prompt_data)
    except Exception as e:
        print(f"Encountered an error {e}")

    stream_data = np.array([stream], dtype=bool)
    inputs.append(grpcclient.InferInput("STREAM", [1], "BOOL"))
    inputs[-1].set_data_from_numpy(stream_data)

    if send_parameters_as_tensor:
        sampling_parameters_data = np.array(
            [json.dumps(sampling_parameters).encode("utf-8")], dtype=np.object_
        )
        inputs.append(grpcclient.InferInput("SAMPLING_PARAMETERS", [1], "BYTES"))
        inputs[-1].set_data_from_numpy(sampling_parameters_data)

    outputs = []
    outputs.append(grpcclient.InferRequestedOutput("TEXT"))

    return {
        "model_name": model_name,
        "inputs": inputs,
        "outputs": outputs,
        "request_id": str(request_id),
        "parameters": sampling_parameters
    }


async def main(FLAGS):
    sampling_parameters = {"temperature": "0.01", "top_p": "1.0", "top_k": 20, "max_tokens": 512}
    stream = FLAGS.streaming_mode
    model_name = FLAGS.model_name
    with open(FLAGS.input_prompts, "r") as file:
        print(f"Loading inputs from `{FLAGS.input_prompts}`...")
        prompts = file.readlines()

    results_dict = {}

    async with grpcclient.InferenceServerClient(
            url=FLAGS.url, verbose=FLAGS.verbose
    ) as triton_client:
        async def async_request_iterator():
            try:
                for iter in range(FLAGS.iterations):
                    for i, prompt in enumerate(prompts):
                        prompt_id = FLAGS.offset + (len(prompts) * iter) + i
                        results_dict[str(prompt_id)] = []
                        SYSTEM_PROMPT = """<<SYS>>\nKeep short answers of no more than 100 sentences.\n<</SYS>>\n\n"""
                        prompt = "<s>[INST]" + SYSTEM_PROMPT + prompt + "[/INST]"
                        yield create_request(
                            prompt, stream, prompt_id, sampling_parameters, model_name
                        )
            except Exception as error:
                print(f"caught error in request iterator: {error}")

        try:
            response_iterator = triton_client.stream_infer(
                inputs_iterator=async_request_iterator(),
                stream_timeout=FLAGS.stream_timeout,
            )
            async for response in response_iterator:
                result, error = response
                if error:
                    print(f"Encountered error while processing: {error}")
                else:
                    output = result.as_numpy("TEXT")
                    for i in output:
                        results_dict[result.get_response().id].append(i)

        except InferenceServerException as error:
            print(error)
            sys.exit(1)

    with open(FLAGS.results_file, "w") as file:
        for id in results_dict.keys():
            for result in results_dict[id]:
                file.write(result.decode("utf-8"))
                file.write("\n")
            file.write("\n=========\n\n")
        print(f"Storing results into `{FLAGS.results_file}`...")

    if FLAGS.verbose:
        print(f"\nContents of `{FLAGS.results_file}` ===>")
        system(f"cat {FLAGS.results_file}")

    print("PASS: vLLM example")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        required=False,
        default=False,
        help="Enable verbose output",
    )
    parser.add_argument(
        "-u",
        "--url",
        type=str,
        required=False,
        default="localhost:8001",
        help="Inference server URL and it gRPC port. Default is localhost:8001.",
    )
    parser.add_argument(
        "-t",
        "--stream-timeout",
        type=float,
        required=False,
        default=None,
        help="Stream timeout in seconds. Default is None.",
    )
    parser.add_argument(
        "--offset",
        type=int,
        required=False,
        default=0,
        help="Add offset to request IDs used",
    )
    parser.add_argument(
        "--input-prompts",
        type=str,
        required=False,
        default="prompts.txt",
        help="Text file with input prompts",
    )
    parser.add_argument(
        "--results-file",
        type=str,
        required=False,
        default="results.txt",
        help="The file with output results",
    )
    parser.add_argument(
        "--iterations",
        type=int,
        required=False,
        default=1,
        help="Number of iterations through the prompts file",
    )
    parser.add_argument(
        "-s",
        "--streaming-mode",
        action="store_true",
        required=False,
        default=False,
        help="Enable streaming mode",
    )
    parser.add_argument(
        "--model-name",
        type=str,
        required=True,
        help="Name of the model to test",
    )
    FLAGS = parser.parse_args()
    asyncio.run(main(FLAGS))
