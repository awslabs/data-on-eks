# Cost effective and Scalable Model Inference on AWS Graviton with Ray on EKS

## Overview
The solution implements a scalable ML inference architecture using Amazon EKS, leveraging Graviton processors. The system utilizes Ray Serve for model serving, deployed as containerized workloads within a Kubernetes environment. 


## Prerequisites
 
1. EKS cluster with Ray operater installed
2. Karpenter node pool is setup for Graviton instance, the node pool label is model-inferencing:cpu-arm in this example
3. Make sure running following command under the llamacpp-rayserve-graviton directory

## Deployment

Deploy an elastic Ray service hosting llama 3.2 model on Graviton, remember to edit your hugging face token for env HUGGING_FACE_HUB_TOKEN in the secret of the 'ray-service-llamacpp.yaml' file.
You can change the model and parameters for inference with llama.cpp, they are configured in [these lines](/gen-ai/inference/llamacpp-rayserve-graviton/ray-service-llamacpp.yaml#L121-L134).
MODEL_ID is the place to change the hugging_face model repo
MODEL_FILENAME is is the place to change the model file in a hugging_face repo 
You may notice the example model used in this blueprint is formatted as GGUF which is optimized for llama.cpp (please refer [this](https://huggingface.co/docs/hub/en/gguf) for more details)
N_THREADS is the number of threads to use for inference, best practice is to set it as same as the number of vCPU of host EC2 instance for optimized performance.
CMAKE_ARGS are the C/C++ compile flags when compiling llama.cpp.(please refer [this](https://github.com/aws/aws-graviton-getting-started/blob/main/c-c++.md) for more details about C/C++ compile flags for Graviton)

After setting up all variables, run this command to create the kubenetes service 

```bash
kubectl create -f ray-service-llamacpp.yaml 
```

KubeRay will create a Kubernetes service that will accept HTTP traffic for inferencing API. Get the name of the Kubernetes service created, which will be used to route traffic for our benchmark.

```bash
kubectl get svc 
```

## How do we measure

Our client program will generate 20 different prompts with different concurrency for each run. Every run will have common GenAI related prompts and assemble them into standard HTTP requests, and concurrency calls will keep increasing until the maximum CPU usage reaches to nearly 100%. We capture the total time from when a HTTP request is initiated to when a HTTP response is received as the latency metric of model performance. We also capture output token generated per second as throughput. The test aims to reach maximum CPU utilization on the worker pods to assess the concurrency performance.

With 10 pods allocated to Ray cluster, the cluster will use 10 8xlarge instance for worker pods and one EC2 for head pod. c7g.8xlarge EC2 instance runs the Graviton3 benchmark and c8g.8xlarge for Graviton4 benchmark.

Follow this guidance if you want to set it up and replicate the experiment

### 1. Launch load generator instance
Launch an EC2 instance as the client in the same AZ with the Ray cluster(For optimal performance testing, deploy a client EC2 instance in the same AZ as your Ray cluster. To generate sufficient load, use a compute-optimized instance like c6i.16xlarge. If you observe that worker node CPU utilization remains flat despite increasing concurrent requests, this indicates your test client may be reaching its capacity limits. In such cases, scale your testing infrastructure by launching additional EC2 instances to generate higher concurrent loads.)

### 2. Execute port forward for the ray service

```bash
kubectl port-forward svc/ray-service-llamacpp 8000:8000
```

### 2. Configure environment
Install golang environment in the client EC2 instance(please refer [this](https://go.dev/doc/install) for the golang installation guidance), specify the environment variables as test configuration.

```bash
export URL=http://localhost:8000/v1/chat/completions
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

You have an average latency reduction of 22% with c7g.4xlarge as compared to c6i.4xlarge. Further more, you can find out Graviton performance is more sustainable, even under high concurrency, the latency performance is keeping stable.

![Performance](/gen-ai/inference/llamacpp-rayserve-graviton/images/performance.png)


### Cost

The fleet we use consists of 10 4x large machines for worker pods. Using simple AWS calculator the cost in Sydney region for c6i.4xlarge is 0.888 hourly and c7g.4xlarge is 0.7549 hourly. We calculate the cost based on the benchmark duration, then figure out the data in following chart,  Graviton clearly has a benefit of 30% cost saving while also leading in the performance benchmarks, and from the trend you can see the more requests, the more cost saving from Graviton. We are using these numbers for comparison between Intel and Graviton, naturally there are AWS savings such as savings plan can be applied to further reduce cost for both.

![Cost](/gen-ai/inference/llamacpp-rayserve-graviton/images/cost.png)
