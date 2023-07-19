#!/bin/bash
read -p "Did you install Podman? If not, install it from here: https://podman.io/ (Y/N): " response

if [[ "$response" == "N" || "$response" == "n" ]]; then
    echo -e "Please install Podman before proceeding. Install it from here: https://podman.io/."
    exit 0
fi

read -p "Enter the region (Should be the same as the region in variables.tf file): " region

# Replace with your desired repository name and region
repository_name="eks_torchx_test"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$repository_name" --region "$region" >/dev/null 2>&1; then
  echo "ECR repository '$repository_name' already exists."

  # Get the REPO_URL for the existing repository
  REPO_URL=$(aws ecr describe-repositories --repository-name "$repository_name" --query 'repositories[0].repositoryUri' --region "$region" --output text)
  echo "Repository URL: $REPO_URL"
else
  # Create the ECR repository
  aws ecr create-repository --repository-name "$repository_name" --region "$region"

  # Get the REPO_URL for the newly created repository
  REPO_URL=$(aws ecr describe-repositories --repository-name "$repository_name" --query 'repositories[0].repositoryUri' --region "$region" --output text)
  echo "ECR repository '$repository_name' created successfully."
  echo "Repository URL: $REPO_URL"
fi

# Build and push the Docker image to ECR
# NOTE: If you hit error with 137 exit code, try increasing the memory of your Podman machine
#   podman machine stop
#   podman machine rm
#   podman machine init --cpus 2 --memory 4048
#   podman machine start

docker_image_tag="bert_pretrain"
echo -e "Building Docker image... $REPO_URL:$docker_image_tag"
podman build --arch amd64 -t "$REPO_URL:$docker_image_tag" -f Dockerfile.bert_pretrain .

# Tagging the Docker image
echo -e "Tagging Docker image... $REPO_URL:$docker_image_tag"
podman tag "$REPO_URL:$docker_image_tag" "$REPO_URL:$docker_image_tag"

# Login to ECR
echo -e "ECR Login with podman..."
aws ecr get-login-password --region "$region" | podman login --username AWS --password-stdin "$REPO_URL"

# Push the Docker image to ECR
echo -e "Pushing Docker image..."
podman push "$REPO_URL:$docker_image_tag"

# Sleep for 5 seconds
echo -e "Sleeping for 5 seconds..."
sleep 5


# ECR_REPO=$(aws ecr describe-repositories --repository-name "$repository_name" \
#     --query repositories[0].repositoryUri --output text)

# torchx run \
#     -s kubernetes --workspace="file:///$PWD/docker" \
#     -cfg queue=test,image_repo=$ECR_REPO \
#     lib/trn1_dist_ddp.py:generateAppDef \
#     --name bertcompile \
#     --script_args "--batch_size 16 --grad_accum_usteps 32 \
#         --data_dir /data/bert_pretrain_wikicorpus_tokenized_hdf5_seqlen128 \
#         --output_dir /data/output --steps_this_run 10" \
#     --nnodes 2 \
#     --nproc_per_node 32 \
#     --image $ECR_REPO:bert_pretrain \
#     --script dp_bert_large_hf_pretrain_hdf5.py \
#     --bf16 True \
#     --cacheset bert-large \
#     --precompile True \
#     --instance_type trn1.32xlarge