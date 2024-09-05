from ultralytics.utils.checks import check_yaml
from ultralytics.utils import yaml_load
import time, os, cv2, numpy as np, tritonclient.http as httpclient

model_name = "yolo"
labels = yaml_load(check_yaml('coco128.yaml'))['names']
colors = np.random.uniform(0, 255, size=(len(labels), 3))
model_input_name = "images"
model_output_name = "output0"

def draw_bounding_box(img, class_id, confidence, x, y, x_plus_w, y_plus_h):
    label = f'{labels[class_id]} ({confidence:.2f})'
    color = colors[class_id]
    cv2.rectangle(img, (x, y), (x_plus_w, y_plus_h), color, 2)
    cv2.putText(img, label, (x - 10, y - 10), cv2.FONT_HERSHEY_DUPLEX, 0.7, color, 1)

def load_image_paths(folder):
    image_paths = []
    for file in os.listdir(folder):
        image_path = os.path.join(folder,file)
        if not file.startswith('.') and not os.path.isdir(image_path):
            image_paths.append(image_path)
    return image_paths

def get_image_params(original_image):
    [height, width, _] = original_image.shape
    length = max((height, width))
    scale = length / 640

    image = np.zeros((length, length, 3), np.uint8)
    image[0:height, 0:width] = original_image
    resize = cv2.resize(image, (640, 640))

    img = resize[np.newaxis, :, :, :] / 255.0  
    img = img.transpose((0, 3, 1, 2)).astype(np.float32)

    inputs = httpclient.InferInput(model_input_name, img.shape, datatype="FP32")
    inputs.set_data_from_numpy(img, binary_data=True)
    outputs = httpclient.InferRequestedOutput(model_output_name, binary_data=True)
    return inputs, outputs, scale

def post_process(inference_results):
    outputs = np.array([cv2.transpose(inference_results[0].astype(np.float32))])
    rows = outputs.shape[1]

    boxes = []
    scores = []
    class_ids = []
    for i in range(rows):
        classes_scores = outputs[0][i][4:]
        (_, maxScore, _, (_, maxClassIndex)) = cv2.minMaxLoc(classes_scores)
        if maxScore >= 0.25:
            box = [
                outputs[0][i][0] - (0.5 * outputs[0][i][2]), outputs[0][i][1] - (0.5 * outputs[0][i][3]),
                outputs[0][i][2], outputs[0][i][3]]
            boxes.append(box)
            scores.append(maxScore)
            class_ids.append(maxClassIndex)

    result_boxes = cv2.dnn.NMSBoxes(boxes, scores, 0.25, 0.45, 0.5)

    detections = []
    for i in range(len(result_boxes)):
        index = result_boxes[i]
        box = boxes[index]
        detection = {
            'class_id': class_ids[index],
            'class_name': labels[class_ids[index]],
            'confidence': scores[index],
            'box': box}
        detections.append(detection)
    return detections

def draw_detections(image, detections, scale):
    for detection in detections:
        class_id = detection["class_id"]
        confidence = detection["confidence"]
        box = detection["box"]
        draw_bounding_box(image, class_id, confidence, round(box[0] * scale), round(box[1] * scale), round((box[0] + box[2]) * scale), round((box[1] + box[3]) * scale))
    
    return image

def infer(image, client):
    inputs, outputs, scale = get_image_params(image)
    
    start_time = time.time()
    inference_results = client.infer(model_name=model_name, inputs=[inputs], outputs=[outputs]).as_numpy(model_output_name)
    end_time = time.time()
    
    inf_time = (end_time - start_time)
    print(f"inference time: {inf_time*1000:.3f} ms")

    statistics = client.get_inference_statistics(model_name=model_name)
    print(statistics)

    detections = post_process(inference_results)
    return draw_detections(image, detections, scale)