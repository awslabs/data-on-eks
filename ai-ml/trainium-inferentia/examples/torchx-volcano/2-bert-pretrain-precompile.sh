#!/bin/bash
read -p "Confirm that you have the 'lib' folder with 'trn1_dist_ddp.py' in the same directory (Y/N): " response
read -p "Enter the region (Should be the same as the region in variables.tf file): " region
read -p "Enter the ECR REPO (e.g., <AccountId>.dkr.ecr.<region>.amazonaws.com/eks_torchx_test): " ECR_REPO_URI
read -p "Enter the ECR TAG (e.g., bert_pretrain): " IMAGE_TAG

INSTANCE_TYPE="trn1.32xlarge"
# Login to ECR
echo -e "ECR Login with podman..."
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$ECR_REPO_URI"

torchx run \
    -s kubernetes --workspace="file:///$PWD/docker" \
    -cfg queue=test,image_repo=$ECR_REPO_URI lib/trn1_dist_ddp.py:generateAppDef \
    --name bertcompile \
    --script_args "--batch_size 16 --grad_accum_usteps 32 \
        --data_dir /data/bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128 \
        --output_dir /data/output --steps_this_run 10" \
    --nnodes 2 \
    --nproc_per_node 32 \
    --image $ECR_REPO_URI:$IMAGE_TAG \
    --script dp_bert_large_hf_pretrain_hdf5.py \
    --bf16 True \
    --cacheset bert-large \
    --precompile True \
    --instance_type $INSTANCE_TYPE