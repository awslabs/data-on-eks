from io import BytesIO
from fastapi import FastAPI
from fastapi.responses import Response
import torch
import os
import ray
from ray import serve


app = FastAPI()


@serve.deployment(num_replicas=1)
@serve.ingress(app)
class APIIngress:
    def __init__(self, diffusion_model_handle) -> None:
        self.handle = diffusion_model_handle

    @app.get(
        "/imagine",
        responses={200: {"content": {"image/png": {}}}},
        response_class=Response,
    )
    async def generate(self, prompt: str, img_size: int = 768):
        assert len(prompt), "prompt parameter cannot be empty"

        image = await self.handle.generate.remote(prompt, img_size=img_size)
        file_stream = BytesIO()
        image.save(file_stream, "PNG")
        return Response(content=file_stream.getvalue(), media_type="image/png")


@serve.deployment(
    name="stable-diffusion-v2",
    ray_actor_options={"num_gpus": 1},
    autoscaling_config={"min_replicas": 1, "max_replicas": 2},
)
class StableDiffusionV2:
    def __init__(self):
        from diffusers import EulerDiscreteScheduler, StableDiffusionPipeline

        model_id = os.getenv("MODEL_ID")
        model_path = os.getenv("MODEL_PATH")
        if model_path is not None:
            model_id = model_path

        self.pipe = StableDiffusionPipeline.from_pretrained(
            model_id, torch_dtype=torch.float16
        )
        self.pipe = self.pipe.to("cuda")

    def generate(self, prompt: str, img_size: int = 768):
        assert len(prompt), "prompt parameter cannot be empty"

        image = self.pipe(
            prompt,
            height=img_size,
            width=img_size,
            negative_prompt="",
            num_inference_steps=50,
            guidance_scale=7.0,
        ).images[0]
        return image


entrypoint = APIIngress.bind(StableDiffusionV2.bind())
