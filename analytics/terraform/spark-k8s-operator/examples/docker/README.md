# Build Multi-Arch Container Image

In order to run Spark on Graviton instances the container images need to be built with support for the arm64 architecture. We launched an Ec2 instance and connected to that instance via SSM to build the images used in our examples.

## Pre-requisites
### 1. Install Docker and Buildx
You will need an environment able to build container images, we used an EC2 instance and [installed Docker and buildx](https://docs.docker.com/engine/install/) using the commands below:
```bash
sudo yum install -y docker
sudo systemctl start docker
```

You may need to add your user to the docker group:
```bash
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
```

Install the cross-platform build emulators:
```bash
 docker run --privileged --rm tonistiigi/binfmt --install all
```

### 2. Create a Buildx builder
We then created a cross-platform builder instance for multi-arch builds:
```bash
docker buildx create --name mybuilder --use
docker buildx inspect --bootstrap
```

You should see both `linux/amd64` and `linux/arm64` in the supported platforms for the builder:
```bash
docker buildx ls

NAME/NODE    DRIVER/ENDPOINT             STATUS  BUILDKIT PLATFORMS
mybuilder *  docker-container
  mybuilder0 unix:///var/run/docker.sock running v0.16.0  linux/amd64, linux/amd64/v2, linux/amd64/v3, linux/amd64/v4, linux/386
default      docker
  default    default                     running v0.12.5  linux/amd64, linux/amd64/v2, linux/amd64/v3, linux/amd64/v4, linux/386
```

### 3. Create an ECR repository
We will use an ECR repo to store the images, if you don't have a repository you can use the command below to [create a Private ECR repo](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-create.html).
```bash
aws ecr create-repository --repository-name spark --region us-east-1
```

We should be ready to build the image now.


## Building the image
### 1. Pull the Dockerfile to the build instance
We will use the Dockerfiles in the Data on EKS repo as an example, we copied the file to the build Ec2 instance with the command below:

```bash
wget https://github.com/awslabs/data-on-eks/blob/main/analytics/terraform/spark-k8s-operator/examples/docker/Dockerfile
```

### 2. Check the Spark/Dependency versions
The Spark base image and dependencies like hadoop and the AWS SDK are defined at the top of the dockerfile, if you need to adjust them you can edit the file before building.

```dockerfile
# Use the official Spark base image with Java 17 and Python 3
FROM apache/spark:3.5.3-scala2.12-java17-python3-ubuntu

# Arguments for version control
ARG HADOOP_VERSION=3.4.1
ARG AWS_SDK_VERSION=2.29.0
...
```

### 3. Login to the ECR repo
We will need to authenticate with the ECR repo in order to push the image we build. You'll need to update the command with your AWS Account ID:

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <aws_account_id>.dkr.ecr.us-east-1.amazonaws.com
```


### 4. Build and push the image
Now we can build the image for both amd64 and arm64 architectures with the command below. You will need to update the image tag(`-t`) to match the ECR repository you created earlier.
The `--push` option will push the image to the ECR repo after building.

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t <aws_account_id>.dkr.ecr.region.amazonaws.com/spark:3.5.3-scala2.12-java17-python3-ubuntu --push .
```
