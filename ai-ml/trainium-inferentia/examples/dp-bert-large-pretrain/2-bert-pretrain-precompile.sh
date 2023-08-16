#!/bin/bash

#--------------------------------------------------------------------------------
# Pre-requisites - Copy Training Wiki corpus dataset to FSx for Lustre
#--------------------------------------------------------------------------------
# kubectl and docker installed
# NOTE: This training dataset size is 30GB

# kubectl exec -i -t -n default aws-cli-cmd-shell -c app -- sh -c "clear; (bash || ash || sh)"
# yum install tar
# cd /data
# aws s3 cp s3://neuron-s3/training_datasets/bert_pretrain_wikicorpus_tokenized_hdf5/bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128.tar . --no-sign-request
# chmod 744 bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128.tar
# tar xvf bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128.tar
#--------------------------------------------------------------------------------
read -p "Did you configure kubeconfig (e.g., aws eks --region us-west-2 update-kubeconfig --name trainium-inferentia):  (y/n): " response
read -p "Confirm that you have the 'lib' folder with 'trn1_dist_ddp.py' in the same directory (y/n): " response
read -p "Enter the ECR REPO (e.g., <AccountId>.dkr.ecr.<region>.amazonaws.com/eks_torchx_test): " ECR_REPO_URI

#--------------------------------------------------------------------------------
# Install and configure docker-credential-ecr-login
# TorchX depends on the docker-credential-ecr-login helper to authenticate with your ECR repository in order to push/pull container images.
# Run the following commands to install and configure the credential helper:
mkdir -p ~/.docker
cat <<EOF > ~/.docker/config.json
{
    "credsStore": "ecr-login"
}
EOF

sudo yum install -y amazon-ecr-credential-helper
#--------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
# Use pip to install TorchX client on localhost or Cloud9 IDE
pip3 install torchx[kubernetes]
#--------------------------------------------------------------------------------

# Login to ECR
# aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$ECR_REPO_URI"

# Precompile the BERT graphs using neuron_parallel_compile
# PyTorch Neuron comes with a tool called neuron_parallel_compile which reduces graph compilation time by extracting model graphs and then compiling the graphs in parallel.
# The compiled graphs are stored on the shared storage volume where they can be accessed by the worker nodes during model training.
# To precompile the BERT graphs, run the following commands:

# Notice --steps_this_run 10 is used to run a small number of steps for testing purposes
torchx run \
    -s kubernetes --workspace="file:///$PWD/docker" \
    -cfg queue=test,image_repo=$ECR_REPO_URI lib/trn1_dist_ddp.py:generateAppDef \
    --name bertcompile \
    --script_args "--batch_size 16 --grad_accum_usteps 32 \
        --data_dir /data/bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128 \
        --output_dir /data/output --steps_this_run 10" \
    --nnodes 2 \
    --nproc_per_node 32 \
    --image $ECR_REPO_URI:bert_pretrain \
    --script dp_bert_large_hf_pretrain_hdf5.py \
    --bf16 True \
    --cacheset bert-large \
    --precompile True \
    --instance_type "trn1.32xlarge" \
    --node_selectors "provisioner=karpenter,instance-type=trn1-32xl,node.kubernetes.io/instance-type=trn1.32xlarge" \
    # --tolerations "aws.amazon.com/neuron=true:NoSchedule" # feature is not ready yet. Workingon a PR with TorchX repo check this issue https://github.com/pytorch/torchx/issues/753
