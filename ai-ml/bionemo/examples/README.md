# BioNemo Examples

Examples make use of the [Kubeflow Training Operator](https://github.com/kubeflow/training-operator) for Kubernetes ML Training jobs with PyTorch.

Install the Kubeflow Training Operator in the cluster before running these Kustomization scripts with the kubectl command line tool.

```
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.7.0"
```
