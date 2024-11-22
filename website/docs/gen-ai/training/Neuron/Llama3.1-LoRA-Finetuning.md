---
sidebar_position: 1
sidebar_label: Llama-3 with RayTrain on Trn1
---
import CollapsibleContent from '../../../../src/components/CollapsibleContent';

:::warning
Deployment of ML models on EKS requires access to GPUs or Neuron instances. If your deployment isn't working, it’s often due to missing access to these resources. Also, some deployment patterns rely on Karpenter autoscaling and static node groups; if nodes aren't initializing, check the logs for Karpenter or Node groups to resolve the issue.
:::

:::danger

Note: Use of this Llama-3 model is governed by the Meta license.
In order to download the model weights and tokenizer, please visit the [website](https://ai.meta.com/) and accept the license before requesting access.

:::

:::info

We are actively enhancing this blueprint to incorporate improvements in observability, logging, and scalability aspects.

:::

# Llama3 Distributed Pre-training on Trn1 with RayTrain and KubeRay

This comprehensive guide walks you through fine-tuning the `Llama3-8B` language model using AWS Trainium (Trn1) EC2 instance.

### What is Llama-3?

Llama-3 is a state-of-the-art large language model (LLM) designed for various natural language processing (NLP) tasks, including text generation, summarization, translation, question answering, and more. It's a powerful tool that can be fine-tuned for specific use cases.

#### AWS Trainium:
- **Optimized for Deep Learning**: AWS Trainium-based Trn1 instances are specifically designed for deep learning workloads. They offer high throughput and low latency, making them ideal for training large-scale models like Llama-3. Trainium chips provide significant performance improvements over traditional processors, accelerating training times.
- **Neuron SDK**: The AWS Neuron SDK is tailored to optimize your deep learning models for Trainium. It includes features like advanced compiler optimizations and support for mixed precision training, which can further accelerate your training workloads while maintaining accuracy.

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

    To install all the pre-reqs on EC2, you can run this [script](https://github.com/awslabs/data-on-eks/blob/main/ai-ml/trainium-inferentia/examples/llama2/install-pre-requsites-for-ec2.sh) which is compatible with Amazon Linux 2023.


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
    export TF_VAR_trn1_32xl_min_size=1
    export TF_VAR_trn1_32xl_desired_size=1
    ```

    Run the installation script to provision an EKS cluster with all the add-ons needed for the solution.

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

## 2. Build the Docker Image (Optional Step)

To simplify the blueprint deployment, we have already built the Docker image and made it available under the public ECR.
If you want to customize the Docker image, you can update the `Dockerfile` and follow the optional step to build the Docker image.
Please note that you will also need to modify the YAML file, `lora-finetune-pod.yaml`, with the newly created image using your own private ECR.

```bash
cd gen-ai/training/raytrain-llama2-pretrain-trn1
./kuberay-trn1-llama2-pretrain-build-image.sh
```
After running this script, note the Docker image URL and tag that are produced.
You will need this information for the next step.

## 3. Generate Pre-training Data on FSx Shared Filesystem

:::warning

Data generation step can take up to 20 minutes to create all the data in FSx for Lustre.

:::


In this step, we'll leverage KubeRay's Job specification to kickstart the data generation process. We'll submit a job directly to the Ray head pod. This job plays a key role in preparing your model for training.

Check out the `RayJob` definition spec below to leverage the existing RayCluster using `clusterSelector` to submit the jobs to RayCluster.


```yaml
# ----------------------------------------------------------------------------
# RayJob: llama2-generate-pretraining-test-data
#
# Description:
# This RayJob is responsible for generating pre-training test data required for
# the Llama2 model training. It sources data from the specified dataset, processes
# it, and prepares it for use in subsequent training stages. The job runs a Python
# script (`get_dataset.py`) that performs these data preparation steps.

# Usage:
# Apply this configuration to your Kubernetes cluster using `kubectl apply -f 1-llama2-pretrain-trn1-rayjob-create-test-data.yaml`.
# Ensure that the Ray cluster (`kuberay-trn1`) is running and accessible in the specified namespace.
# ----------------------------------------------------------------------------

apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: llama2-generate-pretraining-test-data
  namespace: default
spec:
  submissionMode: K8sJobMode
  entrypoint: "python3 get_dataset.py"
  runtimeEnvYAML: |
    working_dir: /llama2_pretrain
    env_vars:
      PYTHONUNBUFFERED: '0'
    resources:
      requests:
        cpu: "6"
        memory: "30Gi"
  clusterSelector:
    ray.io/cluster: kuberay-trn1
    rayClusterNamespace: default  # Replace with the namespace where your RayCluster is deployed
  ttlSecondsAfterFinished: 60  # Time to live for the pod after completion (in seconds)
```

Execute the following command to run the Test Data creation Ray job:


```bash
kubectl apply -f 1-llama2-pretrain-trn1-rayjob-create-test-data.yaml
```

**What Happens Behind the Scenes:**

**Job Launch:** You'll use kubectl to submit the KubeRay job specification. The Ray head pod in your `kuberay-trn1` cluster receives and executes this job.

**Data Generation:** The job runs the `gen-ai/training/raytrain-llama2-pretrain-trn1/llama2_pretrain/get_dataset.py` script, which harnesses the power of the Hugging Face datasets library to fetch and process the raw English Wikipedia dataset ("wikicorpus").

**Tokenization:** The script tokenizes the text using a pre-trained tokenizer from Hugging Face transformers. Tokenization breaks down the text into smaller units (words or subwords) for the model to understand.

**Data Storage:** The tokenized data is neatly organized and saved to a specific directory (`/shared/wikicorpus_llama2_7B_tokenized_4k/`) within your FSx for Lustre shared filesystem. This ensures all worker nodes in your cluster can readily access this standardized data during pre-training.

### Monitoring the Job:

To keep tabs on the job's progress:

**Ray Dashboard**: Head over to the Ray dashboard, accessible via your Ray head pod's IP address and port 8265. You'll see real-time updates on the job's status.


![Prepare the Dataset](../img/raytrain-testdata-raydash1.png)

![Prepare the Dataset](../img/raytrain-testdata-raydash2.png)

![Prepare the Dataset](../img/raytrain-testdata-raydash3.png)

Alternatively, you can use the following command in your terminal:

```bash
kubectl get pods | grep llama2
```

**Output:**

```
llama2-generate-pretraining-test-data-g6ccl   1/1     Running   0             5m5s
```

The following screenshot taken from Lens K8s IDE to show the logs of the pod.

![Prepare the Dataset](../img/raytrain-testdata-lens.png)

## 5. Run Pre-compilation Job (Optimization Step)

:::info

Pre-compilation job can take upto 6 min

:::

Before starting the actual training, we'll perform a pre-compilation step to optimize the model for the Neuron SDK. This helps the model run more efficiently on the `Trn1` instances. This script will use the Neuron SDK to compile and optimize the model's computational graph, making it ready for efficient training on the Trn1 processors.

In this step, you will run a pre-compilation job where the Neuron SDK will identify, compile, and cache the compute graphs associated with `Llama2` pretraining.

Check out the `RayJob` definition spec below to run the pre-compilation job:

```yaml
# ----------------------------------------------------------------------------
# RayJob: llama2-precompilation-job
#
# Description:
# This RayJob is responsible for the pre-compilation step required for the Llama2 model
# training. It runs a Python script (`ray_train_llama2.py`) with the `--neuron_parallel_compile`
# option to compile the model in parallel using AWS Neuron devices. This step is crucial for
# optimizing the model for efficient training on AWS infrastructure.

# Usage:
# Apply this configuration to your Kubernetes cluster using `kubectl apply -f 2-llama2-pretrain-trn1-rayjob-precompilation.yaml`.
# Ensure that the Ray cluster (`kuberay-trn1`) is running and accessible in the specified namespace.
# ----------------------------------------------------------------------------

---
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: llama2-precompilation-job
  namespace: default
spec:
  submissionMode: K8sJobMode
  entrypoint: "NEURON_NUM_DEVICES=32 python3 /llama2_pretrain/ray_train_llama2.py --neuron_parallel_compile"
  runtimeEnvYAML: |
    working_dir: /llama2_pretrain
    env_vars:
      PYTHONUNBUFFERED: '0'
  clusterSelector:
    ray.io/cluster: kuberay-trn1
    rayClusterNamespace: default  # Replace with the namespace where your RayCluster is deployed
  ttlSecondsAfterFinished: 60  # Time to live for the pod after completion (in seconds)
```

Execute the following command to run the pre-compilation job:

```bash
kubectl apply -f 2-llama2-pretrain-trn1-rayjob-precompilation.yaml
```

**Verification Steps:**

To monitor the job's progress and verify that it is running correctly, use the following commands and tools:

**Ray Dashboard:** Access the Ray dashboard via your Ray head pod's IP address and port `8265` to see real-time updates on the job's status.

![Precompilation progress](../img/raytrain-precomplilation1.png)

![Precompilation progress](../img/raytrain-precomplilation2.png)

The following screenshot taken from Lens K8s IDE to show the logs of the pod.

![Precompilation progress](../img/raytrain-precomplilation3.png)

## 6. Run Distributed Pre-training Job

:::warning

This job can run for many hours so feel free to cancel the job using Ctrl+C once you are convinced that the loss is decreasing and the model is learning.

:::

Now, you're ready to begin the actual training of the Llama 2 model! This step involves running the distributed pre-training job using a RayJob. The job will utilize AWS Neuron devices to efficiently train the model with the prepared dataset.

Check out the `RayJob` definition spec below to run the pretraining job:

```yaml
# ----------------------------------------------------------------------------
# RayJob: llama2-pretraining-job
#
# Description:
# This RayJob is responsible for the main pretraining step of the Llama2 model.
# It runs a Python script (`ray_train_llama2.py`) to perform the pretraining using AWS Neuron devices.
# This step is critical for training the language model with the prepared dataset.

# Usage:
# Apply this configuration to your Kubernetes cluster using `kubectl apply -f 3-llama2-pretrain-trn1-rayjob.yaml`.
# Ensure that the Ray cluster (`kuberay-trn1`) is running and accessible in the specified namespace.
# ----------------------------------------------------------------------------

---
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: llama2-pretraining-job
  namespace: default
spec:
  submissionMode: K8sJobMode
  entrypoint: "NEURON_NUM_DEVICES=32 python3 ray_train_llama2.py"
  runtimeEnvYAML: |
    working_dir: /llama2_pretrain
    env_vars:
      PYTHONUNBUFFERED: '0'
  clusterSelector:
    ray.io/cluster: kuberay-trn1
    rayClusterNamespace: default  # Replace with the namespace where your RayCluster is deployed
  shutdownAfterJobFinishes: true
  activeDeadlineSeconds: 600   # The job will be terminated if it runs longer than 600 seconds (10 minutes)
  ttlSecondsAfterFinished: 60  # Time to live for the pod after completion (in seconds)
```

Execute the following command to run the pretraining job:

```bash
kubectl apply -f 3-llama2-pretrain-trn1-rayjob.yaml
```

**Monitor Progress:**

You can monitor the progress of the training job using the Ray Dashboard or by observing the logs output to your terminal. Look for information like the training loss, learning rate, and other metrics to assess how well the model is learning.

![Training Progress](../img/raytrain-training-progress1.png)

**Ray Dashboard:** Access the Ray dashboard via your Ray head pod's IP address and port 8265 to see real-time updates on the job's status.

![Training Progress Ray Dashboard](../img/raytrain-training-progress2.png)

![Training Progress Ray Dashboard](../img/raytrain-training-progress3.png)


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
