from diffusers import StableDiffusionPipeline
import torch

# Set the model you want to download
model_name = "stabilityai/stable-diffusion-2"
model_directory = "./stable-diffusion-2"

# Load the model
pipe = StableDiffusionPipeline.from_pretrained(model_name, torch_dtype=torch.float16, cache_dir=model_directory)
# pipe = StableDiffusionPipeline.from_pretrained(model_directory, torch_dtype=torch.float16)

# Save the model to the local directory
pipe.save_pretrained(model_directory)

# print(f"Model saved to {model_directory}")