#!/bin/bash
set -e

CERT_BASE64=$(terraform output -raw eks_cluster_certificate_authority_data)
CERT_FILE="/usr/local/share/ca-certificates/eks-cluster.crt"

echo "🔐 Décodage du certificat depuis Terraform..."
echo "$CERT_BASE64" | base64 -d | sudo tee "$CERT_FILE" > /dev/null

echo "📥 Mise à jour des autorités de certification..."
sudo update-ca-certificates

echo "✅ Certificat du cluster EKS installé avec succès."
