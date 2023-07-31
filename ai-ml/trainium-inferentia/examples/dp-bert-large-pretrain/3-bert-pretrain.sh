#!/bin/bash

# NOTE: This training dataset size is 30GB stored in FSx for Lustre
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
# Use pip to install TorchX on the jump host:
# pip3 install torchx[kubernetes]
#--------------------------------------------------------------------------------

INSTANCE_TYPE="trn1.32xlarge"

# Notice --steps_this_run 10 is used to run a small number of steps for testing purposes
torchx run \
    -s kubernetes --workspace="file:///$PWD/docker" \
    -cfg queue=test,image_repo=$ECR_REPO_URI lib/trn1_dist_ddp.py:generateAppDef \
    --name berttrain \
    --script_args "--batch_size 16 --grad_accum_usteps 32 \
        --data_dir /data/bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128 \
        --output_dir /data/output" \
    --nnodes 2 \
    --nproc_per_node 32 \
    --image $ECR_REPO_URI:bert_pretrain \
    --script dp_bert_large_hf_pretrain_hdf5.py \
    --bf16 True \
    --cacheset bert-large \
    --instance_type $INSTANCE_TYPE
