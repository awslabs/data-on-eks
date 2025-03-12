import argparse
import asyncio
import time
from os import system

import openai


async def generate(client, prompt, sampling_parameters):
    try:
        response = await client.chat.completions.create(
            model=FLAGS.model_name,
            messages=[
                {
                    "role": "system",
                    "content": "Keep short answers of no more than 100 sentences.",
                },
                {"role": "user", "content": prompt},
            ],
            max_tokens=sampling_parameters["max_tokens"],
            temperature=float(sampling_parameters["temperature"]),
            top_p=float(sampling_parameters["top_p"]),
            n=1,
            stream=False,
        )
        return response.choices[0].message.content
    except Exception as e:
        print(f"Error in generate function: {e}")
        return None


async def process_prompt(client, prompt, prompt_id, sampling_parameters, results_dict):
    start_time = time.time()
    response = await generate(client, prompt.strip(), sampling_parameters)
    end_time = time.time()

    if response:
        results_dict[str(prompt_id)].append(response.encode("utf-8"))
        duration = end_time - start_time
        duration_ms = duration * 1000
        print(
            f"Model {FLAGS.model_name} - Request {prompt_id}: {duration:.2f}s ({duration_ms:.2f}ms)"
        )
        return end_time - start_time
    else:
        print(f"Error processing prompt {prompt_id}")
        return 0


async def main(FLAGS):
    start = time.time()
    sampling_parameters = {
        "temperature": "0.01",
        "top_p": "1.0",
        "top_k": 20,
        "max_tokens": 512,
    }
    client = openai.AsyncOpenAI(
        base_url=FLAGS.url,
        api_key="not_used_for_self_host",  # To avoid report OPENAI_API_KEY missing
    )
    with open(FLAGS.input_prompts, "r") as file:
        print(f"Loading inputs from `{FLAGS.input_prompts}`...")
        prompts = file.readlines()

    results_dict = {}
    total_time_sec = 0

    for iter in range(FLAGS.iterations):
        tasks = []
        for i, prompt in enumerate(prompts):
            prompt_id = FLAGS.offset + (len(prompts) * iter) + i
            results_dict[str(prompt_id)] = []
            task = process_prompt(
                client, prompt, prompt_id, sampling_parameters, results_dict
            )
            tasks.append(task)

        times = await asyncio.gather(*tasks)
        total_time_sec += sum(times)

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

    total_time_ms = total_time_sec * 1000
    print(
        f"Accumulated time for all requests: {total_time_sec:.2f} seconds ({total_time_ms:.2f} milliseconds)"
    )
    print("PASS: NVIDIA NIM example")
    end = time.time()
    actual_duration = end - start
    actual_duration_ms = end - start
    print(
        f"Actual execution time used with concurrency {len(tasks)} is: {actual_duration:.2f} seconds ({actual_duration_ms:.2f} milliseconds)"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-u",
        "--url",
        type=str,
        required=False,
        default="http://localhost:8000/v1",
        help="Inference server URL. Default is http://localhost:8000/v1 ",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        required=False,
        default=False,
        help="Enable verbose output",
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
        "--model-name",
        type=str,
        required=False,
        default="meta/llama3-8b-instruct",
        help="Name of the model to test",
    )
    FLAGS = parser.parse_args()
    asyncio.run(main(FLAGS))
