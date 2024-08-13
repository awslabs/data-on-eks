# Preload Container Images 

To preload the container images in EBS snapshots and launching them in an EKS cluster, using sample will use Bottlerocket AMIs for Amazon EKS.
You can use the generated EBS Snapshot to launch worker nodes in Amazon EKS Node Groups and Worker Nodes created by Karpenter.

For details, refer to the GitHub sample: 
https://github.com/aws-samples/bottlerocket-images-cache/tree/main

Usage Example: 

```
# Using nohup in terminals to avoid disconnections 
❯ nohup ./snapshot.sh --snapshot-size 200 -r us-west-2 docker.io/rayproject/ray-ml:2.10.0-py310-gpu,public.ecr.aws/data-on-eks/ray2.11.0-py310-gpu-stablediffusion:latest,docker.io/rayproject/ray:2.33.0-py311-gpu,public.ecr.aws/lindarr/ray-serve-gpu-stablediffusion:2.33.0-py311-gpu & 
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

You can copy the snapshot ID `snap-0c6d965cf431785ed` and move forward.
An end-to-end deployment example can be found in [JARK Stack](../terraform/README.md)

# With Karpenter

You can specify snapshot ID in a Karpenter node template. You should also specify AMI used when provisioning node is BottleRocket. Add the content on EC2NodeClass (or AWSNodeTemplate on older release of Karpenter):

v1beta1 API:
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
