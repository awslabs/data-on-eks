# Deployment Instructions
This guide provides step-by-step instructions for deploying the **Llama 3.1 405B model** on an Amazon EKS cluster using **4 Trn1 instances**. Follow each section carefully to ensure successful deployment and testing.

## 1. Downalod Llama3.1_405b model form Meta website

- Visit the [Meta website](https://llama.meta.com/) and download the Llama 3.1 405B model.
- Upload the downloaded model and its weights to your own S3 bucket.


## 2. Copy Model weights from S3 to Trn1 SSD Disks

Run the following commands on all 4 nodes to copy the model weights from S3 to the local SSD disks of your Trn1 instances:

        export MODEL_S3_URL="s3://<BUCKET_NAME>/405b-bf16/"
        aws configure set default.s3.preferred_transfer_client crt
        aws configure set default.s3.target_bandwidth 100Gb/s
        aws configure set default.s3.max_concurrent_requests 20
        sudo mkdir -p /mnt/k8s-disks/0/checkpoints/llama-3.1-405b-instruct/
        sudo /usr/local/bin/aws s3 sync $MODEL_S3_URL /mnt/k8s-disks/0/checkpoints/llama-3.1-405b-instruct/
        sudo chmod -R a+rw /mnt/k8s-disks/0/checkpoints/llama-3.1-405b-instruct/

## 3. Install Leader Worker Set (LWS)

To manage the distributed model, install the Leader Worker Set (LWS) by running the following command:

LWS: LWS is a Kubernetes SIGs project that helps manage leader-follower patterns, which are essential for distributed models like Llama.

    VERSION=v0.3.0
    kubectl apply --server-side -f https://github.com/kubernetes-sigs/lws/releases/download/$VERSION/manifests.yaml

## 4. Deploy the model

Deploy the Llama 3.1 405B model on your EKS cluster using the provided Kubernetes YAML file:

> **Note:**
> Please note that this deployment can take up to 20 minutes to compile and load the model across 4 nodes.

    kubectl apply -f  llama3-405b-vllm-lws-deployment.yaml


## 5. Testing the model

To test the deployed model, first, set up port forwarding for the vllm-leader service, which is running on port 8080 in the default namespace:


    kubectl port-forward svc/vllm-leader 8080:8080 -n default


### 5.1 Run a Test Inference

After setting up port forwarding, you can test the model by running the following curl command:


    curl -X POST http://localhost:8080/generate \
      -H "Content-Type: application/json" \
      -d '{
        "prompt": "Translate the following English text to French: Hello, world!",
        "max_tokens": 60,
        "temperature": 0.7,
        "top_p": 0.9,
        "stream": false
      }'

### 5.1 Result

```
{"text":["Translate the following English text to French: Hello, world! in French\nHello, world! in French\nComment dire Hello, world! en français ?\nVoici quelques traductions de Hello, world! en français :\nNous espérons que la traduction de Hello, world! en français vous a aidé! Si vous avez d'autres traductions de"]}%
```

### 6. Gradio WebUI Client deployment

6.1 Deploy Gradio using the command below

    kubectl apply -f gradio-client.yaml


6.2 Port-forward service:

    kubectl port-forward service/gradio-llama-interface 7860:7860

6.3 Access the Gradio Interface:
Open a web browser and go to:

    http://localhost:7860
