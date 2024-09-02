from ultralytics.utils.checks import check_yaml
from ultralytics.utils import yaml_load
import time
import cv2
import numpy as np
import tritonclient.http as httpclient    

client = httpclient.InferenceServerClient(url= "localhost:8000")
CLASSES = yaml_load(check_yaml('coco128.yaml'))['names']
colors = np.random.uniform(0, 255, size=(len(CLASSES), 3))

def draw_bounding_box(img, class_id, confidence, x, y, x_plus_w, y_plus_h):
    label = f'{CLASSES[class_id]} ({confidence:.2f})'
    color = colors[class_id]
    cv2.rectangle(img, (x, y), (x_plus_w, y_plus_h), color, 2)
    cv2.putText(img, label, (x - 10, y - 10), cv2.FONT_HERSHEY_DUPLEX, 0.7, color, 1)

original_image = cv2.imread("/Users/freschri/Downloads/val2017-2/000000025394.jpg")
or_copy = original_image.copy()

[height, width, _] = original_image.shape
length = max((height, width))
scale = length / 640

image = np.zeros((length, length, 3), np.uint8)
image[0:height, 0:width] = original_image
resize = cv2.resize(image, (640, 640))

img = resize[np.newaxis, :, :, :] / 255.0  
img = img.transpose((0, 3, 1, 2)).astype(np.float32)

inputs = httpclient.InferInput("images", img.shape, datatype="FP32")
inputs.set_data_from_numpy(img, binary_data=True)
outputs = httpclient.InferRequestedOutput("output0", binary_data=True)


# Inference
start_time = time.time()
res = client.infer(model_name="yolo", inputs=[inputs], outputs=[outputs]).as_numpy('output0')
end_time = time.time()

inf_time = (end_time - start_time)
print(f"inference time: {inf_time*1000:.3f} ms")
statistics = client.get_inference_statistics(model_name="yolo")
print(statistics)

# Post Processing
outputs = np.array([cv2.transpose(res[0].astype(np.float32))])
rows = outputs.shape[1]

boxes = []
scores = []
class_ids = []
for i in range(rows):
    classes_scores = outputs[0][i][4:]
    (minScore, maxScore, minClassLoc, (x, maxClassIndex)) = cv2.minMaxLoc(classes_scores)
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
        'class_name': CLASSES[class_ids[index]],
        'confidence': scores[index],
        'box': box,
        'scale': scale}
    detections.append(detection)
    draw_bounding_box(or_copy, class_ids[index], scores[index], round(box[0] * scale), round(box[1] * scale),
                        round((box[0] + box[2]) * scale), round((box[1] + box[3]) * scale))

cv2.imshow("Image", or_copy)
cv2.waitKey(0)
cv2.destroyAllWindows()
