import requests

# Define the URL of your FastAPI application
url = "http://localhost:8001/generate"  # Adjust the URL if needed

# Define a function to send a prompt and sampling parameters
def send_request(prompt, sampling_params):
    # Prepare the payload
    payload = {
        "prompt": prompt,
        "sampling_params": sampling_params
    }
    
    # Send the POST request
    response = requests.post(url, json=payload)
    
    # Print the response
    if response.status_code == 200:
        print("Response:", response.json())
    else:
        print(f"Error {response.status_code}: {response.text}")

# Define your test prompts and sampling parameters
test_prompt = "What is the capital city of France"
test_sampling_params = {
    "temperature": 0.7,
    "top_p": 0.9
}

# Send a test request
send_request(test_prompt, test_sampling_params)
