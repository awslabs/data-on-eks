#!/bin/bash

helm install raycluster kuberay/ray-cluster \
--version 1.0.0 \
--values ./values.yaml \
--set image.repository=$(cat .ecr_repo_uri)
