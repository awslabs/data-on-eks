# Ray Batch LLM Inference on EKS

End-to-end example of **batch LLM inference** on the `ray-on-eks` data stack:
mock support tickets land in S3 at an interval, and Ray processes them in bulk
with **DeepSeek-R1-Distill-Llama-8B** served by **vLLM 0.22** on **Ray 2.56**
(KubeRay v1.6.1), using two complementary patterns.

## Architecture

```
                       ┌────────────────────────────────────────────────┐
  Generator Job (10x)  │                 EKS / Karpenter                │
  mock tickets ───────►│  Iceberg table (Glue catalog, S3 warehouse)    │
                       │      │  1 snapshot per firing; jobs read       │
                       │      │  incrementally via watermark property   │
                       │      ▼                                         │
                       │  Pattern 1: RayJob (CPU workers, Ray Data)     │
                       │      │  OpenAI-compatible HTTP                 │
                       │      ▼                                         │
                       │  RayService: vLLM engine on g6e (L40S 48GB)    │
                       │      ▲  weights streamed from S3 at startup    │
                       │      │  (Run:ai Model Streamer)                │
                       │  S3 models/deepseek-r1-distill-llama-8b/       │
                       │                                                │
                       │  Pattern 2: RayJob (ray.data.llm)              │
                       │      vLLM engine runs INSIDE the batch job     │
                       │      on its own ephemeral g6e node             │
                       │      │                                         │
                       │      ▼                                         │
                       │  S3 results/ (Parquet: sentiment, urgency,     │
                       │               category, summary)               │
                       └────────────────────────────────────────────────┘
```

### Why this shape

