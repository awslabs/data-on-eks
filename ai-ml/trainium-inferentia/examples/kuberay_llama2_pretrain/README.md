# Introduction
This directory contains a Llama2-7B pretraining example which uses AWS EC2 trn1 instances and the AWS Neuron SDK running in KubeRay on Amazon EKS. This is based on the original [Llama2 pretraining tutorial](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/libraries/neuronx-distributed/tutorials/training_llama2_7b.html#llama2-7b-tp-zero1-tutorial) in the Neuron documentation with code modifications for KubeRay. 

# Prereqs
It is recommended to run this Data on EKS example from an x86-based Linux EC2 instance. If you try to run this code locally from your laptop you will likely encounter issues pushing the multi-GB docker image into ECR.

Please make sure that you have the following packages installed before proceeding:
* Terraform
* Helm
* AWS cli
* kubectl
* Docker
* git

# Setup EKS cluster
In this step you will use the Data on EKS trainium-inferentia recipe to launch an EKS cluster and associated resources. The EKS cluster will have a nodegroup containing AWS EC2 trn1 instances, and will already have the KubeRay operator pre-installed. An FSx for Lustre filesystem will also be created to provide a shared location for storing model artifacts, datasets, logs, Neuron cache, etc.
```
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks/ai-ml/trainium-inferentia

export TF_VAR_name=kuberay-trn1          # specify a name for your EKS cluster
export TF_VAR_region=us-east-2           # specify your desired region (us-west-2, us-east-1, or us-east-2)
export TF_VAR_trn1_32xl_min_size=2       # specify minimum trn1 nodegroup size
export TF_VAR_trn1_32xl_desired_size=2   # specify desired trn1 nodegroup size

./install.sh

# update kubectl config for your cluster
aws eks update-kubeconfig --name $TF_VAR_name --region $TF_VAR_region  
```

# Build the KubeRay + Neuron docker image
Run the following script to build the docker image and push it into ECR
```
cd examples/kuberay_llama2_pretrain
./1-kuberay-trn1-llama2-pretrain-build-image.sh
```

# Launch the KubeRay cluster
Run the following script to launch the KubeRay cluster pods in your EKS cluster
```
./2-launch-kuberay-cluster.sh
```

# Prepare the dataset
Run `kubectl get pods` and identify the name of one of the worker pods. Then run the following command (substituting-in your worker pod name) in order to prepare/tokenize the wikicorpus dataset. The tokenized dataset will be stored on FSx storage that is accessible to the worker pods during training jobs. This step will take ~25 minutes.
```
kubectl exec -it YOUR_WORKER_POD_NAME -- python3 get_dataset.py
```

# Run precompilation job
In this step, you will run a precompilation job in which the Neuron SDK will identify, compile, and cache the compute graphs associated with Llama2 pretraining.

Run `kubectl get pods` and identify the name of your KubeRay head pod. Then run the following command (substituting-in your head pod name) to launch the precompilation job:
```
kubectl exec -it YOUR_HEAD_POD_NAME -- ./launch_precompile_job.sh
```

# Run training job
Now it is time to run the training job. Feel free to cancel the job using CTRL-C once you are convinced that the loss is decreasing and the model is learning.
```
kubectl exec -it YOUR_HEAD_POD_NAME -- ./launch_training_job.sh
```

# Clean-up
When you are finished with the example, run the following commands to remove the cluster and related resources:
```
cd ../..
helm uninstall raycluster
./cleanup.sh
```
