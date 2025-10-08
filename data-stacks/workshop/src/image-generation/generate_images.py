import boto3
import base64
import os
import json
import time
import logging
import argparse
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Constants
COAT_COLORS = ['tabby', 'calico', 'black', 'orange', 'gray', 'white']
COAT_LENGTHS = ['short', 'medium', 'long']
MODEL_ID = "amazon.nova-canvas-v1:0"
AWS_REGION = "us-east-1"
OUTPUT_DIR = "images"
MAX_RETRIES = 5
INITIAL_BACKOFF = 10  # seconds
STATE_FILE = "generation_state.json"

def get_bedrock_client():
    """Initializes and returns a Bedrock Runtime client."""
    try:
        client = boto3.client(service_name='bedrock-runtime', region_name=AWS_REGION)
        return client
    except Exception as e:
        logging.error(f"Error creating Bedrock client: {e}")
        return None

def generate_image(client, prompt, seed, height, width):
    """Generates an image using the Bedrock model with retry logic."""
    body = {
        "taskType": "TEXT_IMAGE",
        "textToImageParams": {
            "text": prompt
        },
        "imageGenerationConfig": {
            "numberOfImages": 1,
            "height": height,
            "width": width,
            "cfgScale": 8.0,
            "seed": seed
        }
    }

    for attempt in range(MAX_RETRIES):
        try:
            response = client.invoke_model(
                body=json.dumps(body),
                modelId=MODEL_ID,
                accept='application/json',
                contentType='application/json'
            )
            response_body = json.loads(response.get('body').read())
            
            if 'image' in response_body:
                return response_body['image']
            elif 'images' in response_body and response_body['images']:
                return response_body['images'][0]
            else:
                logging.error(f"No image data in response: {response_body}")
                return None

        except ClientError as e:
            if e.response['Error']['Code'] == 'ThrottlingException':
                wait_time = INITIAL_BACKOFF * (2 ** attempt)
                logging.warning(f"Throttling exception caught. Retrying in {wait_time} seconds...")
                time.sleep(wait_time)
            else:
                logging.error(f"A ClientError occurred: {e}")
                return None
        except Exception as e:
            logging.error(f"An unexpected error occurred during image generation: {e}")
            return None
    
    logging.error("Failed to generate image after multiple retries.")
    return None

def save_image(image_data, file_path):
    """Saves the base64 encoded image data to a file."""
    try:
        script_dir = os.path.dirname(os.path.realpath(__file__))
        full_path = os.path.join(script_dir, file_path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, "wb") as f:
            f.write(base64.b64decode(image_data))
        logging.info(f"Image saved to {full_path}")
    except Exception as e:
        logging.error(f"Error saving image to {file_path}: {e}")

def main():
    """Main function to generate cat images."""
    parser = argparse.ArgumentParser(description="Generate cat images using AWS Bedrock.")
    parser.add_argument('--height', type=int, default=320, help='Height of the generated image.')
    parser.add_argument('--width', type=int, default=320, help='Width of the generated image.')
    parser.add_argument('--num_images', type=int, default=2, help='Number of images to generate in this run.')
    parser.add_argument('--variants', type=int, default=1, help='Number of variants to generate for each combination.')
    parser.add_argument('--no-resume', action='store_true', help='Do not resume from last state and start from the beginning.')
    args = parser.parse_args()

    logging.info(f"Starting cat image generation script with size {args.width}x{args.height}.")
    
    bedrock_client = get_bedrock_client()
    if not bedrock_client:
        logging.error("Could not create Bedrock client. Exiting.")
        return

    combinations = [(length, color) for length in COAT_LENGTHS for color in COAT_COLORS]
    tasks = []
    for length, color in combinations:
        for variant in range(args.variants):
            tasks.append((length, color, variant))

    start_index = 0
    script_dir = os.path.dirname(os.path.realpath(__file__))
    state_file_path = os.path.join(script_dir, STATE_FILE)

    if not args.no_resume and os.path.exists(state_file_path):
        try:
            with open(state_file_path, 'r') as f:
                state = json.load(f)
                start_index = state.get('last_successful_index', -1) + 1
            logging.info(f"Resuming from task index {start_index}")
        except (json.JSONDecodeError, FileNotFoundError):
            logging.warning(f"Could not read state file {state_file_path}. Starting from the beginning.")
            start_index = 0

    generation_count = 0

    for i in range(start_index, len(tasks)):
        if generation_count >= args.num_images:
            logging.info(f"Reached generation limit of {args.num_images} images for this run.")
            break
        
        length, color, variant = tasks[i]
        prompt = f"a full-body portrait of a {length}-haired {color} cat with detailed fur texture, in soft natural lighting"
        logging.info(f"Generating image for task {i+1}/{len(tasks)}: {length}-{color} variant {variant+1}")
        
        image_base64 = generate_image(bedrock_client, prompt, seed=i, height=args.height, width=args.width)
        
        if image_base64:
            timestamp = int(time.time())
            file_name = f"{length}_{color}_{timestamp}_variant_{variant+1}.png"
            file_path = os.path.join(OUTPUT_DIR, file_name)
            save_image(image_base64, file_path)
            
            with open(state_file_path, 'w') as f:
                json.dump({'last_successful_index': i}, f)

            generation_count += 1
        else:
            logging.error(f"Failed to generate image for task {i+1}. Stopping run.")
            break

    logging.info(f"Image generation run finished. Generated {generation_count} images in this run.")

if __name__ == "__main__":
    main()
