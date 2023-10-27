import gradio as gr
import requests

# Constants for model endpoint and service name
model_endpoint = "/infer"
# service_name = "http://<REPLACE_ME_WITH_ELB_DNS_NAME>/serve"
service_name = "http://localhost:8000"  # Replace with your actual service name


# Function to generate text
def text_generation(message, history):
    prompt = message

    # Create the URL for the inference
    url = f"{service_name}{model_endpoint}"

    try:
        # Send the request to the model service
        response = requests.get(url, params={"sentence": prompt}, timeout=180)
        response.raise_for_status()  # Raise an exception for HTTP errors

        full_output = response.text
        # Removing the original question from the output
        answer_only = full_output.replace(prompt, "", 1).strip('["]?\n')

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
    text_generation,
    chatbot=gr.Chatbot(line_breaks=True),
    textbox=gr.Textbox(placeholder="Ask me a question", container=False, scale=7),
    title="Llama2 AI Chat",
    description="Ask me any question",
    theme="soft",
    examples=["How many languages are in India", "What is Generative AI?"],
    cache_examples=True,
    retry_btn=None,
    undo_btn="Delete Previous",
    clear_btn="Clear",
)

# Launch the ChatInterface
chat_interface.launch()
