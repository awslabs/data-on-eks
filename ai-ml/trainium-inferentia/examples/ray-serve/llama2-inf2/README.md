# How to deploy Llama2 on Inference2 and EKS

## Step1:

## Step2:

## Step3:

To port forward the Ray Serve service and test the Llama2 model using Curl command, you can follow these steps:

Get the external IP address of the Ray Serve head pod. You can do this using the following command:

    kubectl get pods -n llama2 -l app.kubernetes.io/name=kuberay,ray.io/cluster=llama2-service-raycluster-2bx6m,ray.io/identifier=llama2-service-raycluster-2bx6m-head,ray.io/node-type=head -o jsonpath='{.items[0].status.podIP}'

Port forward the Ray Serve service to your local machine using the following command:

    kubectl port-forward -n llama2 service/llama2-service-raycluster-2bx6m-head-svc 8000:8000

Test the Llama2 model using the following Curl command:

    curl -X POST http://localhost:8000/infer -d '{"sentence": "Hello, world!"}'

This will return a JSON response containing the generated text.
