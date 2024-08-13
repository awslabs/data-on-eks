---
title: Preload container images into Bottlerocket data volumes with Karpenter
sidebar_position: 2
---
import CollapsibleContent from '../../src/components/CollapsibleContent';

# Preload container images into Bottlerocket data volumes with Karpenter with EBS Snapshots

The purpose of this pattern is to reduce the cold start time of containers with large images by caching the images in the data volume of Bottlerocket OS.

Data analytics and machine learning workloads often require large container images (usually measured by Gigabytes), which can take several minutes to pull and extract from Amazon ECR or other image registry. Reduce image pulling time is the key of improving speed of launching these containers.

Bottlerocket OS is a Linux-based open-source operating system built by AWS specifically for running containers. It has two volumes, an OS volume and a data volume, with the latter used for storing artifacts and container images. This sample will leverage the data volume to pull images and take snapshots for later usage.

To demonstrate the process of caching images in EBS snapshots and launching them in an EKS cluster, this sample will use Amazon EKS optimized Bottlerocket AMIs.

For details, refer to the GitHub sample and blog post: 
https://github.com/aws-samples/bottlerocket-images-cache/tree/main
https://aws.amazon.com/blogs/containers/reduce-container-startup-time-on-amazon-eks-with-bottlerocket-data-volume/

## Overview of this script

![](img/bottlerocket-image-cache.png)

1. Launch an EC2 instance with Bottlerocket for EKS AMI.
2. Access to instance via Amazon System Manager
3. Pull images to be cached in this EC2 using Amazon System Manager Run Command.
4. Shut down the instance, build the EBS snapshot for the data volume.
5. Terminate the instance.

## Usage Example

```
git clone https://github.com/aws-samples/bottlerocket-images-cache/
cd bottlerocket-images-cache/

# Using nohup in terminals to avoid disconnections 
❯ nohup ./snapshot.sh --snapshot-size 150 -r us-west-2 \
  docker.io/rayproject/ray-ml:2.10.0-py310-gpu,public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest & 

❯ tail -f nohup.out 

2024-07-15 17:18:53 I - [1/8] Deploying EC2 CFN stack ...
2024-07-15 17:22:07 I - [2/8] Launching SSM .
2024-07-15 17:22:08 I - SSM launched in instance i-07d10182abc8a86e1.
2024-07-15 17:22:08 I - [3/8] Stopping kubelet.service ..
2024-07-15 17:22:10 I - Kubelet service stopped.
2024-07-15 17:22:10 I - [4/8] Cleanup existing images ..
2024-07-15 17:22:12 I - Existing images cleaned
2024-07-15 17:22:12 I - [5/8] Pulling images:
2024-07-15 17:22:12 I - Pulling docker.io/rayproject/ray-ml:2.10.0-py310-gpu - amd64 ... 
2024-07-15 17:27:50 I - docker.io/rayproject/ray-ml:2.10.0-py310-gpu - amd64 pulled. 
2024-07-15 17:27:50 I - Pulling docker.io/rayproject/ray-ml:2.10.0-py310-gpu - arm64 ... 
2024-07-15 17:27:58 I - docker.io/rayproject/ray-ml:2.10.0-py310-gpu - arm64 pulled. 
2024-07-15 17:27:58 I - Pulling public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest - amd64 ... 
2024-07-15 17:31:34 I - public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest - amd64 pulled. 
2024-07-15 17:31:34 I - Pulling public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest - arm64 ... 
2024-07-15 17:31:36 I - public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest - arm64 pulled. 
2024-07-15 17:31:36 I - [6/8] Stopping instance ... 
2024-07-15 17:32:25 I - Instance i-07d10182abc8a86e1 stopped
2024-07-15 17:32:25 I - [7/8] Creating snapshot ... 
2024-07-15 17:38:36 I - Snapshot snap-0c6d965cf431785ed generated.
2024-07-15 17:38:36 I - [8/8] Cleanup.
2024-07-15 17:38:37 I - Stack deleted.
2024-07-15 17:38:37 I - --------------------------------------------------
2024-07-15 17:38:37 I - All done! Created snapshot in us-west-2: snap-0c6d965cf431785ed
```

