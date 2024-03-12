---
title: Llama-2 on Inferentia
sidebar_position: 1
---
import CollapsibleContent from '../../../src/components/CollapsibleContent';


:::danger

Note: Use of this Llama-2 model is governed by the Meta license.
In order to download the model weights and tokenizer, please visit the [website](https://ai.meta.com/) and accept the license before requesting access.

:::

:::info

We are actively enhancing this blueprint to incorporate improvements in observability, logging, and scalability aspects.

:::


# Deploying Llama-2-13b Chat Model with Inferentia, Ray Serve and Gradio
Welcome to the comprehensive guide on deploying the [Meta Llama-2-13b chat](https://ai.meta.com/llama/#inside-the-model) model on Amazon Elastic Kubernetes Service (EKS) using [Ray Serve](https://docs.ray.io/en/latest/serve/index.html).
In this tutorial, you will not only learn how to harness the power of Llama-2, but also gain insights into the intricacies of deploying large language models (LLMs) efficiently, particularly on [trn1/inf2](https://aws.amazon.com/machine-learning/neuron/) (powered by AWS Trainium and Inferentia) instances, such as `inf2.24xlarge` and `inf2.48xlarge`,
which are optimized for deploying and scaling large language models.

### What is Llama-2?
Llama-2 is a pretrained large language model (LLM) trained on 2 trillion tokens of text and code. It is one of the largest and most powerful LLMs available today. Llama-2 can be used for a variety of tasks, including natural language processing, text generation, and translation.

#### Llama-2-chat
Llama-2 is a remarkable language model that has undergone a rigorous training process. It starts with pretraining using publicly available online data. An initial version of Llama-2-chat is then created through supervised fine-tuning.
Following that, `Llama-2-chat` undergoes iterative refinement using Reinforcement Learning from Human Feedback (`RLHF`), which includes techniques like rejection sampling and proximal policy optimization (`PPO`).
This process results in a highly capable and fine-tuned language model that we will guide you to deploy and utilize effectively on **Amazon EKS** with **Ray Serve**.

Llama-2 is available in three different model sizes:

- **Llama-2-70b:** This is the largest Llama-2 model, with 70 billion parameters. It is the most powerful Llama-2 model and can be used for the most demanding tasks.
- **Llama-2-13b:** This is a medium-sized Llama-2 model, with 13 billion parameters. It is a good balance between performance and efficiency, and can be used for a variety of tasks.
- **Llama-2-7b:** This is the smallest Llama-2 model, with 7 billion parameters. It is the most efficient Llama-2 model and can be used for tasks that do not require the highest level of performance.

### **Which Llama-2 model size should I use?**
The best Llama-2 model size for you will depend on your specific needs. and it may not always be the largest model for achieving the highest performance. It's advisable to evaluate your needs and consider factors such as computational resources, response time, and cost-efficiency when selecting the appropriate Llama-2 model size. The decision should be based on a comprehensive assessment of your application's goals and constraints.

## Inference on Trn1/Inf2 Instances: Unlocking the Full Potential of Llama-2
**Llama-2** can be deployed on a variety of hardware platforms, each with its own set of advantages. However, when it comes to maximizing the efficiency, scalability, and cost-effectiveness of Llama-2, [AWS Trn1/Inf2 instances](https://aws.amazon.com/ec2/instance-types/inf2/) shine as the optimal choice.

**Scalability and Availability**
One of the key challenges in deploying large language models (`LLMs`) like Llama-2 is the scalability and availability of suitable hardware. Traditional `GPU` instances often face scarcity due to high demand, making it challenging to provision and scale resources effectively.
In contrast, `Trn1/Inf2` instances, such as `trn1.32xlarge`, `trn1n.32xlarge`, `inf2.24xlarge` and `inf2.48xlarge`, are purpose built for high-performance deep learning (DL) training and inference of generative AI models, including LLMs. They offer both scalability and availability, ensuring that you can deploy and scale your `Llama-2` models as needed, without resource bottlenecks or delays.

**Cost Optimization:**
Running LLMs on traditional GPU instances can be cost-prohibitive, especially given the scarcity of GPUs and their competitive pricing.
**Trn1/Inf2** instances provide a cost-effective alternative. By offering dedicated hardware optimized for AI and machine learning tasks, Trn1/Inf2 instances allow you to achieve top-notch performance at a fraction of the cost.
This cost optimization enables you to allocate your budget efficiently, making LLM deployment accessible and sustainable.

**Performance Boost**
While Llama-2 can achieve high-performance inference on GPUs, Neuron accelerators take performance to the next level. Neuron accelerators are purpose-built for machine learning workloads, providing hardware acceleration that significantly enhances Llama-2's inference speeds. This translates to faster response times and improved user experiences when deploying Llama-2 on Trn1/Inf2 instances.

### Model Specification
The table provides information about the different sizes of Llama-2 models, their weights, and the hardware requirements for deploying them. This information can be used to design the infrastructure required to deploy any size of Llama-2 model. For example, if you want to deploy the `Llama-2-13b-chat` model, you will need to use an instance type with at least `26 GB` of total accelerator memory.

| Model           | Weights | Bytes | Parameter Size (Billions) | Total Accelerator Memory (GB) | Accelerator Memory Size for NeuronCore (GB) | Required Neuron Cores | Required Neuron Accelerators | Instance Type   | tp_degree |
|-----------------|---------|-------|-----------------------------|------------------------------|---------------------------------------------|-----------------------|-----------------------------|-----------------|-----------|
| Meta/Llama-2-70b | float16 | 2     | 70                          | 140                          | 16                                          | 9                     | 5                           | inf2.48x        | 24        |
| Meta/Llama-2-13b | float16 | 2     | 13                          | 26                           | 16                                          | 2                     | 1                           | inf2.24x        | 12        |
| Meta/Llama-2-7b | float16 | 2     | 7                           | 14                           | 16                                          | 1                     | 1                           | inf2.24x        | 12        |

### Example usecase
A company wants to deploy a Llama-2 chatbot to provide customer support. The company has a large customer base and expects to receive a high volume of chat requests at peak times. The company needs to design an infrastructure that can handle the high volume of requests and provide a fast response time.

The company can use Inferentia2 instances to scale its Llama-2 chatbot efficiently. Inferentia2 instances are specialized hardware accelerators for machine learning tasks. They can provide up to 20x better performance and up to 7x lower cost than GPUs for machine learning workloads.

The company can also use Ray Serve to horizontally scale its Llama-2 chatbot. Ray Serve is a distributed framework for serving machine learning models. It can automatically scale your models up or down based on demand.

To scale its Llama-2 chatbot, the company can deploy multiple Inferentia2 instances and use Ray Serve to distribute the traffic across the instances. This will allow the company to handle a high volume of requests and provide a fast response time.

## Solution Architecture
In this section, we will delve into the architecture of our solution, which combines Llama-2 model, [Ray Serve](https://docs.ray.io/en/latest/serve/index.html) and [Inferentia2](https://aws.amazon.com/ec2/instance-types/inf2/) on Amazon EKS.

![Llama-2-inf2](img/llama2-inf2.png)

## Deploying the Solution
To get started with deploying `Llama-2-13b chat` on [Amazon EKS](https://aws.amazon.com/eks/), we will cover the necessary prerequisites and guide you through the deployment process step by step.
This includes setting up the infrastructure, deploying the **Ray cluster**, and creating the [Gradio](https://www.gradio.app/) WebUI app.

<CollapsibleContent header={<h2><span>Prerequisites</span></h2>}>
Before we begin, ensure you have all the prerequisites in place to make the deployment process smooth and hassle-free.
nsure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

### Deploy

Clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into one of the example directories and run `install.sh` script

**Important Note:** Ensure that you update the region in the `variables.tf` file before deploying the blueprint.
Additionally, confirm that your local region setting matches the specified region to prevent any discrepancies.
For example, set your `export AWS_DEFAULT_REGION="<REGION>"` to the desired region:

```bash
cd data-on-eks/ai-ml/trainium-inferentia/ && chmod +x install.sh
./install.sh
```

### Verify the resources

Verify the Amazon EKS Cluster

```bash
aws eks --region us-west-2 describe-cluster --name trainium-inferentia
```

```bash
# Creates k8s config file to authenticate with EKS
aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia

kubectl get nodes # Output shows the EKS Managed Node group nodes
```

</CollapsibleContent>

## Deploying the Ray Cluster with Llama-2-Chat Model
Once the `Trainium on EKS` Cluster is deployed, you can proceed to use `kubectl` to deploy the `ray-service-Llama-2.yaml`.

In this step, we will deploy the Ray Serve cluster, which comprises one `Head Pod` on `x86 CPU` instances using Karpenter autoscaling, as well as `Ray workers` on `Inf2.48xlarge` instances, autoscaled by [Karpenter](https://karpenter.sh/).

Let's take a closer look at the key files used in this deployment and understand their functionalities before proceeding with the deployment:

- **ray_serve_Llama-2.py:**
This script uses FastAPI, Ray Serve, and PyTorch-based Hugging Face Transformers to create an efficient API for text generation using the [NousResearch/Llama-2-13b-chat-hf](https://huggingface.co/NousResearch/Llama-2-13b-chat-hf) language model.
Alternatively, users have the flexibility to switch to the [meta-llama/Llama-2-13b-chat-hf](https://huggingface.co/meta-llama/Llama-2-13b-chat-hf) model. The script establishes an endpoint that accepts input sentences and efficiently generates text outputs, benefiting from Neuron acceleration for enhanced performance. With its high configurability, users can fine-tune model parameters to suit a wide range of natural language processing applications, including chatbots and text generation tasks.

- **ray-service-Llama-2.yaml:**
This Ray Serve YAML file serves as a Kubernetes configuration for deploying the Ray Serve service, facilitating efficient text generation using the `Llama-2-13b-chat` model.
It defines a Kubernetes namespace named `Llama-2` to isolate resources. Within the configuration, the `RayService` specification, named `Llama-2-service`, is created and hosted within the `Llama-2` namespace. The `RayService` specification leverages the Python script `ray_serve_Llama-2.py` (copied into the Dockerfile located within the same folder) to create the Ray Serve service.
The Docker image used in this example is publicly available on Amazon Elastic Container Registry (ECR) for ease of deployment.
Users can also modify the Dockerfile to suit their specific requirements and push it to their own ECR repository, referencing it in the YAML file.

### Deploy the Llama-2-Chat Model

**Ensure the cluster is configured locally**
```bash
aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia
```

**Deploy RayServe Cluster**

```bash
cd ai-ml/trainium-inferentia/examples/inference/ray-serve/llama2-inf2
kubectl apply -f ray-service-llama2.yaml
```

Verify the deployment by running the following commands

:::info

The deployment process may take up to 10 minutes. The Head Pod is expected to be ready within 2 to 3 minutes, while the Ray Serve worker pod may take up to 10 minutes for image retrieval and Model deployment from Huggingface.

:::

```text
$ kubectl get all -n llama2

NAME                                                          READY   STATUS              RESTARTS   AGE
pod/llama2-service-raycluster-smqrl-head-4wlbb                0/1     ContainerCreating   0          77s
pod/service-raycluster-smqrl-worker-inf2-worker-group-wjxqq   0/1     Init:0/1            0          77s

NAME                     TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                                                                                       AGE
service/llama2-service   NodePort   172.20.246.48   <none>        8000:32138/TCP,52365:32653/TCP,8080:32604/TCP,6379:32739/TCP,8265:32288/TCP,10001:32419/TCP   78s

$ kubectl get ingress -n llama2

NAME             CLASS   HOSTS   ADDRESS                                                                         PORTS   AGE
llama2-ingress   nginx   *       k8s-ingressn-ingressn-randomid-randomid.elb.us-west-2.amazonaws.com   80      2m4s

```

Now, you can access the Ray Dashboard from the Load balancer URL below.

    http://\<NLB_DNS_NAME\>/dashboard/#/serve

If you don't have access to a public Load Balancer, you can use port-forwarding and browse the Ray Dashboard using localhost with the following command:

```bash
kubectl port-forward svc/llama2-service 8265:8265 -n llama2

# Open the link in the browser
http://localhost:8265/

```

From this webpage, you will be able to monitor the progress of Model deployment, as shown in the image below:

![Ray Dashboard](img/ray-dashboard.png)

### To Test the Llama-2-Chat Model
Once you see the status of the model deployment is in `running` state then you can start using Llama-2-chat.

You can use the following URL with a query added at the end of the URL.

    http://\<NLB_DNS_NAME\>/serve/infer?sentence=what is data parallelism and tensor parallelisma and the differences

You will see an output like this in your browser:

![Chat Output](img/llama-2-chat-ouput.png)

## Deploying the Gradio WebUI App
Discover how to create a user-friendly chat interface using [Gradio](https://www.gradio.app/) that integrates seamlessly with deployed models.

Let's deploy Gradio app locally on your machine to interact with the LLama-2-Chat model deployed using RayServe.

:::info

The Gradio app interacts with the locally exposed service created solely for the demonstration. Alternatively, you can deploy the Gradio app on EKS as a Pod with Ingress and Load Balancer for wider accessibility.

:::

### Execute Port Forward to the llama2 Ray Service
First, execute a port forward to the Llama-2 Ray Service using kubectl:

```bash
kubectl port-forward svc/llama2-service 8000:8000 -n llama2
```

### Deploy Gradio WebUI Locally

#### Create a Virtual Environment
Create a Python virtual environment in your machine for the Gradio application:

```bash
cd ai-ml/trainium-inferentia/examples/gradio-ui
python3 -m venv .venv
source .venv/bin/activate
```

#### Install Gradio ChatBot app
Install all the Gradio WebUI app dependencies with pip

```bash
pip install gradio requests
```

#### Invoke the WebUI
Run the Gradio WebUI using the following command:

NOTE: `gradio-app.py` refers to the port forward url. e.g., `service_name = "http://localhost:8000" `

```bash
python gradio-app.py
```

You should see output similar to the following:

```text
Using cache from ~/data-on-eks/ai-ml/trainium-inferentia/examples/gradio-ui/gradio_cached_examples/16' directory. If method or examples have changed since last caching, delete this folder to clear cache.

Running on local URL:  http://127.0.0.1:7860

To create a public link, set `share=True` in `launch()`.
```

#### 2.4. Access the WebUI from Your Browser
Open your web browser and access the Gradio WebUI by navigating to the following URL:

http://127.0.0.1:7860

You should now be able to interact with the Gradio application from your local machine.

![Gradio Llama-2 AI Chat](img/gradio-llama-ai-chat.png)

## Conclusion
In conclusion, you will have successfully deployed the **Llama-2-13b chat** model on EKS with Ray Serve and created a chatGPT-style chat web UI using Gradio.
This opens up exciting possibilities for natural language processing and chatbot development.

In summary, when it comes to deploying and scaling Llama-2, AWS Trn1/Inf2 instances offer a compelling advantage.
They provide the scalability, cost optimization, and performance boost needed to make running large language models efficient and accessible, all while overcoming the challenges associated with the scarcity of GPUs.
Whether you're building chatbots, natural language processing applications, or any other LLM-driven solution, Trn1/Inf2 instances empower you to harness the full potential of Llama-2 on the AWS cloud.

## Cleanup
Finally, we'll provide instructions for cleaning up and deprovisioning the resources when they are no longer needed.

**Step1:** Cancel the execution of the `python gradio-app.py`

**Step2:** Delete Ray Cluster

```bash
cd ai-ml/trainium-inferentia/examples/ray-serve/llama2-inf2
kubectl delete -f ray-service-llama2.yaml
```

**Step3:** Cleanup the EKS Cluster
This script will cleanup the environment using `-target` option to ensure all the resources are deleted in correct order.

```bash
export AWS_DEAFULT_REGION="DEPLOYED_EKS_CLUSTER_REGION>"
cd data-on-eks/ai-ml/trainium-inferentia/ && chmod +x cleanup.sh
./cleanup.sh
```
