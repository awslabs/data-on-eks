# TF-controller install

In order to use an existing FluxCD to pull data into a kubernetes cluster running TF-controller:

## Prerequisites

- A kubernetes cluster running FluxCD in the flux-system namespace and configured with a cluster repo
- Installed TF-controller in the kubernetes cluster in the flux-system namespace

## Method

### CLI commands

1. Use flux to create the gitrepository object:
```
flux create source git data-on-eks --url=https://github.com/weavegitops/data-on-eks --interval=1m --branch=main
```
2. Create a new kustomization that points to this directory in the GitRepository source using flux:
```
flux create kustomization data-on-eks-cloudnative-postgresql --source=GitRepository/data-on-eks --prune=true --path="./distributed-databases/cloudnative-postgres/tf-controller"
```

### Gitops

1. Use flux to create the gitrepository object, but output it to the cluster config directory that is already configured:
```
flux create source git data-on-eks --url=https://github.com/weavegitops/data-on-eks --interval=1m --branch=main --export > data-on-eks.yaml
```
2. Create a new kustomization that points to this directory using flux and output to a file:
```
flux create kustomization data-on-eks-cloudnative-postgresql --source=GitRepository/data-on-eks --prune=true --path="./distributed-databases/cloudnative-postgres/tf-controller" --export > data-on-eks-cloudnative-postgres.yaml
```
3. Commit the changes to the Git repository and wait for Flux to sync the changes


TF-controller will deploy the eks cluster with the cloudnative-postgresql component.

## Cleanup

To delete the cluster, just delete the files from the repository and the TF destroy process will run to delete all the objects that were created.

Alternatively: you can change the field: `destroy: false` to `destroy: true` which will also run the destroy TF process.
