# This Python script demonstrates asynchronous communication with a Triton Inference Server using the tritonclient library.
# It is designed to send multiple prompts to the server, which processes them and returns the results asynchronously.

# -----------------------------
# Requirements:
# -----------------------------
# 1. Install Python 3.9.6 or later
# 2. tritonclient library installed with all its dependencies:
#   pip install tritonclient[all]

# -----------------------------
# Preparation before running the script:
# -----------------------------
# 1. Populate the 'prompts.txt' file with multiple prompts. Each prompt should be on a new line.
#    This file will be used as the input for making inferences.
# 2. Ensure that the Triton Inference Server is up and running and properly configured to process the requests.
# 3. Ensure Triton model deployment service is port-forward to local port 8001

# -----------------------------
# Execution:
# -----------------------------
# Run the script using the following command:
# python3 client.py

# -----------------------------
# Post-Execution:
# -----------------------------
# Check the 'results.txt' file in the same directory after running the script. This file will contain
# the processed outputs for each prompt sent to the inference server. The results are stored to allow
# easy verification of the outputs.

import argparse
import asyncio
import queue
import sys
from os import system
import json

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

    # Request parameters are not yet supported via BLS. Provide an
    # optional mechanism to send serialized parameters as an input
    # tensor until support is added

    if send_parameters_as_tensor:
        sampling_parameters_data = np.array(
            [json.dumps(sampling_parameters).encode("utf-8")], dtype=np.object_
        )
        inputs.append(grpcclient.InferInput("SAMPLING_PARAMETERS", [1], "BYTES"))
        inputs[-1].set_data_from_numpy(sampling_parameters_data)

    # Add requested outputs
    outputs = []
    outputs.append(grpcclient.InferRequestedOutput("TEXT"))

    # Issue the asynchronous sequence inference.
    return {
        "model_name": model_name,
        "inputs": inputs,
        "outputs": outputs,
        "request_id": str(request_id),
        "parameters": sampling_parameters
    }


async def main(FLAGS):
    model_name = "vllm"
    sampling_parameters = {"temperature": "0.01", "top_p": "1.0", "top_k": 20, "max_tokens": 512}
    stream = FLAGS.streaming_mode
    with open(FLAGS.input_prompts, "r") as file:
        print(f"Loading inputs from `{FLAGS.input_prompts}`...")
        prompts = file.readlines()

    results_dict = {}

    async with grpcclient.InferenceServerClient(
            url=FLAGS.url, verbose=FLAGS.verbose
    ) as triton_client:
        # Request iterator that yields the next request
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
                print(f"caught error in request iterator:  {error}")

        try:
            # Start streaming
            response_iterator = triton_client.stream_infer(
                inputs_iterator=async_request_iterator(),
                stream_timeout=FLAGS.stream_timeout,
            )
            # Read response from the stream
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
    FLAGS = parser.parse_args()
    asyncio.run(main(FLAGS))
