---
title: RayServe with vLLM
sidebar_position: 6
---
import CollapsibleContent from '../../../src/components/CollapsibleContent';

:::caution

The use of [Mistralai/Mistral-7B-Instruct-v0.2](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2) models requires access through a Hugging Face account.

:::

# Deploying Large Language Models with RayServe and vLLM

In this pattern, we'll explore how to deploy multiple large language models (LLMs) using the [Ray](https://docs.ray.io/en/latest/serve/getting_started.html) and the [vLLM](https://github.com/vllm-project/vllm) backend/engine. We'll demonstrate this process with `mistralai/Mistral-7B-Instruct-v0.2` model.

Using Ray Serve with a vLLM backend for LLM inference offers several compelling benefits, particularly in terms of scalability, efficiency, and ease of deployment. Ray Serve is designed to handle concurrent requests efficiently, making it ideal for real-time applications where multiple requests need to be processed simultaneously. It supports dynamic batching, which groups multiple requests together to optimize throughput and resource utilization, crucial for handling the high demands of LLM inference. Additionally, Ray Serve's ability to auto-scale based on incoming request load ensures that resources are used optimally, adapting to varying traffic without manual intervention. The integration with vLLM further enhances performance by leveraging vLLM's real-time batching capabilities, which are essential for efficient online inference. Moreover, Ray Serve's framework-agnostic nature allows it to be used alongside any Python framework, providing flexibility in model deployment and integration with existing systems. This combination of features makes Ray Serve with a vLLM backend a robust solution for deploying large language models in production environments, ensuring high performance, scalability, and ease of use. In this deployment, we're leveraging `g5.8xlarge` instance to run Ray worker Pod hosting the inference endpoint.

# RayServe and vLLM Backend Integration

