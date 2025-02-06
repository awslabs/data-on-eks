# Cost effective and Scalable Model Inference on AWS Graviton with Ray on EKS

## Overview
The solution implements a scalable ML inference architecture using Amazon EKS, leveraging Graviton processors. The system utilizes Ray Serve for model serving, deployed as containerized workloads within a Kubernetes environment. 


## Prerequisites
 
1. EKS cluster with Ray operater installed
2. Karpenter node pool is setup for Graviton instance, the node pool label is model-inferencing:cpu-arm in this example
3. Make sure running following command under the llamacpp-rayserve-graviton directory

## Deployment

### 1. Deploy Ray Service
Deploy an elastic Ray service hosting llama 3.2 3B model on Graviton, remember to fill in your hugging face token for env HUGGING_FACE_HUB_TOKEN.

```bash
kubectl create -f ray-service-llamacpp.yaml 
```

### 2. Configure Kubernetes Service
KubeRay will create a Kubernetes service that will accept HTTP traffic for inferencing API. Get the name of the Kubernetes service created, which will be used to route traffic for our benchmark.

```bash
kubectl get svc 
```

### 3. Setup Ingress
Create ingress for your API.  Read the Kubernetes Service name created in the step above and update the yaml file with the service name in your environment.

## How do we measure

Our client program will generate 20 different prompts with different concurrency for each run. Every run will have common GenAI related prompts and assemble them into standard HTTP requests, and concurrency calls will keep increasing until the maximum CPU usage reaches to nearly 100%. We capture the total time from when a HTTP request is initiated to when a HTTP response is received as the latency metric of model performance. We also capture output token generated per second as throughput. The test aims to reach maximum CPU utilization on the worker pods to assess the concurrency performance.

With 10 pods allocated to Ray cluster, the cluster will use 10 8xlarge instance for worker pods and one EC2 for head pod. c7g.8xlarge EC2 instance runs the Graviton3 benchmark and c8g.8xlarge for Graviton4 benchmark.

Follow this guidance if you want to set it up and replicate the experiment

### 1. Launch load generator instance
Launch an EC2 instance as the client in the same AZ with the Ray cluster(For optimal performance testing, deploy a client EC2 instance in the same AZ as your Ray cluster. To generate sufficient load, use a compute-optimized instance like c6i.16xlarge. If you observe that worker node CPU utilization remains flat despite increasing concurrent requests, this indicates your test client may be reaching its capacity limits. In such cases, scale your testing infrastructure by launching additional EC2 instances to generate higher concurrent loads.)

### 2. Configure environment
Install golang environment in the client EC2 instance, specify the environment variables as test configuration

```bash
export URL=http://<INGRESS_ADDRESS>/v1/chat/completions
export REQUESTS_PER_PROMPT=<The_number_of_concurrent_calls>
export NUM_WARMUP_REQUESTS=<The_number_of_warmup_requests>
```

### 3. Run test
Run the performance test golang script and you can find the results from the output. 

```bash
go run perf_benchmark.go
```

## Result

Let us see a benchmark result with above steps

### Performance

You have an average latency reduction of 22% with Graviton as compared to Intel. Further more, you can find out Graviton performance is more sustainable, even under high concurrency, the latency performance is keeping stable.

![Performance](/gen-ai/inference/llamacpp-rayserve-graviton/images/performance.png)


### Cost

The fleet we use consists of 10 4x large machines for worker pods. Using simple AWS calculator the cost for Intel is 0.888 hourly and Graviton is 0.7549 hourly. We calculate the cost based on the benchmark duration, then figure out the data in following chart,  Graviton clearly has a benefit of 30% over intel while also leading in the performance benchmarks, and from the trend you can see the more requests, the more cost saving from Graviton. We are using these numbers for comparison between Intel and Graviton, naturally there are AWS savings such as savings plan can be applied to further reduce cost for both.

![Cost](/gen-ai/inference/llamacpp-rayserve-graviton/images/cost.png)
