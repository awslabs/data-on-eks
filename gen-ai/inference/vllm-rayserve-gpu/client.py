import requests
import os
import time
import logging

# Setup logging configuration
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants for model endpoint and service name
model_endpoint = os.getenv("MODEL_ENDPOINT", "/vllm")
service_name = os.getenv("SERVICE_NAME", "http://localhost:8000")

# Function to generate text
def generate_text(prompt):
    payload = {
        "prompt": prompt,
        "stream": False,
        "max_tokens": 2048,  # Increased to allow for longer responses
        "temperature": 0.7,  # Adjusted for balanced responses
        "top_p": 0.9,  # Adjusted for balanced responses
        "top_k": 50,  # Increased for more diversity in responses
        "stop": None
    }
    # Create the URL for the inference
    url = f"{service_name}{model_endpoint}"

    try:
        # Measure the start time
        start_time = time.time()

        # Send the request to the model service
        response = requests.post(url, json=payload, timeout=180)

        # Measure the end time
        end_time = time.time()
        latency = end_time - start_time

        if response.status_code == 200:
            # Get the response from the model
            response_data = response.json()
            text = response_data["text"][0].strip()
            return text, None
        else:
            # Print the error message
            logger.error(f"Failed to get response from model. Status code: {response.status_code}")
            logger.error(f"Error message: {response.text}")
            return None, latency
    except requests.exceptions.RequestException as e:
        # Handle any request exceptions (e.g., connection errors)
        logger.error(f"Request exception: {str(e)}")
        return f"Error: {str(e)}", None

# List of dynamic prompts
prompts = [
    "[INST] How big is the Observable Universe? [/INST] The observable universe is not a fixed size with a definitive boundary, but",
    "[INST] What is the speed of light? [/INST] The speed of light in a vacuum is a fundamental constant of nature,",
    "[INST] Explain the theory of relativity. [/INST] The theory of relativity, developed by Albert Einstein, is a fundamental theory in physics that describes the relationship between space and time,"
]

# Loop through the prompts and generate text
for prompt in prompts:
    response_text, latency = generate_text(prompt)
    print(f"Prompt: {prompt}")
    print(f"Response: {response_text}")
    if latency is not None:
        print(f"Latency: {latency:.2f} seconds")
    print("-" * 80)
