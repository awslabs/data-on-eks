#!/bin/bash

export stack_name="${1:-emr-roadshow}"

# 0. Setup AWS environment
echo "Setup AWS environment ..."
sudo yum -y install jq
export AWS_REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region)
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)

echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region

# don't need this line once the prev lab EMR on EKS is up
# export S3BUCKET=$(aws cloudformation describe-stacks --stack-name $stack_name --query "Stacks[0].Outputs[?OutputKey=='CODEBUCKET'].OutputValue" --output text)
# echo "export S3BUCKET=${S3BUCKET}" | tee -a ~/.bash_profile
# source ~/.bash_profile


#2. Install Terraform v1.2.8
TERRAFORM_VERSION="1.2.8"
TERRAFORM_ZIP="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
curl -O "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TERRAFORM_ZIP}"
sudo unzip $TERRAFORM_ZIP -d /usr/local/bin/
rm $TERRAFORM_ZIP

# 3. install tools
# Install kubectl  (not needed after EMR on EKS Lab is up)
sudo curl --silent --location -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl --silent --location https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo chmod +x /usr/local/bin/kubectl

# Install Helm
sudo curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
helm repo add stable https://charts.helm.sh/stable
helm repo update

helm version

# Install latest AWS CLIv2 (not needed after EMR on EKS Lab is up)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Clone repo
git clone -b apac-workshop --single-branch https://github.com/awslabs/data-on-eks.git

# 4. connect to the EKS newly created
echo $(aws cloudformation describe-stacks --stack-name $stack_name --query "Stacks[0].Outputs[?starts_with(OutputKey,'eksclusterEKSConfig')].OutputValue" --output text) | bash
echo "Testing EKS connection..."
kubectl get svc
