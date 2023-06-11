if [ $# -ne 5 ];
  then echo "Please include the 1) Account Numer; 2) Docker repository name; 3) Image tag; 4) Region; and 5) Account number of the Base Spark Rapids EMR on EKS image. The parameters are in sequential order"
  exit 1
fi

# Steps to create a custom Docker image to be used duing Spark job submission

ACCOUNT_NUMBER=$1
REPOSITORY_NAME=$2
TAG=$3
REGION=$4
BASE_IMAGE_ACCOUNT=$5

# Ignore this step if you already have an ECR repository
aws create-repository --registry-id < Account number > --repository-name $REPOSITORY_NAME --region $REGION

# Login to the EMR on EKS ECR repository to pull the US-east-1 Spark Rapids base image
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $BASE_IMAGE_ACCOUNT.dkr.ecr.$REGION.amazonaws.com

# Build your Docker image locally
docker build -t $ACCOUNT_NUMBER.dkr.ecr.$REGION.amazonaws.com/$REPOSITORY_NAME:$TAG -f Dockerfile .

# Login to your ECR repository
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_NUMBER.dkr.ecr.$REGION.amazonaws.com

# Push Docker image to your ECR
docker push $ACCOUNT_NUMBER.dkr.ecr.$REGION.amazonaws.com/$REPOSITORY_NAME:$TAG

# Verify ECR repository
aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $REGION
