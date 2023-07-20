# TF-controller install

In order to use an existing FluxCD to pull data into a kubernetes cluster running TF-controller:

## Prerequisites

- A kubernetes cluster running FluxCD in the flux-system namespace and configured with a cluster repo
- Installed TF-controller in the kubernetes cluster in the flux-system namespace

## Method

1. Use the data-on-eks-repo.yaml to set up the GitRepository on the target kubernetes cluster either by using:
   a. kubectl apply -f data-on-eks-repo.yaml
   b. Copy the file into a Flux enabled directory of manifests that will sync to the kubernetes cluster
2. Create a new kustomization that points to this directory in the GitRepository source using flux:
```
flux create kustomization data-on-eks-cloudnative-postgresql --source=GitRepository/data-on-eks --prune=true --path="./distributed-databases/cloudnative-postgres/tf-controller"
```


Let flux sync the files to the cluster and then the TF-controller will deploy the eks cluster with the cloudnative-postgresql component.

## Cleanup

To delete the cluster, just delete the files from the repository and the TF destroy process will run to delete all the objects that were created.

Alternatively: you can change the field: `destroy: false` to `destroy: true` which will also run the destroy TF process.
