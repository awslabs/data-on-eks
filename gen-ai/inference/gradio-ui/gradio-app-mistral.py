import gradio as gr
import requests
import os


# Constants for model endpoint and service name
model_endpoint = os.environ.get("MODEL_ENDPOINT", "/infer")
service_name = os.environ.get("SERVICE_NAME", "http://localhost:8000")

# Function to generate text
def generate_text(message, history):
    prompt = message

    # Create the URL for the inference
    url = f"{service_name}{model_endpoint}"

    try:
        # Send the request to the model service
        response = requests.get(url, params={"sentence": prompt}, timeout=180)
        response.raise_for_status()  # Raise an exception for HTTP errors
        prompt_to_replace = "[INST]" + prompt + "[/INST]"

        # Removing the original prompt with instruction set from the output
        text = response.text.replace(prompt_to_replace, "", 1).strip('["]?\n')
        # remove '<s>' strikethrough markdown
        if text.startswith("<s>"):
            text = text.replace("<s>", "", 1)

        text = text.replace("</s>", "", 1)

        answer_only = text

        # Safety filter to remove harmful or inappropriate content
        answer_only = filter_harmful_content(answer_only)
        return answer_only
    except requests.exceptions.RequestException as e:
        # Handle any request exceptions (e.g., connection errors)
        return f"AI: Error: {str(e)}"


# Define the safety filter function (you can implement this as needed)
def filter_harmful_content(text):
    # TODO: Implement a safety filter to remove any harmful or inappropriate content from the text

    # For now, simply return the text as-is
    return text


# Define the Gradio ChatInterface
chat_interface = gr.ChatInterface(
    generate_text,
    chatbot=gr.Chatbot(height=300),
    textbox=gr.Textbox(placeholder="Ask me a question", container=False, scale=7),
    title="Mistral AI Chat",
    description="Ask me any question",
    theme="soft",
    examples=["How Big Is Observable Universe", "How to kill a linux process"],
    cache_examples=False,
    retry_btn=None,
    undo_btn="Delete Previous",
    clear_btn="Clear",
)

# Launch the ChatInterface
chat_interface.launch()
