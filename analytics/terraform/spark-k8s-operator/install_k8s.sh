#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define the Kubernetes version you want to target (matching your current apt preference)
K8S_VERSION="v1.33"

echo "========================================="
echo " Starting Kubernetes ($K8S_VERSION) Installation"
echo "========================================="

# 1. Disable Swap (Required by Kubernetes)
echo "--> Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 2. Configure Prerequisites (Forwarding IPv4 and letting iptables see bridged traffic)
echo "--> Configuring kernel modules and sysctl..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# 3. Install and Configure Containerd (Container Runtime)
echo "--> Installing and configuring containerd..."
sudo apt-get update && sudo apt-get install -y containerd

# Generate default containerd config and enforce SystemdCgroup
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart containerd to apply changes
sudo systemctl restart containerd
sudo systemctl enable containerd

# 4. Install Dependencies for K8s Repository
echo "--> Installing repository dependencies..."
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# 5. Add Kubernetes GPG Key and Repository
echo "--> Adding Kubernetes repository ($K8S_VERSION)..."
sudo mkdir -p -m 755 /etc/apt/keyrings

# Download the public signing key
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes

# Add the appropriate apt repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

# 6. Install Kubernetes Components
echo "--> Updating apt packages and installing kubelet, kubeadm, kubectl..."
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Pin the versions so they don't automatically upgrade during system updates
echo "--> Pinning Kubernetes package versions..."
sudo apt-mark hold kubelet kubeadm kubectl

# 7. Enable Kubelet service
sudo systemctl enable --now kubelet

echo "========================================="
echo " Installation Complete!"
echo " Components Verified:"
echo "----------------------------------------="
kubeadm version -o short
kubectl version --client
echo "========================================="