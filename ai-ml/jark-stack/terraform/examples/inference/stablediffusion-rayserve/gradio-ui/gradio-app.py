import gradio as gr
import requests
import os
from PIL import Image
from io import BytesIO

# Constants for model endpoint and service name
model_endpoint = os.environ.get("MODEL_ENDPOINT", "/imagine")
service_name = os.environ.get("SERVICE_NAME", "http://localhost:8000")

# Function to generate image based on prompt
def generate_image(prompt):

    # Create the URL for the inference
    url = f"{service_name}{model_endpoint}"

    try:
        # Send the request to the model service
        response = requests.get(url, params={"prompt": prompt}, timeout=180)
        response.raise_for_status()  # Raise an exception for HTTP errors
        i = Image.open(BytesIO(response.content))
        return i

    except requests.exceptions.RequestException as e:
        # Handle any request exceptions (e.g., connection errors)
        # return f"AI: Error: {str(e)}"
        return Image.new('RGB', (100, 100), color='red')

# Define the Gradio PromptInterface
demo = gr.Interface(fn=generate_image,
                    inputs = [gr.Textbox(label="Enter the Prompt")],
                    outputs = gr.Image(type='pil')).launch(server_name="0.0.0.0")
