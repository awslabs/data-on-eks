import gradio as gr
import tritonclient.http as httpclient
from yolo_inference import infer

url = "localhost:8000"

def remote_inference(image):
    client = httpclient.InferenceServerClient(url=url)
    return infer(image, client)

demo = gr.Interface(remote_inference, gr.Image(), "image")
demo.launch()
