#!/bin/bash

helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update
helm install raycluster kuberay/ray-cluster \
--version 1.0.0 \
--values ./values.yaml \
--set image.repository=$(cat .ecr_repo_uri)