- **Weights live in S3 as safetensors**, streamed straight to GPU memory with
  the [Run:ai Model Streamer](https://docs.vllm.ai/en/stable/models/extensions/runai_model_streamer/)
  (`load_format: runai_streamer`). No HuggingFace pull on the GPU node, no
  weights baked into images or EBS snapshots. Ray 2.56 treats it as a
  first-class streaming format and skips node-local model downloads entirely.
- **The 11.6 GB `rayproject/ray-llm` image is mirrored to same-region ECR**
  once (in-cluster skopeo job), so GPU node cold starts never pull from
  Docker Hub.
- **CPU/GPU separation**: the Ray head is control-plane only (`num-cpus: 0`),
  Ray Data preprocessing runs on cheap general-purpose CPU nodes, and the
  GPU worker group runs nothing but the vLLM engine. On a g6e.2xlarge
  (8 vCPU), stealing engine cores for data tasks starves tokenization and
  kills GPU utilization — don't co-locate.
- **Karpenter provisions the GPU node on demand** and reclaims it when the
  service scales in or the batch job finishes. g6e.2xlarge is preferred with
  g6e.4xlarge as fallback (same single L40S GPU) because 2xlarge frequently
  has capacity shortages (ICE) in us-west-2.
- **Tickets land in an Iceberg table, not raw files.** The generator appends
  to `raydata_spark_logs.support_tickets` (Glue catalog, warehouse under
  `s3://$S3_BUCKET/iceberg-warehouse/`), one snapshot per firing. Each batch
  pattern tracks its own watermark (`watermark.native` / `watermark.endpoint`)
  as an Iceberg table property, like independent consumer groups: a run pins
  the current snapshot, reads only rows with `ingested_ms` past its
  watermark, and advances the watermark only after results are durable in
  S3. Reruns after a failure reprocess the same increment (at-least-once)
  into a fresh run-stamped output path, so nothing is lost or corrupted.
  Note the watermark protocol assumes a single sequential writer (the
  generator is one pod appending in a loop); with concurrent writers use
  Iceberg incremental append scans between snapshot IDs instead.

### Pattern 1 vs Pattern 2

| | Pattern 1: endpoint (05) | Pattern 2: native (06) |
|---|---|---|
| Engine location | Shared RayService (online + batch) | Inside the batch job |
| Transport | HTTP (OpenAI API) | In-process Ray Data pipeline |
| Autoscaling | Serve replicas on request pressure | Job-scoped, fixed |
| Best for | Reusing a live endpoint, trickle backfills | Max throughput per GPU-hour |
| GPU while idle | Held by the service (min_replicas) | Released when job ends |

## Prerequisites

The `ray-on-eks` stack deployed with `enable_raydata = true` and
`enable_nvidia_gpu_operator = true` in `terraform/data-stack.tfvars`. The GPU
operator provides the device plugin plus DCGM exporter metrics (GPU
utilization, memory, power) scraped by the stack's Prometheus.

```bash
export KUBECONFIG=<repo>/data-stacks/ray-on-eks/kubeconfig.yaml
export S3_BUCKET=$(cd ../../terraform/_local && terraform output -raw s3_bucket_id_spark_history_server)
export AWS_REGION=us-west-2
```

## Run it

```bash
# 1. One-time: stage model weights in S3 + mirror image to ECR (~3 min total)
./deploy.sh prepare

# 2. Deploy the inference endpoint (Karpenter provisions the GPU node)
./deploy.sh service
kubectl get rayservice deepseek-r1-8b -n raydata -w   # wait for Running

# 3. Run the ticket generator: one pod, 10 appends of 200 tickets to the
#    Iceberg table 2 min apart (~20 min, ~2,000 tickets), then it
#    completes. Tune MAX_BATCHES / INTERVAL_SECONDS / TICKETS_PER_BATCH
#    in 04-ticket-generator.yaml; re-run for another round.
./deploy.sh generator

# 4. Batch inference against the endpoint (pattern 1)
./deploy.sh batch-endpoint
kubectl logs -n raydata -l job-name=ticket-batch-endpoint -f

# 5. Batch inference with in-job vLLM (pattern 2)
./deploy.sh batch-native
kubectl logs -n raydata -l job-name=ticket-batch-native -f
```

Query the endpoint directly:

```bash
kubectl port-forward svc/deepseek-r1-8b-serve-svc 8000 -n raydata &
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "deepseek-r1-distill-llama-8b",
  "messages": [{"role": "user", "content": "Classify: my invoice was charged twice"}],
  "max_tokens": 256
}'
```

## Measured cold-start timings

Measured end-to-end on this stack on 2026-07-10 (us-west-2, g6e.2xlarge
on-demand, NVIDIA GPU operator, image from same-region ECR, weights from
same-region S3). Every figure below comes from Kubernetes event timestamps or
vLLM/Ray log lines from a single measured run, not estimates:

| Phase | Duration |
|---|---|
| One-time: HuggingFace -> staging pod download (15 GiB safetensors) | 18 s |
| One-time: staging pod -> S3 upload (15 GiB) | 30 s |
| One-time: Docker Hub -> ECR mirror (11.6 GB image, in-cluster skopeo) | 82 s |
| Autoscaler + Karpenter reaction (GPU pod pending -> NodeClaim created) | 13 s |
| EC2 launch -> node Ready (NodeClaim -> kubelet Ready) | 40 s |
| Node Ready -> pod scheduled (GPU operator registers `nvidia.com/gpu`) | 36 s |
| ECR image pull (11.6 GB, kubelet `Pulled` event) | 2 m 01 s |
| Container start (init container waits for Ray head GCS) | 53 s |
| Ray worker up -> Serve replica init (runtime_env pip: ~12 s) | 16 s |
| Replica init -> vLLM engine start (tokenizer fetch, platform setup) | 36 s |
| Model weights: Run:ai stream S3 -> memory (15 GiB, concurrency 32) | 17.8 s (860 MiB/s) |
| vLLM model load total (includes the stream above) | 18.5 s |
| vLLM init engine: torch.compile 19.4 s + CUDA graphs + warmup | 33.8 s |
| **Total: GPU pod created -> replica serving traffic (fresh node)** | **6 m 33 s** |
| **Total: warm node, image cached (pod restart only)** | **~2 m 30 s** |
| Single request, batch size 1 (R1 emits 150-180 reasoning+answer tokens) | 4.2-4.7 s (~37 tok/s) |

Weight delivery is a 17.8-second phase because the safetensors stream
directly from S3 to memory with the Run:ai Model Streamer; pulling the same
model from HuggingFace at startup typically takes several minutes and adds
rate-limit risk. In an earlier run on g6e.4xlarge the same stream sustained
1.0 GiB/s (14.9 s), so expect 15-18 s for this model size.


## Measured batch results and tokenomics

Both patterns processed the **same 15,600-ticket dataset** on the same
hardware (one L40S, g6e.2xlarge on-demand, $2.24208/h in us-west-2), with
per-request token counts recorded in the output Parquet — `usage` from the
OpenAI response in pattern 1, exact engine counters (`num_input_tokens` /
`num_generated_tokens`) in pattern 2. Prompt tokens are identical across
runs (2,611,810); output tokens differ by <0.1% (sampling temperature).

| Metric | Pattern 1: endpoint | Pattern 2: native `ray.data.llm` |
|---|---|---|
| Tickets processed | 15,600 (0 failed requests) | 15,600 |
| Wall time | 51.1 min | 30.1 min |
| Throughput | 5.09 tickets/s | **8.63 tickets/s (1.70x)** |
| Output token rate | 1,637 tok/s | **2,776 tok/s (1.70x)** |
| GPU-hours consumed | 0.851 | 0.502 |
| GPU cost (run total) | $1.91 | $1.13 |
| **Cost per 1,000 tickets** | **$0.122** | **$0.072 (41% cheaper)** |
| Cost per 1M output tokens | $0.380 | $0.224 |
| Cost per 1M total tokens | $0.250 | $0.148 |

Verbatim job output (pattern 2):

```
==== BATCH SUMMARY (native ray.data.llm) ====
tickets processed : 15600
wall time         : 1808.2s
throughput        : 8.63 tickets/s
==== TOKENOMICS ====
prompt tokens     : 2,611,810 (167/ticket)
output tokens     : 5,019,499 (322/ticket)
output token rate : 2,776 tok/s
GPU cost          : $1.1261 (0.5023 GPU-h @ $2.24208/h)
cost per 1k tickets       : $0.0722
cost per 1M output tokens : $0.224
cost per 1M total tokens  : $0.148
```

**Why the native pattern is 1.70x cheaper on identical work:** cost is
GPU-hours × hourly rate ÷ work done, and the only variable is how full the
engine's continuous-batching queue stays. Pattern 1 pays an HTTP round-trip
per ticket (client → Serve proxy → replica → back), and its saturation is
capped by client-side concurrency — a finished batch slot idles until the
next request arrives. Pattern 2 inverts control: Ray Data backpressure lets
the engine *pull* the next row the moment capacity frees, keeping it pinned
at its own limit (95.5% prefix-cache hit rate on the shared system prompt).
Note the table also understates the difference in steady state: pattern 1's
GPU is billed only for the batch window here, but a standing endpoint costs
$2.24/h around the clock ($53.81/day) whether traffic arrives or not, while
pattern 2's node exists for 30 minutes and is reclaimed by Karpenter.

Pattern 1 still earns its place: if you already run the endpoint for online
traffic, backfills reuse infrastructure you are paying for anyway, and the
Serve autoscaler adds replicas under sustained pressure (observed during
these runs). Rule of thumb: batches worth minutes of GPU time go to the
endpoint; batches worth tens of minutes or more deserve their own job-scoped
engine.

Set `GPU_COST_PER_HOUR` in the RayJob env to your node price (Spot,
different instance type, negotiated rates) to make the printed costs match
your bill. For fleet-level monitoring of the online endpoint, vLLM exports
`vllm:prompt_tokens_total` / `vllm:generation_tokens_total` to the stack's
Prometheus.

## Files

| File | Purpose |
|---|---|
| `01-model-staging-job.yaml` | HF -> S3 safetensors staging job |
| `02-image-mirror-job.yaml` | Docker Hub -> ECR skopeo mirror job |
| `03-rayservice-deepseek-r1-8b.yaml` | RayService: vLLM + Run:ai streamer |
| `04-ticket-generator.yaml` | Job: 10 appends of ~200 tickets to Iceberg, 2 min apart |
| `05-rayjob-batch-endpoint.yaml` | Pattern 1: incremental Iceberg read -> HTTP endpoint |
| `06-rayjob-batch-native.yaml` | Pattern 2: incremental Iceberg read -> native `ray.data.llm` |
| `deploy.sh` | Renders placeholders and applies everything |

## Cleanup

```bash
./deploy.sh cleanup
```
