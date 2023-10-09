#!/bin/bash

read -p "Enter the ECR region: " region

# Replace with your desired repository name and region
ECR_REPO_NAME="eks_torchx_test"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$region" >/dev/null 2>&1; then
  echo "ECR repository '$ECR_REPO_NAME' already exists."

  # Get the ECR_REPO_URI for the existing repository
  ECR_REPO_URI=$(aws ecr describe-repositories --repository-name "$ECR_REPO_NAME" --query 'repositories[0].repositoryUri' --region "$region" --output text)
  echo "Repository URL: $ECR_REPO_URI"
else
  # Create the ECR repository
  aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$region"

  # Get the ECR_REPO_URI for the newly created repository
  ECR_REPO_URI=$(aws ecr describe-repositories --repository-name "$ECR_REPO_NAME" --query 'repositories[0].repositoryUri' --region "$region" --output text)
  echo "Repository URL: $ECR_REPO_URI"
fi

PASSWORD=$(head /dev/random|md5sum|head -c12)

echo -e "Building Tensorboard container"
DOCKER_BUILDKIT=1 docker build --build-arg TB_PASSWORD=$PASSWORD ./docker -f Dockerfile-t $ECR_REPO_URI:tensorboard

echo -e "\nPushing Tensorboard container to $ECR_REPO_URI"
docker push $ECR_REPO_URI:tensorboard

cat <<EOF > tensorboard_manifest.yaml
apiVersion: v1
kind: Service
metadata:
  name: tensorboard-ext-loadbalancer
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: tensorboard-app
  type: LoadBalancer
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: tensorboard-app
  name: tensorboard-service
spec:
  ports:
  - name: nginx-proxy
    port: 80
    protocol: TCP
    targetPort: 80
  - name: tensorboard-server
    port: 6006
    protocol: TCP
    targetPort: 6006
  selector:
    app: tensorboard-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: tensorboard-app
  name: tensorboard-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: tensorboard-app
  template:
    metadata:
      labels:
        app: tensorboard-app
    spec:
      containers:
      - args:
        - /usr/local/bin/tensorboard --logdir /data/output --bind_all & /usr/sbin/nginx
          -g "daemon off;"
        command:
        - /bin/sh
        - -c
        image: $ECR_REPO_URI:tensorboard
        imagePullPolicy: Always
        name: app
        ports:
        - containerPort: 80
          name: http
        - containerPort: 6006
          name: tensorboard
        volumeMounts:
        - mountPath: /data
          name: persistent-storage
      restartPolicy: Always
      volumes:
      - name: persistent-storage
        persistentVolumeClaim:
          claimName: fsx-claim
EOF

echo -e "\nCreating Tensorboard pod"
kubectl apply -f tensorboard_manifest.yaml

# Wait for loadbalancer to be created
LB_HOST=$(kubectl get service tensorboard-ext-loadbalancer -o json | jq -r ".status.loadBalancer.ingress[0].hostname")
while [ $LB_HOST = "null" ]
do
        sleep 2;
        LB_HOST=$(kubectl get service tensorboard-ext-loadbalancer -o json | jq -r ".status.loadBalancer.ingress[0].hostname")
done

# Now wait for loadbalancer to come online
echo -e "\n\nWaiting for loadbalancer $LB_HOST to come online. This could take 1-2 minutes."

sleep 5

STATUS=$(curl -sI $LB_HOST|head -1)
while [[ ! $STATUS =~ Unauthorized ]]
do
	echo -n "."
	sleep 10
	STATUS=$(curl -sI $LB_HOST|head -1)
done

# Lastly, output the URL
echo -e "\n\n\nTensorboard URL ==> http://admin:$PASSWORD@$LB_HOST\n\n"
echo "http://admin:$PASSWORD@$LB_HOST" > tensorboard_url.txt