You can copy the snapshot ID `snap-0c6d965cf431785ed` and configure it as a snapshot for worker nodes.

# Using Snapshot with Amazon EKS and Karpenter

You can specify `snapshotID` in a Karpenter node class. Add the content on EC2NodeClass:

```
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: Bottlerocket # Ensure OS is BottleRocket
  blockDeviceMappings:
    - deviceName: /dev/xvdb
      ebs:
        volumeSize: 150Gi
        volumeType: gp3
        kmsKeyID: "arn:aws:kms:us-west-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab" # Specify KMS ID if you use custom KMS key
        snapshotID: snap-0123456789 # Specify your snapshot ID here
```

# End-to-End deployment example

An end-to-end deployment example can be found in [Stable Diffusion on GPU](https://awslabs.github.io/data-on-eks/docs/gen-ai/inference/stablediffusion-gpus).

### Clone the repository

```
git clone https://github.com/awslabs/data-on-eks.git
```

Important Note: Ensure that you update the region in the variables.tf file before deploying the blueprint. Additionally, confirm that your local region setting matches the specified region to prevent any discrepancies. For example, set your `export AWS_DEFAULT_REGION="<REGION>"` to the desired region:

### Reduce Cold Start Time by Preloading Container Images in Bottlerocket OS

Define the `TF_VAR_bottlerocket_data_disk_snpashot_id` to enable Karpenter to provision Bottlerocket worker nodes with EBS Snapshots, to reduce cold start for container startup. This will likely to save 10 mins (depending on the image size) for downloading and extracting container images from Amazon ECR.

```
export TF_VAR_bottlerocket_data_disk_snpashot_id=snap-0c6d965cf431785ed

cd data-on-eks/ai-ml/jark-stack/ && chmod +x install.sh
./install.sh
```

# Verify the resources
Verify the Amazon EKS Cluster

```
aws eks --region us-west-2 describe-cluster --name jark-stack

# Creates k8s config file to authenticate with EKS
aws eks --region us-west-2 update-kubeconfig --name jark-stack

# Output shows the EKS Managed Node group nodes
kubectl get nodes

## Deploying the Ray Cluster with Stable Diffusion Model
Ensure the cluster is configured locally

```bash
aws eks --region us-west-2 update-kubeconfig --name jark-stack
```

**Deploy RayServe Cluster**

```bash
cd ./../gen-ai/inference/stable-diffusion-rayserve-gpu
kubectl apply -f ray-service-stablediffusion.yaml
```

This deployment establishes a Ray head pod running on an x86 instance and a worker pod on a GPU G5 instance as shown below.

```bash
kubectl get pods -n stablediffusion

NAME                                                      READY   STATUS
rservice-raycluster-hb4l4-worker-gpu-worker-group-z8gdw   1/1     Running
stablediffusion-service-raycluster-hb4l4-head-4kfzz       2/2     Running
```
You can find the container image is preloaded into the disk disk.


```
kubectl describe pod

...
Events:
  Type     Reason            Age                From               Message
  ----     ------            ----               ----               -------
  Warning  FailedScheduling  41m                default-scheduler  0/8 nodes are available: 1 Insufficient cpu, 3 Insufficient memory, 8 Insufficient nvidia.com/gpu. preemption: 0/8 nodes are available: 8 No preemption victims found for incoming pod.
  Normal   Nominated         41m                karpenter          Pod should schedule on: nodeclaim/gpu-ljvhl
  Normal   Scheduled         40m                default-scheduler  Successfully assigned stablediffusion/stablediffusion-raycluster-ms6pl-worker-gpu-85d22 to ip-100-64-136-72.us-west-2.compute.internal
  Normal   Pulled            40m                kubelet            Container image "public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest" already present on machine
  Normal   Created           40m                kubelet            Created container wait-gcs-ready
  Normal   Started           40m                kubelet            Started container wait-gcs-ready
  Normal   Pulled            39m                kubelet            Container image "public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest" already present on machine
  Normal   Created           39m                kubelet            Created container worker
  Normal   Started           38m                kubelet            Started container worker
  ```

TODO: add benchmark results and the time save for downloading container images  