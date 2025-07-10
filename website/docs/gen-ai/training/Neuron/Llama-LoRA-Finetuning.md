---
sidebar_position: 1
sidebar_label: Llama-3 with RayTrain on Trn1
---
import CollapsibleContent from '../../../../src/components/CollapsibleContent';

:::caution

The **AI on EKS** content **is being migrated** to a new repository.
🔗 👉 [Read the full migration announcement »](https://awslabs.github.io/data-on-eks/docs/migration/migration-announcement)

:::

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

# Llama3 fine-tuning on Trn1 with HuggingFace Optimum Neuron

This comprehensive guide walks you through the steps for fine-tuning the `Llama3-8B` language model using AWS Trainium (Trn1) EC2 instances. The fine-tuning process is facilitated by HuggingFace Optimum Neuron, a powerful library that simplifies the integration of Neuron into your training pipeline.

### What is Llama-3?

Llama-3 is a state-of-the-art large language model (LLM) designed for various natural language processing (NLP) tasks, including text generation, summarization, translation, question answering, and more. It's a powerful tool that can be fine-tuned for specific use cases.

#### AWS Trainium:
- **Optimized for Deep Learning**: AWS Trainium-based Trn1 instances are specifically designed for deep learning workloads. They offer high throughput and low latency, making them ideal for training large-scale models like Llama-3. Trainium chips provide significant performance improvements over traditional processors, accelerating training times.
- **Neuron SDK**: The AWS Neuron SDK is tailored to optimize your deep learning models for Trainium. It includes features like advanced compiler optimizations and support for mixed precision training, which can further accelerate your training workloads while maintaining accuracy.

## 1. Deploying the Solution

<CollapsibleContent header={<h2><span>Prerequisites</span></h2>}>
    Before we begin, ensure you have all the prerequisites in place to make the deployment process smooth and hassle-free.
    Ensure that you have installed the following tools on your EC2 instance.

:::info

    * [EC2 Instance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html) → Ensure you have 100GB+ of storage for both options. This is crucial for creating a Docker image with x86 architecture and having the right amount of storage.

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

    **NOTE:** Trainium instances are available in select regions, and the user can determine this list of regions using the commands outlined [here](https://repost.aws/articles/ARmXIF-XS3RO27p0Pd1dVZXQ/what-regions-have-aws-inferentia-and-trainium-instances) on re:Post.

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

To simplify the blueprint deployment, we have already built the Docker image and made it available under the public ECR. If you want to customize the Docker image, you can update the `Dockerfile` and follow the optional step to build the Docker image. Please note that you will also need to modify the YAML file, `lora-finetune-pod.yaml`, with the newly created image using your own private ECR.

Execute the below commands after ensuring you are in the root folder of the data-on-eks repository.

```bash
cd gen-ai/training/llama-lora-finetuning-trn1
./build-container-image.sh
```
After running this script, note the Docker image URL and tag that are produced.
You will need this information for the next step.

## 3. Launch the Llama training pod

If you skip step 2, you don't need to modify the YAML file.
You can simply run the `kubectl apply` command on the file, and it will use the public ECR image that we published.

If you built a custom Docker image in **Step 2**, update the `gen-ai/training/llama-lora-finetuning-trn1/lora-finetune-pod.yaml` file with the Docker image URL and tag obtained from the previous step.

Once you have updated the YAML file (if needed), run the following command to launch the pod in your EKS cluster:

```bash
kubectl apply -f lora-finetune-pod.yaml
```

**Verify the Pod Status:**

```bash
kubectl get pods

```

## 4. Launch LoRA fine-tuning

Once the pod is ‘Running’, connect to it using the following command:

```bash
kubectl exec -it lora-finetune-app -- /bin/bash
```

Before running the launch script `01__launch_training.sh`, you need to set an environment variable with your HuggingFace token. The access token is found under Settings → Access Tokens on the Hugging Face website.

```bash
export HF_TOKEN=<your-huggingface-token>

./01__launch_training.sh
```

Once the script is complete, you can verify the training progress by checking the logs of the training job.

Next, we need to consolidate the adapter shards and merge the model. For this we run the python script `02__consolidate_adapter_shards_and_merge_model.py` by passing in the location of the checkpoint using the '-i' parameter and providing the location where you want to save the consolidated model using the '-o' parameter.
```
python3 ./02__consolidate_adapter_shards_and_merge_model.py -i /shared/finetuned_models/20250220_170215/checkpoint-250/ -o /shared/tuned_model/20250220_170215
```

Once the script is complete, we can test the fine-tuned model by running the `03__test_model.py` by passing in the location of the tuned model using the '-m' parameter.
```bash
./03__test_model.py -m /shared/tuned_model/20250220_170215
```

You can exit from the interactive terminal of the pod once you are done testing the model.

### Cleaning up

To remove the resources created using this solution, execute the below commands after ensuring you are in the root folder of the data-on-eks repository.:

```bash
# Delete the Kubernetes Resources:
cd gen-ai/training/llama-lora-finetuning-trn1
kubectl delete -f lora-finetune-pod.yaml

# Clean Up the EKS Cluster and Associated Resources:
cd ../../../ai-ml/trainium-inferentia
./cleanup.sh
```