**[vLLM](https://github.com/vllm-project/vllm)**: vLLM backend is specifically designed to handle various LLM workloads. It offers efficient memory management and execution pipelines tailored for large models. This backend ensures that memory resources are used optimally, allowing for the deployment of very large models without running into memory bottlenecks. vLLM is crucial for applications that need to serve multiple large models simultaneously, providing a robust and scalable solution.


### Mistralai/Mistral-7B-Instruct-v0.2
Mistralai/Mistral-7B-Instruct-v0.2 is a state-of-the-art large language model designed to provide high-quality, instructive responses. Trained on a diverse dataset, it excels in understanding and generating human-like text across a variety of topics. Its capabilities make it suitable for applications requiring detailed explanations, complex queries, and natural language understanding.

## Deploying the Solution
To get started with deploying `mistralai/Mistral-7B-Instruct-v0.2`  on [Amazon EKS](https://aws.amazon.com/eks/), we will cover the necessary prerequisites and guide you through the deployment process step by step. This process includes setting up the infrastructure, deploying the Ray cluster, and creating the client Python application that sends HTTP requests to the RayServe endpoint for inferencing.

:::danger

Important: Deploying on `g5.8xlarge` instances can be expensive. Ensure you carefully monitor and manage your usage to avoid unexpected costs. Consider setting budget alerts and usage limits to keep track of your expenditures.

:::


<CollapsibleContent header={<h2><span>Prerequisites</span></h2>}>
Before we begin, ensure you have all the necessary prerequisites in place to make the deployment process smooth. Make sure you have installed the following tools on your machine:

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [envsubst](https://pypi.org/project/envsubst/)

### Deploy

Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into one of the example directories and run `install.sh` script

**Important Note:**

**Step1**: Ensure that you update the region in the `variables.tf` file before deploying the blueprint.
Additionally, confirm that your local region setting matches the specified region to prevent any discrepancies.

For example, set your `export AWS_DEFAULT_REGION="<REGION>"` to the desired region:

**Step2**: To proceed, ensure you have access to the model using your Huggingface account:

![mistral7b-hg.png](img/mistral7b-hg.png)

**Step4**: Run the installation script.

```bash
cd data-on-eks/ai-ml/jark-stack/ && chmod +x install.sh
./install.sh
```

### Verify the resources

**Step5**: Once the installation finishes, verify the Amazon EKS Cluster

```bash
# Creates k8s config file to authenticate with EKS
aws eks --region us-west-2 update-kubeconfig --name jark-stack

kubectl get nodes # Output shows the EKS worker nodes
```

</CollapsibleContent>

### RayServe with vLLM Backend

We're using the [jark-stack blueprint](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/jark-stack/terraform) to deploy the EKS cluster with `KubeRay` operator, `nvidia-device-plugin` and other necessary add-ons. We're also using Karpenter version `0.37` in this blueprint.

**vllm_serve.py**: This script uses vLLM library as RayServe backend framework and initializes a `VLLMDeployment` class by loading the model configuration and configuring vLLM engine. The `huggingface_hub` library's login function is used to establish access to the hugging face repository for model access. It then starts an asyncio event loop to process the received requests asynchronously. The script has several functions that processes the inference requests, issues the requests to vLLM backend and return the response.


**Deploy RayServe Cluster**

:::info

To deploy the Mistral-7B-Instruct-v0.2 model with RayServe and vLLM backend, it's essential to configure your Hugging Face Hub token as an environment variable. This token is required for authentication and accessing the model. For guidance on how to create and manage your Hugging Face tokens, please visit [Hugging Face Token Management](https://huggingface.co/docs/hub/security-tokens).

:::

```bash
# set the Hugging Face Hub Token as an environment variable. This variable will be substituted when applying the ray-service-vllm.yaml file

export HUGGING_FACE_HUB_TOKEN=$(echo -n "Your-Hugging-Face-Hub-Token-Value" | base64)

cd ./../gen-ai/inference/vllm-rayserve-gpu
envsubst < ray-service-vllm.yaml| kubectl apply -f -
```

Verify the deployment by running the following commands

:::info

The deployment process may take up to 10 minutes. The Head Pod is expected to be ready within 5 to 6 minutes, while the Ray Serve worker pod may take up to 10 minutes for image retrieval and Model deployment from Huggingface.

:::

This deployment establishes a Ray head pod running on an `x86` instance and a worker pod on `g5.8xl` instance as shown below.

```bash
kubectl get po -n rayserve-vllm

NAME                                           READY   STATUS    RESTARTS   AGE
vllm-raycluster-nvtxg-head-g2cg8               1/1     Running   0          47m
vllm-raycluster-nvtxg-worker-gpu-group-msl5p   1/1     Running   0          47m
```

This deployment also sets up a mistral service with multiple ports configured; port `8265` is designated for the Ray dashboard and port `8000` for the Mistral model endpoint.

```bash
kubectl get svc -n rayserve-vllm

NAME             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                                         AGE
vllm             ClusterIP   172.20.208.16    <none>        6379/TCP,8265/TCP,10001/TCP,8000/TCP,8080/TCP   48m
vllm-head-svc    ClusterIP   172.20.239.237   <none>        6379/TCP,8265/TCP,10001/TCP,8000/TCP,8080/TCP   37m
vllm-serve-svc   ClusterIP   172.20.196.195   <none>        8000/TCP                                        37m
```

For the Ray dashboard, you can port-forward these ports individually to access the web UI locally using localhost.

```bash
kubectl -n rayserve-vllm port-forward svc/vllm 8265:8265
```

Access the web UI via `http://localhost:8265` . This interface displays the deployment of jobs and actors within the Ray ecosystem.

![RayServe Deployment](img/ray-dashboard-vllm-mistral.png)

Once the deployment is complete, the Controller and Proxy status should be `HEALTHY` and Application status should be `RUNNING`

![RayServe Deployment Logs](img/ray-deplo-logs-vllm-mistral.png)

### Testing Mistral-7b Chat Model
It's time to test the Mistral-7b chat model. We will run the following commands with the same prompts to verify the outputs generated by the model. We use a python client that sends the request over HTTP to the RayServe inference endpoint hosting the `mistral

First, execute a port forward to the `vllm-serve-svc` Service using kubectl:

```bash
kubectl -n rayserve-vllm port-forward svc/vllm-serve-svc 8000:8000
```

**client.py** This script uses HTTP `post` method to send a list of prompts to the inference endpoint for text completion and Q&A. It uses `/vllm` as the model endpoint.

You can test with your custom prompts by adding them in the `prompts` array.

To, run the python client application in a python virtual environment:

```bash
cd gen-ai/inference/vllm-rayserve-gpu
python3 -m venv .venv
source .venv/bin/activate
pip install requests
python3 client.py
```

You will see an output something like below:

```text
Prompt: [INST] How big is the Observable Universe? [/INST] The observable universe is not a fixed size with a definitive boundary, but
Response: [INST] How big is the Observable Universe? [/INST] The observable universe is not a fixed size with a definitive boundary, but rather it continues to expand since the Big Bang around 13.8 billion years ago. The current estimate for the diameter of the observable universe is around 93 billion light-years. However, this size is based on the current understanding of the universe and our ability to observe it, and it may continue to grow as technology and knowledge advance. It's important to note that the observable universe is not the entire universe, but rather the part of it that we can currently observe based on the information that has reached us since the Big Bang. The rest of the universe, which is sometimes referred to as the "unobservable universe," is beyond the current horizon and cannot be directly observed.
```

The should like below:

<details>
<summary>Click to expand Mistral results partial output</summary>
```text
Prompt: [INST] How big is the Observable Universe? [/INST] The observable universe is not a fixed size with a definitive boundary, but
Response: [INST] How big is the Observable Universe? [/INST] The observable universe is not a fixed size with a definitive boundary, but rather it continues to expand since the Big Bang around 13.8 billion years ago. The current estimate for the diameter of the observable universe is around 93 billion light-years. However, this size is based on the current understanding of the universe and our ability to observe it, and it may continue to grow as technology and knowledge advance. It's important to note that the observable universe is not the entire universe, but rather the part of it that we can currently observe based on the information that has reached us since the Big Bang. The rest of the universe, which is sometimes referred to as the "unobservable universe," is beyond the current horizon and cannot be directly observed.
--------------------------------------------------------------------------------
Prompt: [INST] What is the speed of light? [/INST] The speed of light in a vacuum is a fundamental constant of nature,
Response: [INST] What is the speed of light? [/INST] The speed of light in a vacuum is a fundamental constant of nature, and it is approximately 299,792,458 meters per second or about 186,282 miles per second. This value is often denoted by the symbol "c". It is the maximum speed at which all information, energy, or matter can travel. In other mediums, such as water or glass, the speed of light is slightly slower due to the interaction between the light and the material.
--------------------------------------------------------------------------------
Prompt: [INST] Explain the theory of relativity. [/INST] The theory of relativity, developed by Albert Einstein, is a fundamental theory in physics that describes the relationship between space and time,
Response: [INST] Explain the theory of relativity. [/INST] The theory of relativity, developed by Albert Einstein, is a fundamental theory in physics that describes the relationship between space and time, and how matter and energy interact within that framework. It is actually composed of two parts: the Special Theory of Relativity, published in 1905, and the General Theory of Relativity, published in 1915.

The Special Theory of Relativity is based on two postulates: the first one states that the laws of physics are the same in all inertial frames of reference (frames that are not accelerating); the second one asserts that the speed of light in a vacuum is the same for all observers, regardless of their motion or the source of the light.

From these two postulates, several counter-intuitive consequences follow. For example, the length of an object contracts when it is in motion relative to an observer, and time dilation occurs, meaning that a moving clock appears to tick slower than a stationary one. These phenomena have been confirmed by numerous experiments.

The General Theory of Relativity is a theory of gravitation, which extended the Special Theory of Relativity by incorporating gravity into the fabric of spacetime. In this theory, mass causes a distortion or curvature in spacetime, which is felt as a gravitational force. This is in contrast to the Newtonian view of gravity as a force acting at a distance between two masses.

One of the most famous predictions of General Relativity is the bending of light by gravity, which was first observed during a solar eclipse in 1919. The theory has been extremely successful in explaining various phenomena, such as the precession of Mercury's orbit, the gravitational redshift of light, and the existence of black holes and gravitational waves.

In summary, the theory of relativity is a groundbreaking theory in physics that fundamentally changed our understanding of space, time, and matter. It has been incredibly successful in making accurate predictions about the natural world and has stood the test of time through numerous experiments and observations.
--------------------------------------------------------------------------------
```
</details>


## Conclusion
Integrating Ray Serve with a vLLM backend offers numerous benefits for large language model (LLM) inference, particularly in terms of efficiency, scalability, and cost-effectiveness. Ray Serve's ability to handle concurrent requests and dynamically batch them ensures optimal GPU utilization, which is crucial for high-throughput LLM applications. The integration with vLLM enhances this further by enabling continuous batching, which significantly improves throughput and reduces latency compared to static batching. Overall, the combination of Ray Serve and vLLM provides a robust, scalable, and cost-efficient solution for deploying LLMs in production.

## Cleanup

Finally, we'll provide instructions for cleaning up and deprovisioning the resources when they are no longer needed.

**Cleanup the EKS Cluster:**
This script will cleanup the environment using `-target` option to ensure all the resources are deleted in correct order.

```bash
export AWS_DEAFULT_REGION="DEPLOYED_EKS_CLUSTER_REGION>"
cd data-on-eks/ai-ml/jark-stack/terraform/ && chmod +x cleanup.sh
./cleanup.sh
```
