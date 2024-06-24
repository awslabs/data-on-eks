import requests
import os


# Constants for model endpoint and service name
model_endpoint = os.getenv("MODEL_ENDPOINT", "/vllm")
service_name = os.getenv("SERVICE_NAME", "http://localhost:8001")

# Function to generate text
def generate_text(message, history):
    prompt = message
    # prompt = "How big is the universe"
    # payload = {
    #     "prompt": prompt
    # }
    # Create the URL for the inference
    url = f"{service_name}{model_endpoint}"

    try:
        # Send the request to the model service
        response = requests.post(url, json={"prompt": prompt}, timeout=180)
        # print(response.text)
        if response.status_code == 200:
        # Print the response from the model
          print("Response from model:", response.json())
        else:
        # Print the error message
          print("Failed to get response from model. Status code:", response.status_code)
          print("Error message:", response.text)
        response.raise_for_status()  # Raise an exception for HTTP errors
        prompt_to_replace = "[INST]" + prompt + "[/INST]"

        # Removing the original prompt with instruction set from the output
        text = response.text.replace(prompt_to_replace, "", 1).strip('["]?\n')
        # remove '<s>' strikethrough markdown
        if text.startswith("<s>"):
            text = text.replace("<s>", "", 1)

        text = text.replace("</s>", "", 1)


        # Safety filter to remove harmful or inappropriate content
        # answer_only = filter_harmful_content(answer_only)
        return text
    except requests.exceptions.RequestException as e:
        # Handle any request exceptions (e.g., connection errors)
        return f" :Error: {str(e)}"

print(generate_text("<s>[INST] What is your favourite condiment? [/INST]", []))