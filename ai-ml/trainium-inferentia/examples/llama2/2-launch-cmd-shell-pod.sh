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

# Read in our ECR REPO URI, created by 1-llama2-neuronx-pretrain-build-image.sh
ECR_REPO_URI=$(cat .ecr_repo_uri)
echo -e "Using container image $ECR_REPO_URI:latest"

# Launch the cmd-shell pod using the container image created by 1-llama2-neuronx-pretrain-build-image.sh
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: cli-cmd-shell
spec:
  containers:
  - name: app
    image: $ECR_REPO_URI:latest
    command: ["/bin/sh", "-c"]
    args: ["while true; do sleep 30; done"]
    volumeMounts:
    - name: persistent-storage
      mountPath: /shared
    - name: dshm
      mountPath: /dev/shm
  volumes:
  - name: persistent-storage
    persistentVolumeClaim:
      claimName: fsx-claim
  - name: dshm
    emptyDir:
      medium: Memory
  restartPolicy: Never
EOF

if [[ "$?" -eq 0 ]]; then
  echo
  kubectl get pods
fi
