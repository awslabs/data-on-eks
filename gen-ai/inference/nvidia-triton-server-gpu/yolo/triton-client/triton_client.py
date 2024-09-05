from sys import argv, exit
from yolo_inference import load_image_paths, infer
import os, cv2, shutil, tritonclient.http as httpclient

url = "localhost:8000"

def main():
    try:
        images_path = argv[1]
    except:
        print("Please provide the path of your test images")
        exit(1)
    if not os.path.exists(images_path):
        raise Exception(f'The path at location {images_path} does not exist')
    
    results_path = os.path.join(images_path, "results")
    if os.path.exists(results_path):
        shutil.rmtree(results_path)
    os.mkdir(results_path)

    client = httpclient.InferenceServerClient(url=url)
    
    for image_path in load_image_paths(images_path):
        image = cv2.imread(image_path)
        image = infer(image, client)
        result_path = os.path.join(results_path, os.path.basename(image_path))
        cv2.imwrite(result_path, image)

if __name__ == "__main__":
    main()
