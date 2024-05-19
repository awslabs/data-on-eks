---
sidebar_position: 4
sidebar_label: RayTrain Llama2 on Trn1
---

import CollapsibleContent from '../../../src/components/CollapsibleContent';

:::danger

Note: Use of this Llama-2 model is governed by the Meta license.
In order to download the model weights and tokenizer, please visit the [website](https://ai.meta.com/) and accept the license before requesting access.

:::

:::info

We are actively enhancing this blueprint to incorporate improvements in observability, logging, and scalability aspects.

:::

# Llama2 Distributed Pre-training on Trn1 with RayTrain and KubeRay

This comprehensive guide walks you through pre-training the `Llama2-7B` language model using AWS Trainium (Trn1) instances and the AWS Neuron SDK within a KubeRay cluster on Amazon EKS. This is a tailored version of the original [Llama2 pretraining tutorial](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/neuronx-distributed/tutorials/training_llama2_7b.html#llama2-7b-tp-zero1-tutorial) optimized for KubeRay's distributed training capabilities.

### What is Llama-2?

Llama-2 is a state-of-the-art large language model (LLM) designed for various natural language processing (NLP) tasks, including text generation, summarization, translation, question answering, and more. It's a powerful tool that can be fine-tuned for specific use cases.

### Why RayTrain and KubeRay for Distributed Training?

Distributed training is essential for large models like Llama-2 due to their extensive computational and memory requirements. The combination of RayTrain and KubeRay, especially when leveraged with AWS Trainium, provides a robust framework for handling these demands efficiently and effectively:

#### RayTrain:
- **Simplified Distributed Training**: RayTrain is a high-level library built on the Ray framework that abstracts the complexities of distributed training. It allows you to scale your Llama-2 training across multiple nodes with minimal code changes. Ray's actor-based architecture and task-based parallelism enable efficient execution of distributed workloads.
- **Flexible Strategies**: RayTrain supports various distributed training strategies such as data parallelism and model parallelism. Data parallelism splits the dataset across multiple nodes, while model parallelism splits the model itself. This flexibility allows you to optimize training based on the specific needs of your model and the architecture of your training environment.
- **Fault Tolerance**: RayTrain includes built-in fault tolerance mechanisms. If a node fails, Ray can reschedule the tasks on other available nodes, ensuring that the training job continues without interruption. This feature is crucial for maintaining robustness in large-scale distributed training environments.
- **Ease of Use**: RayTrain offers intuitive APIs that simplify the setup and execution of distributed training jobs. Integrations with popular machine learning libraries like Hugging Face Transformers make it easier to incorporate RayTrain into your existing workflows without extensive modifications.

#### KubeRay:
- **Integration with Kubernetes**: KubeRay leverages Kubernetes' native capabilities to deploy, manage, and scale Ray clusters. This integration allows you to use Kubernetes' robust orchestration features to handle Ray workloads effectively.
- **Dynamic Scaling**: KubeRay supports dynamic scaling of Ray clusters. Ray's built-in autoscaler can request additional actor replicas based on workload demands, while Kubernetes tools like Karpenter or Cluster Autoscaler manage the creation of new nodes to meet these demands.
- **Horizontal Scaling**: Scale your Ray clusters horizontally by adding more worker nodes as the computational load increases. This allows efficient handling of large-scale distributed training and inference tasks.
- **Custom Resource Definitions (CRDs)**: KubeRay utilizes Kubernetes CRDs to define and manage Ray clusters and jobs. This provides a standardized way to handle Ray workloads within the Kubernetes ecosystem.
- **Fault Tolerance**: KubeRay takes advantage of Kubernetes' self-healing capabilities. If a Ray head node or worker node fails, Kubernetes automatically restarts the failed components, ensuring minimal downtime and continuous operation.
- **Distributed Scheduling**: Ray's actor-based model and distributed task scheduling, combined with Kubernetes' orchestration, ensure high availability and efficient task execution even in the event of node failures.
- **Declarative Configuration**: KubeRay allows you to define Ray clusters and jobs using declarative YAML configurations. This simplifies the deployment and management process, making it easier to set up and maintain Ray clusters.
- **Integrated Logging and Monitoring**: KubeRay integrates with Kubernetes' logging and monitoring tools, such as Prometheus and Grafana. This provides comprehensive insights into the performance and health of Ray clusters, facilitating easier debugging and optimization.
- **Spot Instances**: Use Kubernetes' support for spot instances to run Ray clusters cost-effectively. This allows you to take advantage of lower-cost compute resources while maintaining the ability to scale as needed.

#### AWS Trainium:
- **Optimized for Deep Learning**: AWS Trainium-based Trn1 instances are specifically designed for deep learning workloads. They offer high throughput and low latency, making them ideal for training large-scale models like Llama-2. Trainium chips provide significant performance improvements over traditional processors, accelerating training times.
- **Neuron SDK**: The AWS Neuron SDK is tailored to optimize your deep learning models for Trainium. It includes features like advanced compiler optimizations and support for mixed precision training, which can further accelerate your training workloads while maintaining accuracy.

### Why This Combination is Powerful
- **Simplified Scaling**: RayTrain and KubeRay simplify the process of scaling Llama-2 training across multiple nodes. With Ray's efficient distributed execution and KubeRay's Kubernetes-native orchestration, you can easily scale your training workloads to leverage the full power of AWS Trainium on Trn1 instances.
- **Optimized Performance**: The Neuron SDK enhances the performance of your training jobs by optimizing them specifically for Trainium's architecture. Combined with Ray's ability to efficiently manage distributed tasks and KubeRay's resource orchestration, this setup ensures optimal training performance.
- **Cost-Effective**: Ray's autoscaling capabilities and Kubernetes' resource management help you optimize costs by efficiently allocating resources and scaling your cluster based on demand. This ensures you only use the resources you need, reducing unnecessary expenditure.

By using this combination of technologies, you can take advantage of the latest advancements in distributed training and hardware to pre-train Llama-2 efficiently and effectively.


## 1. Deploying the Solution

<CollapsibleContent header={<h2><span>Prerequisites</span></h2>}>
    Before we begin, ensure you have all the prerequisites in place to make the deployment process smooth and hassle-free.
    Ensure that you have installed the following tools on your EC2 or Cloud9 instance.

:::info

    * [EC2 Instance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html) or [Cloud9 instance](https://docs.aws.amazon.com/cloud9/latest/user-guide/tutorial-create-environment.html) → Ensure you have 100GB+ of storage for both options. This is crucial for creating a Docker image with x86 architecture and having the right amount of storage.

    If you are using a local Windows machine or Mac, ensure you have Docker installed locally with builder storage above 100GB and the image is created with x86 architecture.

:::


    * [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
    * [kubectl](https://Kubernetes.io/docs/tasks/tools/)
    * [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

    To install all the pre-reqs on EC2, you can run this [script](https://github.com/sanjeevrg89/data-on-eks/blob/main/ai-ml/trainium-inferentia/examples/llama2/install-pre-requsites-for-ec2.sh) which is compatible with Amazon Linux 2023.


    **Clone the Data on EKS repository**

    ```bash
    git clone https://github.com/awslabs/data-on-eks.git
    ```

    **Navigate to the trainium-inferentia directory.**

    ```bash
    cd data-on-eks/ai-ml/trainium-inferentia
    ```

   Let's run the below export commands to set environment variables.

:::info

    **NOTE:** As of 2024/01/04 Trainium instances only available in us-west-2, us-east-1, and us-east-2 regions.

:::


    ```bash
    # Enable FSx for Lustre, which will mount pre-training data to all pods across multiple nodes
    export TF_VAR_enable_fsx_for_lustre=true

    # Set the region according to your requirements. Check Trn1 instance availability in the specified region.
    export TF_VAR_region=us-west-2

    # Note: This configuration will create two new Trn1 32xl instances. Ensure you validate the associated costs before proceeding.
    export TF_VAR_trn1_32xl_min_size=2
    export TF_VAR_trn1_32xl_desired_size=2
    ```

    Run the install script to provision an EKS cluster with all the add-ons needed for the solution.

    ```bash
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

## 2. Build the Docker Image

Build and push the custom Docker image containing KubeRay and Neuron components:

```bash
cd gen-ai/training/raytrain-llama2-pretrain-trn1
./1-kuberay-trn1-llama2-pretrain-build-image.sh
```
After running this script, note the Docker image URL and tag that are produced. You will need this information for the next step.

## 3. Launch the Ray Cluster with KubeRay Operator
Before launching the Ray cluster, update the `llama2-pretrain-kuberay.yaml` file with the Docker image URL and tag obtained from the previous step. Replace the placeholder(`<your-docker-image-url>:<your-docker-image-tag>`) values for the image URL and tag in the YAML file.

Once you have updated the YAML file, run the following command to launch the KubeRay cluster pods in your EKS cluster:

```bash
kubectl apply -f llama2-pretrain-trn1-raycluster.yaml
```

## 4. Prepare the Dataset
Run `kubectl get pods` and identify the name of one of the worker pods. Then run the following command (substituting in your worker pod name) to prepare/tokenize the wikicorpus dataset. The tokenized dataset will be stored on FSx storage that is accessible to the worker pods during training jobs. This step will take approximately 25 minutes.

```bash
kubectl exec -it <YOUR_WORKER_POD_NAME> -- python3 get_dataset.py
```

## 5. Run Precompilation Job

:::info

Currently, precompilation and training jobs are run from the RayHead pod. However, in the next iteration, this process will be improved to trigger the job using RayJob with KubeRay Operator, utilizing the existing RayClusters.

This enhancement will allow you to run both jobs without having to log in to the actual Ray head pod by using the `llama2-pretrain-trn1-rayjob.yaml` file.

:::

In this step, you will run a precompilation job where the Neuron SDK will identify, compile, and cache the compute graphs associated with Llama2 pretraining.

Run kubectl get pods and identify the name of your KubeRay head pod. Then run the following command (substituting in your head pod name) to launch the precompilation job:

```bash
kubectl exec -it <YOUR_HEAD_POD_NAME> -- ./launch_precompile_job.sh
```

## 6. Run Training Job

Now it is time to run the training job. Feel free to cancel the job using CTRL-C once you are convinced that the loss is decreasing and the model is learning.

```bash
kubectl exec -it <YOUR_HEAD_POD_NAME> -- ./launch_training_job.sh
```

### Cleaning up

To remove the resources created using this solution, run the cleanup script:

```bash
# Delete the RayCluster Resources:
cd gen-ai/training/raytrain-llama2-pretrain-trn1
kubectl delete -f llama2-pretrain-trn1-raycluster.yaml

# Clean Up the EKS Cluster and Associated Resources:
cd data-on-eks/ai-ml/trainium-inferentia
./cleanup.sh
```
