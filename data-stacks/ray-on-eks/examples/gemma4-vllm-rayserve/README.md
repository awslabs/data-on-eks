# Gemma 4 12B on RayServe + vLLM (optimized cold start)

An optimized, OpenAI-compatible inference endpoint for
[`google/gemma-4-12B-it`](https://huggingface.co/google/gemma-4-12B-it) on the
`ray-on-eks` data stack, served by **vLLM 0.25** on **Ray 2.57** (KubeRay),
with a single **L40S 48GB** GPU node provisioned on demand by **Karpenter**.

Every stage of the deployment is tuned for cold-start speed:

```
 Stage                     Technique                          Where
 ─────────────────────     ────────────────────────────────   ─────────────────────
 GPU node provisioning     Karpenter on-demand, g6e            gpu NodePool
 Container image pull      SOCI parallel pull/unpack + ECR     EC2NodeClass userData
 Model weight staging      HF -> S3 once (Xet transfer)        01-model-staging-job
 Model weight loading      Same-region S3 -> node NVMe         03-rayservice (ray-llm
                           (boto3 parallel mirror download)     CloudMirrorConfig)
 vLLM engine init          Bounded MM budget, async sched      engine_kwargs
```

This example pairs with the `ray-batch-inference` example: deploy this
endpoint, then run that example's Pattern 1 (`ray.data` against an
OpenAI-compatible endpoint) for **batch inference with Ray** against Gemma 4.

## Model facts

From the HuggingFace model card (`api/models/google/gemma-4-12B-it`):

| | |
|---|---|
| Architecture | `Gemma4UnifiedForConditionalGeneration` (encoder-free unified multimodal: text + image + audio) |
| `model_type` | `gemma4_unified` (requires transformers >= 5.10, vLLM >= 0.19) |
| Parameters | 11.96B, bf16 -> **~22.3 GiB** weights, a single `model.safetensors` (not sharded) |
| Context window | 128K (this config caps `max_model_len` at 32K for KV-cache headroom) |
| Chat template | Ships as a separate `chat_template.jinja` (staged alongside the JSON configs) |
| License | **apache-2.0, NOT gated** - no HuggingFace token needed |

## What makes it fast

1. **SOCI parallel pull (stack-level).** The `gpu` EC2NodeClass enables the
   AL2023 nodeadm `FastImagePull` feature gate: the SOCI snapshotter pulls and
   unpacks image layers in parallel (20 connections, 16MB chunks, 12 concurrent
   unpacks). AWS measured ~60% faster pulls for a 10GB vLLM image
   (1m53s -> 45s). The kubelet is also tuned (`serializeImagePulls: false`,
   `maxParallelImagePulls: 5`) so DaemonSet images don't queue behind the big
   one.

2. **Same-region ECR image (11.7 GB).** `rayproject/ray-llm:2.57.x` is
   mirrored once from Docker Hub to a private ECR repo by an in-cluster skopeo
   job. GPU node cold starts never touch Docker Hub (no rate limits, no
   cross-internet transfer).

