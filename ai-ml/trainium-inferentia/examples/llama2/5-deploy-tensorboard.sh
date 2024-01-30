#!/bin/bash

# Check if kubectl is installed
junk=$(which kubectl 2>&1 > /dev/null)
if [[ "$?" -ne 0 ]]; then
  echo "Error: please install kubectl and try again. See: https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html"
  exit 1
fi

# Check if kubectl is configured
junk=$(kubectl get nodes)
if [[ "$?" -ne 0 ]]; then
  echo "Error: kubectl is installed but not configured. Please use 'aws eks update-kubeconfig' to configure it and try again"
  exit 1
fi

# Determine ECR REPO URI to which we'll push the Tensorboard image
ECR_REPO_URI=$(cat .ecr_repo_uri):tensorboard

# Generate a random password which will be used for Tensorboard
PASSWORD=$(head /dev/random|md5sum|head -c12)

# Build and push the Tensorboard image
echo -e "Building Tensorboard container"
DOCKER_BUILDKIT=1 docker build --build-arg TB_PASSWORD=$PASSWORD ./docker -f ./docker/Dockerfile.tensorboard -t $ECR_REPO_URI
echo -e "\nPushing Tensorboard container to $ECR_REPO_URI"
docker push $ECR_REPO_URI

# Create the Tensorboard deployment
echo -e "\nCreating Tensorboard pod"
kubectl apply -f - <<EOF
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
        - /usr/local/bin/tensorboard --logdir /shared/nemo_experiments/ --bind_all & /usr/sbin/nginx
          -g "daemon off;"
        command:
        - /bin/sh
        - -c
        image: $ECR_REPO_URI
        imagePullPolicy: Always
        name: app
        ports:
        - containerPort: 80
          name: http
        - containerPort: 6006
          name: tensorboard
        volumeMounts:
        - mountPath: /shared
          name: persistent-storage
      restartPolicy: Always
      volumes:
      - name: persistent-storage
        persistentVolumeClaim:
          claimName: fsx-claim
EOF

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
