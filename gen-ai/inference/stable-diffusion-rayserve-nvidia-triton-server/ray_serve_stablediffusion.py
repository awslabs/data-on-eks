from io import BytesIO
import numpy
import tritonserver
from fastapi import FastAPI
from PIL import Image
from ray import serve
from fastapi.responses import Response
import os

app = FastAPI()

@serve.deployment(name="stable-diffusion-nvidia-triton-server", ray_actor_options={"num_gpus": 1})
@serve.ingress(app)
class TritonDeployment:
    def __init__(self):
        self._triton_server = tritonserver

        model_repository = [os.getenv('MODEL_REPOSITORY')]

        self._triton_server = tritonserver.Server(
            model_repository=model_repository,
            model_control_mode=tritonserver.ModelControlMode.EXPLICIT,
            log_info=False,
        )
        self._triton_server.start(wait_until_ready=True)

    @app.get("/imagine")
    def generate(self, prompt: str, filename: str = "generated_image.jpg") -> None:
        print("call done")
        if not self._triton_server.model("stable_diffusion").ready():
            try:
                self._triton_server.load("text_encoder")
                self._triton_server.load("vae")
                self._stable_diffusion = self._triton_server.load("stable_diffusion")
                if not self._stable_diffusion.ready():
                    raise Exception("Model not ready")
            except Exception as error:
                print(f"Error can't load stable diffusion model, {error}")
                return

        for response in self._stable_diffusion.infer(inputs={"prompt": [[prompt]]}):
            generated_image = (
                numpy.from_dlpack(response.outputs["generated_image"])
                .squeeze()
                .astype(numpy.uint8)
            )

            image = Image.fromarray(generated_image)
            file_stream = BytesIO()
            image.save(file_stream, "PNG")
            return Response(content=file_stream.getvalue(), media_type="image/png")

entrypoint = TritonDeployment.bind()
