import json
from locust import HttpUser, task, between

class StableDiffusionUser(HttpUser):
    wait_time = between(1, 2)  # Seconds between requests

    @task
    def generate_image(self):
        prompt = "A beautiful sunset over the ocean"
        payload = {
            "prompt": prompt
        }

        headers = {
            "Content-Type": "application/json"
        }

        response = self.client.get(
            "/imagine",
            params=payload,
            data=json.dumps(payload),
            headers=headers
        )

        if response.status_code == 200:
            print(f"Generated image for prompt: {prompt}")
        else:
            print(f"Error generating image: {response.text}")

    # You can add more tasks here if needed
