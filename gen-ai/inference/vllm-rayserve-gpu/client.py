import aiohttp
import asyncio
import os
import time
import logging
import csv
from uuid import uuid4 as random_uuid
import json

# Setup logging configuration
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants for model endpoint and service name
model_endpoint = os.getenv("MODEL_ENDPOINT", "/vllm")
service_name = os.getenv("SERVICE_NAME", "http://localhost:8000")

# Function to count tokens in a response
def count_tokens(text):
    return len(text.split())

# Function to generate text asynchronously
async def generate_text(session, prompt):
    SYSTEM_PROMPT = """<<SYS>>\nKeep short answers of no more than 100 sentences.\n<</SYS>>\n\n"""
    payload = {
        "prompt": "<s>[INST]" + SYSTEM_PROMPT + prompt + "[/INST]",
        "stream": False,
        "max_tokens": 512,  # Increased to allow for longer responses
        "temperature": 0.01,  # Adjusted for balanced responses
        "top_p": 1,  # Adjusted for balanced responses
        "top_k": 20,  # Increased for more diversity in responses
        "stop": None
    }
    # Create the URL for the inference
    url = f"{service_name}{model_endpoint}"

    try:
        # Measure the start time for the inference
        start_time = time.perf_counter()

        # Send the request to the model service
        async with session.post(url, json=payload, timeout=180) as response:
            # Measure the end time for the inference
            end_time = time.perf_counter()
            latency = end_time - start_time

            # Log response status and content type
            logger.info(f"Response status: {response.status}")

            if response.status == 200:
                if response.content_type == 'application/json':
                    response_data = await response.json()
                elif response.content_type == 'application/octet-stream':
                    response_data = await response.read()
                    response_data = response_data.decode('utf-8')
                    response_data = json.loads(response_data)
                else:
                    logger.error(f"Unexpected content type: {response.content_type}")
                    return None, latency, 0

                text = response_data["text"][0].strip()
                num_tokens = count_tokens(text)
                return text, latency, num_tokens
            else:
                # Print the error message
                logger.error(f"Failed to get response from model. Status code: {response.status}")
                logger.error(f"Error message: {await response.text()}")
                return None, latency, 0
    except aiohttp.ClientError as e:
        # Handle any request exceptions (e.g., connection errors)
        logger.error(f"Request exception: {str(e)}")
        return None, None, 0

# Function to warm up the model
async def warmup(session):
    """Warm up the model to reduce cold start latency."""
    prompt = "Warmup"
    payload = {
        "prompt": prompt,
        "stream": False,
        "max_tokens": 1,
        "temperature": 0.7,
        "top_p": 0.9,
        "top_k": 50,
        "stop": None
    }
    url = f"{service_name}{model_endpoint}"

    try:
        # Send the warm-up request to the model service
        async with session.post(url, json=payload, timeout=180) as response:
            if response.status == 200:
                logger.info("Warm-up successful")
            else:
                logger.error(f"Failed to warm up model. Status code: {response.status}")
                logger.error(f"Error message: {await response.text()}")
    except aiohttp.ClientError as e:
        logger.error(f"Warm-up request exception: {str(e)}")

# Function to read prompts from a file
def read_prompts(file_path):
    with open(file_path, 'r') as file:
        return [line.strip() for line in file.readlines()]

# Function to write results to a file
def write_results(file_path, results, summary):
    with open(file_path, 'w') as file:
        # Write each request and response with detailed information
        for result in results:
            prompt, latency, response_text, num_tokens = result
            file.write(f"Prompt: {prompt}\n")
            file.write(f"Response Time: {latency:.2f} seconds\n")
            file.write(f"Token Length: {num_tokens}\n")
            file.write(f"Response: {response_text}\n")
            file.write("=" * 80 + "\n")

        # Write summary
        file.write("\nSummary of Latency:\n")
        file.write("Total Prompts: {}\n".format(len(results)))
        file.write("Average Latency: {:.2f} seconds\n".format(summary['average_latency']))
        file.write("Max Latency: {:.2f} seconds\n".format(summary['max_latency']))
        file.write("Min Latency: {:.2f} seconds\n".format(summary['min_latency']))

# Main function to handle asynchronous execution
async def main():
    prompts = read_prompts('prompts.txt')

    # List to store results
    results = []

    total_latency = 0
    max_latency = float('-inf')
    min_latency = float('inf')

    async with aiohttp.ClientSession() as session:
        # Warm up the model
        await warmup(session)

        tasks = [generate_text(session, prompt) for prompt in prompts]
        responses = await asyncio.gather(*tasks)

        for prompt, (response_text, latency, num_tokens) in zip(prompts, responses):
            if latency is not None:
                results.append([prompt, latency, response_text, num_tokens])
                total_latency += latency
                max_latency = max(max_latency, latency)
                min_latency = min(min_latency, latency)
                print(f"Prompt: {prompt}")
                print(f"Response Time: {latency:.2f} seconds")
                print(f"Token Length: {num_tokens}")
                print("=" * 80)
            else:
                results.append([prompt, "N/A", response_text, 0])
                print(f"Prompt: {prompt}")
                print(f"Response Time: N/A")
                print(f"Token Length: 0")
                print("=" * 80)

    # Calculate summary
    valid_latencies = [r[1] for r in results if isinstance(r[1], float)]
    if valid_latencies:
        summary = {
            'average_latency': sum(valid_latencies) / len(valid_latencies),
            'max_latency': max(valid_latencies),
            'min_latency': min(valid_latencies)
        }

        # Write results and summary to the local file
        write_results('results.txt', results, summary)

# Run the main function
if __name__ == "__main__":
    asyncio.run(main())
