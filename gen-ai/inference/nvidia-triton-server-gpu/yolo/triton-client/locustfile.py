import os, random, numpy as np, tritonclient.http as httpclient
from locust import FastHttpUser, task
from PIL import Image
from yolo_inference import load_image_paths

class YoloTritonUser(FastHttpUser):
    host = "http://127.0.0.1:8000"

    images_path = os.environ['IMAGES_PATH']
    if not os.path.exists(images_path):
        raise Exception(f'The path at location {images_path} does not exist')
    
    image_paths = load_image_paths(images_path)

    @task
    def request(self):
        image_path = random.choice(self.image_paths)
    
        image = Image.open(image_path).resize((640, 640))
        image = np.array(image).astype(np.float32) / 255.0
        image = np.transpose(image, (2, 0, 1))
        image = np.expand_dims(image, axis=0)

        inputs = [httpclient.InferInput("images", image.shape, "FP32")]
        inputs[0].set_data_from_numpy(image)

        outputs = [httpclient.InferRequestedOutput("output0")]

        request_body, json_size = httpclient._utils._get_inference_request(
            inputs=inputs,
            request_id="",
            outputs=outputs,
            sequence_id=0,
            sequence_start=False,
            sequence_end=False,
            priority=0,
            timeout=None,
            custom_parameters=None,
        )

        response = self.client.post(
            "/v2/models/yolo/versions/1/infer",
            data=request_body,
            headers={
                "Inference-Header-Content-Length": json_size,
            },
        )

        print("Response status code:", response.status_code)
