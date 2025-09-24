#!/bin/bash

# Build and push TPC-DS Gluten+Velox Docker image
# Usage: ./build-tpcds-gluten-image.sh [version]

set -euo pipefail

# Default version
VERSION=${1:-"v1.0.0"}
IMAGE_NAME="<dockerhubuser>/spark-tpcds-gluten-velox"
FULL_IMAGE="${IMAGE_NAME}:${VERSION}"

echo "Building TPC-DS Gluten+Velox Docker image: ${FULL_IMAGE}"

# Navigate to the spark-jobs directory
cd "$(dirname "$0")/.."

# Build the Docker image (ensure AMD64 for EKS compatibility)
echo "Building Docker image for AMD64 platform..."
docker buildx build \
    --platform linux/amd64 \
    -f Dockerfile-tpcds-gluten-velox-v2 \
    -t "${FULL_IMAGE}" \
    --load .

# Verify the image was built
echo "Verifying image build..."
docker images | grep "${IMAGE_NAME}" | head -1

# Tag as latest
docker tag "${FULL_IMAGE}" "${IMAGE_NAME}:latest"

# Push to Docker Hub
echo "Pushing ${FULL_IMAGE} to Docker Hub..."
docker push "${FULL_IMAGE}"
docker push "${IMAGE_NAME}:latest"

echo "✅ Successfully built and pushed:"
echo "   ${FULL_IMAGE}"
echo "   ${IMAGE_NAME}:latest"
echo ""
echo "Image is ready for TPC-DS Gluten+Velox benchmarks!"
echo "Update the image reference in tpcds-benchmark-gluten-c5d.yaml if needed."
