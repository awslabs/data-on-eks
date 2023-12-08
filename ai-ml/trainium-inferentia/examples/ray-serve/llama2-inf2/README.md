# How to deploy Llama2 on Inference2 and EKS

## Pre-requisites
Deploy the `trainium-inferentia` blueprint using this [link](https://awslabs.github.io/data-on-eks/docs/blueprints/ai-ml/trainium)

## Step 1: Deploy RayServe Cluster

To deploy the RayServe cluster with `Llama2-13B` LLM on `Inf2.48xlarge` instance, run the following command:

**IMPORTANT NOTE: RAY MODEL DEPLOYMENT CAN TAKE UPTO 8 TO 10 MINS**

```bash
cd data-on-eks/ai-ml/trainium-inferentia/examples/ray-serve/llama2-inf2
kubectl apply -f ray-service-llama2.yaml
```

This will deploy a RayServe cluster with two `inf2.48xlarge` instances. The `Llama2-13B` LLM will be loaded on both instances and will be available to serve inference requests.

Once the RayServe cluster is deployed, you can start sending inference requests to it. To do this, you can use the following steps:

Get the NLB DNS Name address of the RayServe cluster. You can do this by running the following command:

```bash
kubectl get ingress llama2-ingress -n llama2
```

Now, you can access the Ray Dashboard from the URL Below

    http://<NLB_DNS_NAME>/dashboard/#/serve

## Step 2: To Test the Llama2 Model

To test the Llama2 model, you can use the following command with a query added at the end of the URL.
This uses the GET method to get the response:

    http://<NLB_DNS_NAME>/serve/infer?sentence=what is data parallelism and tensor parallelisma and the differences


You will see an output like this in your browser:

```text
[
"what is data parallelism and tensor parallelisma and the differences between them?

Data parallelism and tensor parallelism are both techniques used to speed up machine learning training on large datasets using multiple GPUs or other parallel processing units. However, there are some key differences between them:

Data parallelism:

* In data parallelism, the same model is split across multiple devices (e.g., GPUs or Machines), and each device processes a portion of the input data.
* Each device computes the gradients for its own portion of the data and sends them back to the host, which aggregates them to update the model parameters.
* Data parallelism is useful for training large models on large datasets, as it allows the model to be partitioned across multiple devices and processed in parallel.
* Popular deep learning frameworks such as TensorFlow, PyTorch, and Keras support data parallelism.

Tensor parallelism:

* In tensor parallelism, multiple devices (e.g., GPUs or TPUs) are used to compute multiple tensors (i.e., matrices) in parallel.
* Each device computes a subset of the tensor operations, and the results are combined to form the final output.
* Tensor parallelism is useful for training large models on large datasets, as it allows the model to be computed in parallel across multiple devices.
* Popular deep learning frameworks such as TensorFlow and PyTorch support tensor parallelism.

Key differences:

* Data parallelism is focused on dividing the input data across multiple devices, while tensor parallelism is focused on dividing the computational operations across multiple devices.
* In data parallelism, each device processes a portion of the input data, while in tensor parallelism, each device computes a subset of the tensor operations.
* Data parallelism is typically used for training large models on large datasets, while tensor parallelism is typically used for training large models on large datasets with a large number of parameters.

In summary, data parallelism is a technique for speeding up machine learning training by dividing the input data across multiple devices, while tensor parallelism is a technique for speeding up machine learning training by dividing the computational operations across multiple devices. Both techniques are useful for training large models on large datasets, but they have different focuses and are used in different situations."
]
```
