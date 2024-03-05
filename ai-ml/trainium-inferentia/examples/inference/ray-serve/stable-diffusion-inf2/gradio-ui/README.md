# Steps to Deploy Gradio on Your Mac

## 1. Pre-requisites
Deploy the `trainium-inferentia` blueprint using this [link](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/trainium)

## 2. Deploying the Gradio WebUI App

Discover how to create a user-friendly chat interface using [Gradio](https://www.gradio.app/) that integrates seamlessly with deployed models.

Let's deploy Gradio app as a docker container to interact with the Stable Diffusion XL model deployed using RayServe.

### 2.1. Deploy the Gradio App as Deployment

First, deploy the Gradio app as a Deployment on EKS using kubectl:

```bash
cd gradio-ui
kubectl apply -f gradio-deploy.yaml
```

This should create a Deployment and a Service in namespace `gradio`. Check the status of the resources.

```bash
kubectl -n gradio get all
NAME                                     READY   STATUS    RESTARTS   AGE
pod/gradio-deployment-59cfbffdf5-q745z   1/1     Running   0          143m

NAME                     TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/gradio-service   ClusterIP   172.20.245.153   <none>        7860/TCP   3d12h
```

### 2.2. Port-Forward to access the service locally

Execute a port forward to the `gradio-service` Service using kubectl:

```bash
kubectl -n gradio port-forward service/gradio-service 8080:7860
```

### 2.3. Access the WebUI from Your Browser

Open your web browser and access the Gradio WebUI by navigating to the following URL:

http://localhost:8080

You should now be able to interact with the Gradio application from your local machine.
