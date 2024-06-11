---
title: Mistral-7B on Inferentia
sidebar_position: 2
---
import CollapsibleContent from '../../../src/components/CollapsibleContent';

:::danger

Note: Mistral-7B-Instruct-v0.2 is a gated model in [Huggingface](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2) repository. In order to use this model, one needs to use a HuggingFace Token.
To generate a token in HuggingFace, log in using your HuggingFace account and click on `Access Tokens` menu item on the [Settings](https://huggingface.co/settings/tokens) page.

:::

# Deploying Mistral-7B-Instruct-v0.2 on Inferentia2, Ray Serve, Gradio
This pattern outlines the deployment of the [Mistral-7B-Instruct-v0.2](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2) model on Amazon EKS, utilizing [AWS Inferentia2](https://aws.amazon.com/ec2/instance-types/inf2/) for enhanced text generation performance. [Ray Serve](https://docs.ray.io/en/latest/serve/index.html) ensures efficient scaling of Ray Worker nodes, while [Karpenter](https://karpenter.sh/) dynamically manages the provisioning of AWS Inferentia2 nodes. This setup optimizes for high-performance and cost-effective text generation applications in a scalable cloud environment.

Through this pattern, you will accomplish the following:

- Create an [Amazon EKS](https://aws.amazon.com/eks/) cluster with a Karpenter managed AWS Inferentia2 nodepool for dynamic provisioning of Nodes.
- Install [KubeRay Operator](https://github.com/ray-project/kuberay) and other core EKS add-ons using the [trainium-inferentia](https://github.com/awslabs/data-on-eks/tree/main/ai-ml/trainium-inferentia) Terraform blueprint.
- Deploy the `Mistral-7B-Instruct-v0.2` model with RayServe for efficient scaling.

### What is Mistral-7B-Instruct-v0.2 Model?

The `mistralai/Mistral-7B-Instruct-v0.2` is an instruction-tuned version of the `Mistral-7B-v0.2 base model`, which has been fine-tuned using publicly available conversation datasets. It is designed to follow instructions and complete tasks, making it suitable for applications such as chatbots, virtual assistants, and task-oriented dialogue systems. It is built on top of the `Mistral-7B-v0.2` base model, which has 7.3 billion parameters and employs a state-of-the-art architecture including Grouped-Query Attention (GQA) for faster inference and a Byte-fallback BPE tokenizer for improved robustness.

Please refer to the [Model Card](https://replicate.com/mistralai/mistral-7b-instruct-v0.2/readme) for more detail.

## Deploying the Solution
Let's get `Mistral-7B-Instruct-v0.2` model up and running on Amazon EKS! In this section, we'll cover:

- **Prerequisites**: Ensuring all necessary tools are installed before you begin.
- **Infrastructure Setup**: Creating your your EKS cluster and setting the stage for deployment.
- **Deploying the Ray Cluster**: The core of your image generation pipeline, providing scalability and efficiency.
- **Building the Gradio Web UI**: Creating a user-friendly interface for seamless interaction with the Mistral 7B model.

<CollapsibleContent header={<h2><span>Prerequisites</span></h2>}>
Before we begin, ensure you have all the prerequisites in place to make the deployment process smooth and hassle-free.
Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [envsubst](https://pypi.org/project/envsubst/)
5. [jq](https://jqlang.github.io/jq/download/)

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
cd data-on-eks/ai-ml/trainium-inferentia/
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

# Output shows the EKS Managed Node group nodes
kubectl get nodes
```

</CollapsibleContent>

## Deploying the Ray Cluster with Mistral 7B Model

Once the `trainium-inferentia` EKS cluster is deployed, you can proceed to use `kubectl` to deploy the `ray-service-mistral.yaml` from `/data-on-eks/gen-ai/inference/mistral-7b-rayserve-inf2/` path.

In this step, we will deploy the Ray Serve cluster, which comprises one `Head Pod` on `x86 CPU` instances using Karpenter autoscaling, as well as `Ray workers` on `inf2.24xlarge` instances, autoscaled by [Karpenter](https://karpenter.sh/).

Let's take a closer look at the key files used in this deployment and understand their functionalities before proceeding with the deployment:
- **ray_serve_mistral.py:**
  This script sets up a FastAPI application with two main components deployed using Ray Serve, which enables scalable model serving on AWS Neuron infrastructure(Inf2):
  - **mistral-7b Deployment**: This class initializes the Mistral 7B model using a scheduler and moves it to an Inf2 node for processing. The script leverages Transformers Neuron support for grouped-query attention (GQA) models for this Mistral model. The `mistral-7b-instruct-v0.2` is a chat based model. The script also adds the required prefix for instructions by adding `[INST]` and `[/INST]` tokens surrounding the actual prompt.
  - **APIIngress**: This FastAPI endpoint acts as an interface to the Mistral 7B model. It exposes a GET method on the `/infer` path that takes a text prompt. It responds to the prompt by replying with a text.

- **ray-service-mistral.yaml:**
  This RayServe deployment pattern sets up a scalable service for hosting the Mistral-7B-Instruct-v0.2 Model model on Amazon EKS with AWS Inferentia2 support. It creates a dedicated namespace and configures a RayService with autoscaling capabilities to efficiently manage resource utilization based on incoming traffic. The deployment ensures that the model, served under the RayService umbrella, can automatically adjust replicas, depending on demand, with each replica requiring 2 neuron cores. This pattern makes use of custom container images designed to maximize performance and minimizes startup delays by ensuring that heavy dependencies are preloaded.

### Deploy the Mistral-7B-Instruct-v0.2 Model

Ensure the cluster is configured locally

```bash
aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia
```

**Deploy RayServe Cluster**

:::info

To deploy the Mistral-7B-Instruct-v0.2 model, it's essential to configure your Hugging Face Hub token as an environment variable. This token is required for authentication and accessing the model. For guidance on how to create and manage your Hugging Face tokens, please visit [Hugging Face Token Management](https://huggingface.co/docs/hub/security-tokens).

:::


```bash
# set the Hugging Face Hub Token as an environment variable. This variable will be substituted when applying the ray-service-mistral.yaml file

export HUGGING_FACE_HUB_TOKEN=$(echo -n "Your-Hugging-Face-Hub-Token-Value" | base64)

cd ./../gen-ai/inference/mistral-7b-rayserve-inf2
envsubst < ray-service-mistral.yaml| kubectl apply -f -
```

Verify the deployment by running the following commands

:::info

The deployment process may take up to 10 minutes. The Head Pod is expected to be ready within 2 to 3 minutes, while the Ray Serve worker pod may take up to 10 minutes for image retrieval and Model deployment from Huggingface.

:::

This deployment establishes a Ray head pod running on an `x86` instance and a worker pod on `inf2.24xl` instance as shown below.

```bash
kubectl get pods -n mistral

NAME                                                      READY   STATUS
service-raycluster-68tvp-worker-inf2-worker-group-2kckv   1/1     Running
mistral-service-raycluster-68tvp-head-dmfz5               2/2     Running
```

This deployment also sets up a mistral service with multiple ports configured; port `8265` is designated for the Ray dashboard and port `8000` for the Mistral model endpoint.

```bash
kubectl get svc -n mistral

NAME                        TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)
mistral-service             NodePort   172.20.118.238   <none>        10001:30998/TCP,8000:32437/TCP,52365:31487/TCP,8080:30351/TCP,6379:30392/TCP,8265:30904/TCP
mistral-service-head-svc    NodePort   172.20.245.131   <none>        6379:31478/TCP,8265:31393/TCP,10001:32627/TCP,8000:31251/TCP,52365:31492/TCP,8080:31471/TCP
mistral-service-serve-svc   NodePort   172.20.109.223   <none>        8000:31679/TCP
```

For the Ray dashboard, you can port-forward these ports individually to access the web UI locally using localhost.



```bash
kubectl -n mistral port-forward svc/mistral-service 8265:8265
```

Access the web UI via `http://localhost:8265` . This interface displays the deployment of jobs and actors within the Ray ecosystem.

![RayServe Deployment In Progress](img/ray-dashboard-deploying-mistral-inf2.png)

Once the deployment is complete, the Controller and Proxy status should be `HEALTHY` and Application status should be `RUNNING`

![RayServe Deployment Completed](img/ray-dashboard-deployed-mistral-inf2.png)


You can monitor Serve deployment and the Ray Cluster deployment including resource utilization using the Ray Dashboard.

![RayServe Cluster](img/ray-serve-inf2-mistral-cluster.png)

## Deploying the Gradio WebUI App

[Gradio](https://www.gradio.app/) Web UI is used to interact with the Mistral7b inference service deployed on EKS Clusters using inf2 instances.
The Gradio UI communicates internally with the mistral service(`mistral-serve-svc.mistral.svc.cluster.local:8000`), which is exposed on port `8000`, using its service name and port.

We have created a base Docker(`gen-ai/inference/gradio-ui/Dockerfile-gradio-base`) image for the Gradio app, which can be used with any model inference.
This image is published on [Public ECR](https://gallery.ecr.aws/data-on-eks/gradio-web-app-base).

#### Steps to Deploy a Gradio App:

The following YAML script (`gen-ai/inference/mistral-7b-rayserve-inf2/gradio-ui.yaml`) creates a dedicated namespace, deployment, service, and a ConfigMap where your model client script goes.

To deploy this, execute:

```bash
cd gen-ai/inference/mistral-7b-rayserve-inf2/
kubectl apply -f gradio-ui.yaml
```

**Verification Steps:**
Run the following commands to verify the deployment, service, and ConfigMap:

```bash
kubectl get deployments -n gradio-mistral7b-inf2

kubectl get services -n gradio-mistral7b-inf2

kubectl get configmaps -n gradio-mistral7b-inf2
```

**Port-Forward the Service:**

Run the port-forward command so that you can access the Web UI locally:

```bash
kubectl port-forward service/gradio-service 7860:7860 -n gradio-mistral7b-inf2
```

#### Invoke the WebUI

Open your web browser and access the Gradio WebUI by navigating to the following URL:

Running on local URL:  http://localhost:7860

You should now be able to interact with the Gradio application from your local machine.

![Gradio WebUI](img/mistral-gradio.png)

#### Interaction With Mistral Model

`Mistral-7B-Instruct-v0.2` Model can be used for purposes such as chat applications (Q&A, conversation), text generation, knowledge retrieval and others.

Below screenshots provide some examples of the model response based on different text prompts.

![Gradio QA](img/mistral-sample-prompt-1.png)

![Gradio Convo 1](img/mistral-conv-1.png)

![Gradio Convo 2](img/mistral-conv-2.png)


### Ray Head Node High Availability With Elastic Cache for Redis

A critical component of a Ray cluster is the head node, which orchestrates the entire cluster by managing task scheduling, state synchronization, and node coordination. However, by default, the Ray head Pod represents a single point of failure; if it fails, the entire cluster including the Ray worker Pods need to be restarted.

To address this, High Availability (HA) for the Ray head node is essential. Global Control Service (GCS) manages cluster-level metadata in a RayCluster. By default, the GCS lacks fault tolerance as it stores all data in-memory, and a failure can cause the entire Ray cluster to fail. To avoid this, one must add fault tolerance to Ray’s Global Control Store (GCS), which allows the Ray Serve application to serve traffic even when the head node crashes. In the event of a GCS restart, it retrieves all the data from the Redis instance and resumes its regular functions.

Folloiwng sections provide the steps on how to enable GCS fault tolerance and ensure high availability for the Ray head Pod.

#### Add an External Redis Server

GCS fault tolerance requires an external Redis database. You can choose to host your own Redis database, or you can use one through a third-party vendor.

For development and testing purposes, you can also host a containerized Redis database on the same EKS cluster as your Ray cluster. However, for production setups, it's recommended to use a highly available external Redis cluster. In this pattern, we've used [Amazon ElasticCache for Redis](https://aws.amazon.com/elasticache/redis/) to create an external Redis cluster.

As part of the current blueprint, we've added a terraform module named `elasticache` that creates an Elastic Cache Redis cluster in AWS. This uses The Redis cluster has cluster mode disabled and contain one node. This cluster node's endpoint can be used for both reads and writes.

Key things to note in this module are -

- The Redis Cluster is in the same VPC as the EKS cluster. If the Redis cluster is created in a separate VPC, then VPC peering needs to be set up between the EKS cluster VPC and the Elastic Cache Redis cluster VPC to enable network connectivity.
- A cache subnet group needs to be created at the time of creating the Redis cluster. A subnet group is a collection of subnets that you may want to designate for your caches in a VPC. ElastiCache uses that cache subnet group to assign IP addresses within that subnet to each cache node in the cache. The blueprint automatically adds all the subnets used by the EKS cluster in the subnet group for the Elastic cache Redis cluster.
- Security Group - The Security Group assigned to the Redis cache needs to have an inbound rule that allows TCP traffic from EKS Cluster's worker node security group to the Redis cluster security group over port 6379. This is because the Ray head Pod needs to establish a connection to the Elastic cache Redis cluster over port 6379. The blueprint automatically sets up the security group with the inbound rule.

To create the Redis cluster using Amazon Elastic Cache, please follow the below steps.

First, enable the creation of the Redis cluster by setting the `enable_rayserve_ha_elastic_cache_redis` variable to `true` in `variables.tf` file. By default it's set to `false`.

Then, run the `terraform apply --auto-approve` command.

```bash
cd ai-ml/trainimum-inferentia
terraform apply --auto-approve
```

This creates the AWS Elastic Cache Redis Cluster. Sample output looks like below

```text
Apply complete! Resources: 8 added, 1 changed, 0 destroyed.

Outputs:

configure_kubectl = "aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia"
elastic_cache_redis_cluster_arn = "arn:aws:elasticache:us-west-2:489829964455:cluster:trainium-inferentia"
```

#### Add External Redis Information to RayService

Once the elastic cache Redis cluster is created, we need to modify the `RayService` configuration for `mistral-7b` model inference.

First we need to obtain the Elastic Cache Redis Cluster endpoint by using AWS CLI and jq like below.

```bash
export EXT_REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id "trainium-inferentia" \
    --show-cache-node-info | jq -r '.CacheClusters[0].CacheNodes[0].Endpoint.Address')
```

Now, add the annotation `ray.io/ft-enabled: "true"` under `RayService` CRD. The annotation `ray.io/ft-enabled` enables GCS fault tolerance when set to `true`.

```yaml
apiVersion: ray.io/v1
kind: RayService
metadata:
  name: mistral
  namespace: mistral
  annotations:
    ray.io/ft-enabled: "true"
```

Add the external Redis cluster information in the `headGroupSpec` as `RAY_REDIS_ADDRESS` environment variable.

```yaml
headGroupSpec:
  headService:
    metadata:
      name: mistral
      namespace: mistral
  rayStartParams:
    dashboard-host: '0.0.0.0'
    num-cpus: "0"
  template:
    spec:
      containers:
      - name: head
        ....
        env:
          - name: RAY_REDIS_ADDRESS
            value: $EXT_REDIS_ENDPOINT:6379
```

`RAY_REDIS_ADDRESS`’s value should be your Redis database’s address. It should contain the Redis cluster endpoint and the port.

You can find the full `RayService` configuration with GCS fault tolerance enabled in `gen-ai/inference/mistral-7b-rayserve-inf2/ray-service-mistral-ft.yaml` file.

With the above `RayService` configuration, we have enabled GCS fault tolerance for the Ray head Pod and the Ray cluster can recover from head Pod crashes without restarting all the Ray workers.

Let's apply the above `RayService` configuration and check the behavior.

```bash
cd ../../gen-ai/inference/
envsubst < mistral-7b-rayserve-inf2/ray-service-mistral-ft.yaml| kubectl apply -f -
```

The output should look like below

```text
namespace/mistral created
secret/hf-token created
rayservice.ray.io/mistral created
ingress.networking.k8s.io/mistral created
```

Check the status of the Ray Pods in the cluster.

```bash
kubectl get po -n mistral
```

The Ray head and worker Pods should be in `Running` state as below.

```text
NAME                                         READY   STATUS    RESTARTS   AGE
mistral-raycluster-rf6l9-head-hc8ch          2/2     Running   0          31m
mistral-raycluster-rf6l9-worker-inf2-tdrs6   1/1     Running   0          31m
```

Simulate Ray head Pod crashing by deleting the Pod

```bash
kubectl -n mistral delete po mistral-raycluster-rf6l9-head-xxxxx
pod "mistral-raycluster-rf6l9-head-xxxxx" deleted
```

We can see that the Ray worker Pod is still running when the Ray head Pod is terminated and auto-restarted. Please see the below screenshots from Lens IDE.

![Head Pod Deletion](img/head-pod-deleted.png)


![Worker Pod Uninterrupted](img/worker-pod-running.png)

#### Test the Gradio App

Let's also test our Gradio UI App to see whether it's able to answer questions while the Ray head Pod is deleted.

Open the Gradio Mistral AI Chat application by pointing your browser to localhost:7860.

Now repeat the Ray head Pod crash simulation by deleting the Ray head Pod as shown in the above steps.

While the Ray head Pod is terminated and is recovering, submit questions into the Mistral AI Chat interface. We can see from below screenshots that the chat application is indeed able to serve traffic while the Ray head Pod is deleted and is recovering. This is because the RayServe service points to the Ray worker Pod which in this case is never restarted because of the GCS fault tolerance.

![Gradio App Test HA](img/gradio-test-ft.png)

![Gradio App Test 1](img/answer-1.png)

![Gradio App Test Contd](img/answer-1-contd.png)

For a complete guide on enabling end-to-end fault tolerance to your RayServe application, please refer to [Ray Guide](https://docs.ray.io/en/latest/serve/production-guide/fault-tolerance.html#add-end-to-end-fault-tolerance).

## Cleanup

Finally, we'll provide instructions for cleaning up and deprovisioning the resources when they are no longer needed.

**Step1:** Delete Gradio App and mistral Inference deployment


```bash
cd gen-ai/inference/mistral-7b-rayserve-inf2
kubectl delete -f gradio-ui.yaml
kubectl delete -f ray-service-mistral.yaml
```

**Step2:** Cleanup the EKS Cluster
This script will cleanup the environment using `-target` option to ensure all the resources are deleted in correct order.

```bash
cd ../../../ai-ml/trainium-inferentia/
./cleanup.sh
```
