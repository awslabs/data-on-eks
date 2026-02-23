---
title: Execute Sample Flink Job
sidebar_label: Execute Sample Flink Job
sidebar_position: 3
---

## Prerequisites

- ✅ [Infrastructure deployed](/data-on-eks/docs/datastacks/processing/emr-on-eks/infra)


## Execute Sample Flink job with Karpenter

Set the env variables for the job execution role and s3 bucket name :
```bash
source env.sh
```

Navigate to example directory and submit the Flink job.

```bash
cd examples/flink/karpenter
```

Modify the basic-example-app-cluster.yaml by replacing the placeholders with values from the two env variables above.

```bash
envsubst < basic-example-app-cluster.yaml > basic-example-app-cluster1.yaml
```

Deploy the job by running the kubectl deploy command.

```bash
kubectl apply -f basic-example-app-cluster1.yaml
```

Monitor the job status using the below command.
You should see the new nodes triggered by the karpenter and the YuniKorn will schedule one Job manager pod and one Taskmanager pods on this node.

```bash
kubectl get deployments -n emr-data-team-a
```
```
NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
basic-example-karpenter-flink   2/2     2            2           3h6m
```

```bash
kubectl get pods -n emr-data-team-a
```
```
NAME                                               READY   STATUS    RESTARTS   AGE
basic-example-karpenter-flink-7c7d9c6fd9-cdfmd   2/2     Running   0          3h7m
basic-example-karpenter-flink-7c7d9c6fd9-pjxj2   2/2     Running   0          3h7m
basic-example-karpenter-flink-taskmanager-1-1    2/2     Running   0          3h6m
```
```bash
kubectl get services -n flink-team-a-ns
```
```
NAME                                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
basic-example-karpenter-flink-rest   ClusterIP   172.20.17.152   <none>        8081/TCP   3h7m
```

To access the Flink WebUI for the job, run this command locally.

```bash
kubectl port-forward svc/basic-example-karpenter-flink-rest 8081 -n emr-data-team-a
```

![Flink Job UI](img/flink1.png)
![Flink Job UI](img/flink2.png)
![Flink Job UI](img/flink3.png)
![Flink Job UI](img/flink4.png)
![Flink Job UI](img/flink5.png)