3. **Weights in S3, loaded via ray-llm's cloud mirror.** `model_source` points
   at `s3://<bucket>/models/gemma-4-12b-it`. At replica init, ray-llm
   downloads the 22.3 GiB safetensors from same-region S3 to the node's NVMe
   (RAID0 instance store), then vLLM loads locally (2.5s NVMe -> GPU). No
   HuggingFace pull on the GPU node, no weights baked into images or EBS
   snapshots.

   **How the download parallelism works (and its limit):** ray-llm's mirror
   downloader runs a thread pool *across files*, and within each file boto3's
   `download_file` does multipart ranged GETs at its default `TransferConfig`
   (10 threads, 8 MB parts). Gemma 4 is a *single* `model.safetensors`, so the
   cross-file pool buys nothing and the effective rate is boto3's single-file
   default: ~190 MB/s observed -> 2m05s for 22.3 GiB, well under the g6e's
   20 Gbps NIC.

   > **Why not `load_format: runai_streamer`?** The streamer opens many
   > concurrent ranged reads against S3 (tunable `concurrency`, benchmarked at
   > ~3 GB/s from S3 at concurrency 32) and overlaps them with the host->GPU
   > copy, skipping the disk entirely - the same 22.3 GiB would land in
   > roughly **10-25s instead of 2m05s**. The `ray-batch-inference` DeepSeek
   > example uses exactly this on Ray 2.56. Gemma 4, however, needs Ray 2.57 /
   > vLLM 0.25, where an upstream regression
   > ([ray-project/ray#64978](https://github.com/ray-project/ray/issues/64978))
   > breaks `runai_streamer` with string `s3://` sources - Ray passes the
   > served model id instead of the S3 URI to vLLM, which then falls back to
   > HuggingFace and crashes. The fix
   > ([#64996](https://github.com/ray-project/ray/pull/64996)) is unmerged.
   > Switch back to the streamer once it ships in a ray-llm release.

4. **Bounded multimodal engine config.** The endpoint serves text, image, and
   audio, with per-prompt caps (`limit_mm_per_prompt: {image: 2, audio: 1}`)
   keeping the multimodal activation budget predictable. Measured on this
   deployment, enabling multimodal cost almost no KV cache (15.11 GiB in both
   configs) thanks to Gemma 4's encoder-free unified architecture.
   `async_scheduling`, chunked prefill, prefix caching, and
   `max_num_seqs: 256` follow the
   [official vLLM Gemma 4 recipe](https://github.com/vllm-project/recipes/blob/main/Google/Gemma4.md).

5. **CPU/GPU separation.** The Ray head is control-plane only (`num-cpus: 0`);
   the vLLM engine runs alone on the GPU node.

6. **Karpenter on-demand GPU.** Single L40S: `g6e.2xlarge` preferred,
   `g6e.4xlarge` fallback (2xlarge often hits ICE capacity shortages in
   us-west-2). The node is reclaimed after the service is deleted.

   **Why not the cheaper g5.2xlarge (A10G 24GB)?** The bf16 weights alone are
   22.83 GiB; at `gpu_memory_utilization: 0.90` an A10G's budget is 21.6 GiB -
   the model does not fit at all, before allocating a single KV-cache byte.
   To run Gemma 4 12B on A10G-class GPUs, use the official QAT variant
   [`google/gemma-4-12B-it-qat-w4a16-ct`](https://huggingface.co/google/gemma-4-12B-it-qat-w4a16-ct)
   (8.3 GiB weights -> ~13 GiB left for KV cache, and ~3x faster weight
   download), and re-point `HF_MODEL_ID`/`MODEL_DIR` at it. Also drop
   `accelerator_type` to `A10G` and lower `max_num_seqs`; A10G has ~half the
   memory bandwidth of an L40S, so expect roughly half the token throughput.

## Prerequisites

The `ray-on-eks` stack deployed with `enable_raydata = true` and
`enable_nvidia_gpu_operator = true`.

```bash
export KUBECONFIG=<repo>/data-stacks/ray-on-eks/kubeconfig.yaml
export S3_BUCKET=$(cd ../../terraform/_local && terraform output -raw s3_bucket_id_spark_history_server)
export AWS_REGION=us-west-2
# No HF_TOKEN needed - Gemma 4 is apache-2.0 (not gated).
```

## Run it

```bash
# 1. One-time: stage weights in S3 + mirror image to ECR
./deploy.sh prepare
kubectl get job model-staging-gemma4-12b -n raydata -w   # wait for Complete

# 2. Optional but recommended: confirm the image registers gemma4_unified
./deploy.sh verify

# 3a. Deploy the endpoint (Karpenter provisions the GPU node)
./deploy.sh service
kubectl get rayservice gemma4-12b -n raydata -w          # wait for Ready

#  -- or --

# 3b. Deploy AND measure the end-to-end deployment time
./deploy.sh measure

# 4. Send a sample request
./deploy.sh test
```

Query the endpoint directly:

```bash
kubectl port-forward svc/gemma4-12b-serve-svc 8000 -n raydata &
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-4-12b-it",
  "messages": [{"role": "user", "content": "Explain vLLM continuous batching in two sentences."}],
  "max_tokens": 256
}'
```

## Testing multimodal inputs (image / audio)

Gemma 4 12B is unified-multimodal, and this deployment serves all three
modalities out of the box: up to **2 images + 1 audio clip per prompt**
(`limit_mm_per_prompt: {image: 2, audio: 1}`). Requests beyond the caps get a
clean 400.

The caps are a throughput dial: multimodal activation budget comes out of the
same `gpu_memory_utilization` pool as the KV cache. For Gemma 4's
encoder-free architecture the measured cost is tiny - 313,555 KV-cache
tokens with `image: 2, audio: 1` vs 313,514 text-only (both 15.11 GiB) -
because there is no separate vision tower to profile. Set both to 0 for
strictly text-only serving if you want image/audio requests rejected at
admission; on encoder-based models the same knob buys back real memory.
Changing the limits and re-running `./deploy.sh service` triggers a KubeRay
zero-downtime upgrade (a second GPU node runs both clusters briefly,
~6-7 min).

**Image understanding** (OpenAI `image_url` content part, public URL - the
vLLM server fetches it):

```bash
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-4-12b-it",
  "messages": [{"role": "user", "content": [
    {"type": "image_url", "image_url": {"url": "https://raw.githubusercontent.com/pytorch/hub/master/images/dog.jpg"}},
    {"type": "text", "text": "Describe this image in one sentence."}
  ]}],
  "max_tokens": 128
}'
# -> "A fluffy white Japanese Spitz dog sits on a green lawn, looking off to
#     the side with its tongue slightly out."
```

Local image file (`data:` URI, base64):

```bash
IMG_B64=$(base64 -i photo.jpg)
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-4-12b-it",
  "messages": [{"role": "user", "content": [
    {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,'"$IMG_B64"'"}},
    {"type": "text", "text": "What objects do you see?"}
  ]}],
  "max_tokens": 128
}'
# -> itemized list: "dog (a white fluffy dog...), grass, foliage/bushes"
```

**Audio understanding** (OpenAI `input_audio` content part, base64 wav):

```bash
# macOS: generate a spoken test clip (or use any 16kHz PCM wav)
say -o sample.wav --data-format=LEI16@16000 \
  "The quick brown fox jumps over the lazy dog near the river bank."

AUDIO_B64=$(base64 -i sample.wav)
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-4-12b-it",
  "messages": [{"role": "user", "content": [
    {"type": "input_audio", "input_audio": {"data": "'"$AUDIO_B64"'", "format": "wav"}},
    {"type": "text", "text": "What exactly is said in this audio clip?"}
  ]}],
  "max_tokens": 128
}'
# -> "The quick brown fox jumps over the lazy dog near the river."
```

Text-only requests keep working unchanged in multimodal mode. All four
request shapes above (URL image, base64 image, base64 audio, plain text) were
executed against a live deployment with `image: 2, audio: 1` limits; the
arrow comments are the actual model responses.

## Measured end-to-end deployment timing

`./deploy.sh measure` prints a phase breakdown (Karpenter reaction, node Ready,
image pull, container start, Serve replica init, S3 weight download + vLLM
engine init) and the total from *RayService applied* to *endpoint serving a
request*, labeled COLD (fresh Karpenter node) or WARM (node already present).

Measured on a real COLD run (us-west-2, fresh `g6e.2xlarge` Karpenter node,
2026-07-27):

| Phase | Duration |
|---|---|
| GPU pod created -> scheduled (Karpenter provisions + boots node) | 1m 28s |
| Pod scheduled -> container Ready (SOCI-accelerated 11.7GB ECR pull + start) | 2m 56s |
| Serve replica init, of which: | ~5m 20s |
| &nbsp;&nbsp;- S3 -> node NVMe weight download (22.3 GiB, parallel boto3) | 2m 05s |
| &nbsp;&nbsp;- vLLM load from NVMe to GPU memory | 2.5s |
| &nbsp;&nbsp;- torch.compile | 50s |
| &nbsp;&nbsp;- engine init total (profile, KV cache alloc, CUDA graph capture, warmup) | 1m 25s |
| **Total: RayService applied -> serving a request (cold)** | **9m 58s** |

A WARM run (GPU node already present, image cached on the node) measured the
same day:

| Phase | Duration |
|---|---|
| GPU pod created -> scheduled | 0m 00s |
| Pod scheduled -> container Ready (image already on node) | 0m 53s |
| Serve replica init (download + engine init, same as cold) | ~5m 15s |
| **Total: RayService applied -> serving a request (warm)** | **6m 28s** |

Resulting engine capacity on the 48GB L40S: 22.83 GiB weights + 15.11 GiB KV
cache (313K tokens at 32K `max_model_len`).

Further cold-start headroom (not enabled here): once ray-project/ray#64996
ships, `load_format: runai_streamer` streams S3 straight to GPU (~3 GB/s vs
~190 MB/s observed for the mirror download) and removes the 2-minute download
phase; persisting `~/.cache/vllm/torch_compile_cache` (e.g. to S3) across
restarts removes most of the 50s compile step.

## Batch inference with Ray (customer demo path)

This endpoint is OpenAI-compatible, so the `ray-batch-inference` example's
Pattern 1 works against it unchanged: a RayJob reads records with Ray Data on
CPU nodes and fans out HTTP requests to this service. Point that example's
endpoint config at `http://gemma4-12b-serve-svc.raydata:8000/v1` and set
`model: gemma-4-12b-it`. For maximum throughput per GPU-hour, adapt Pattern 2
(`ray.data.llm` with the vLLM engine inside the batch job) with this example's
`engine_kwargs`.

## Files

| File | Purpose |
|---|---|
| `01-model-staging-job.yaml` | HF -> S3 safetensors staging (no token; Xet high-performance transfer) |
| `02-image-mirror-job.yaml` | Docker Hub -> ECR skopeo mirror (shared ray-llm image) |
| `03-rayservice-gemma4-12b.yaml` | RayService: vLLM + S3 mirror weights, text-optimized |
| `deploy.sh` | Renders placeholders and applies everything |
| `measure-deployment.sh` | Times a fresh deploy end-to-end |

## Cleanup

```bash
./deploy.sh cleanup   # deletes the RayService; keeps S3 weights + ECR image
```
