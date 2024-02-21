from io import BytesIO
from fastapi import FastAPI
from fastapi.responses import Response
import os
import base64

from ray import serve

app = FastAPI()

neuron_cores = 2

@serve.deployment(name="stable-diffusion-api", num_replicas=1, route_prefix="/")
@serve.ingress(app)
class APIIngress:
    def __init__(self, diffusion_model_handle) -> None:
        self.handle = diffusion_model_handle

    @app.get(
        "/imagine",
        responses={200: {"content": {"image/png": {}}}},
        response_class=Response,
    )
    async def generate(self, prompt: str):
        image = await self.handle.generate.remote(prompt)
        file_stream = BytesIO()
        image.save(file_stream, "PNG")
        return Response(content=file_stream.getvalue(), media_type="image/png")

@serve.deployment(name="stable-diffusion-v2",
    autoscaling_config={"min_replicas": 0, "max_replicas": 6},
    ray_actor_options={
        "resources": {"neuron_cores": neuron_cores},
        "runtime_env": {"env_vars": {"NEURON_CC_FLAGS": "-O1"}},
    },
)
class StableDiffusionV2:
    def __init__(self):
        from optimum.neuron import NeuronStableDiffusionXLPipeline

        compiled_model_id = "aws-neuron/stable-diffusion-xl-base-1-0-1024x1024"

        # To avoid saving the model locally, we can use the pre-compiled model directly from HF
        self.pipe = NeuronStableDiffusionXLPipeline.from_pretrained(compiled_model_id, device_ids=[0, 1])

    async def generate(self, prompt: str):
        assert len(prompt), "prompt parameter cannot be empty"
        image = self.pipe(prompt).images[0]
        return image

entrypoint = APIIngress.bind(StableDiffusionV2.bind())
