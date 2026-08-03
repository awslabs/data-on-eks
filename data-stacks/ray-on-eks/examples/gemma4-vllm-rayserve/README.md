# Gemma 4 12B on RayServe + vLLM

An OpenAI-compatible endpoint for
[`google/gemma-4-12B-it`](https://huggingface.co/google/gemma-4-12B-it) on the
`ray-on-eks` stack, served by **vLLM 0.25** on **Ray 2.57** (KubeRay), on a
single **L40S 48GB** provisioned by Karpenter. Text, image and audio in; one
GPU node; cold start tuned end to end.

## Model facts

| | |
|---|---|
| Architecture | `Gemma4UnifiedForConditionalGeneration` - encoder-free unified multimodal (text + image + audio) |
| `model_type` | `gemma4_unified` (needs transformers >= 5.10, vLLM >= 0.19) |
| Parameters | 11.96B, bf16 -> **22.83 GiB** weights, a single unsharded `model.safetensors` |
| Context window | **256K** (`max_position_embeddings: 262144`); this config runs `max_model_len` at 64K |
| Attention | 5:1 interleaved - 40 of 48 layers `sliding_attention` (window 1024), 8 `full_attention`. Only the 8 full layers grow KV with sequence length (~64 KiB/token), so a 31K-token prompt costs ~2.2 GiB of KV |
| Chat template | Separate `chat_template.jinja`, staged alongside the JSON configs |
| License | **apache-2.0, not gated** - no HuggingFace token needed |

## What makes it fast

| Stage | Technique |
|---|---|
| GPU node | Karpenter provisions `g6e` on demand - no idle GPU |
| Image pull | 11.7 GB ray-llm image mirrored to same-region ECR, pulled with SOCI parallel unpack (`FastImagePull` on the `gpu` EC2NodeClass) |
| Weight staging | HuggingFace -> S3 once, ahead of time - never on the node's critical path |
| Weight load | Same-region S3 -> node NVMe (parallel boto3), then NVMe -> GPU |
| Engine | `async_scheduling`, chunked prefill, prefix caching, CUDA graphs - per the [official vLLM Gemma 4 recipe](https://github.com/vllm-project/recipes/blob/main/Google/Gemma4.md) |
| Isolation | Ray head is control-plane only (`num-cpus: 0`); the engine has the GPU node to itself |

Two things worth knowing before you change the config:

> **Don't set `load_format: runai_streamer`.** Streaming S3 straight to GPU
> would cut the 2-minute weight download to ~10-25s, but it crashes on Ray 2.57
> ([ray#64978](https://github.com/ray-project/ray/issues/64978) - the S3 URI
> isn't passed through, so vLLM falls back to HuggingFace and dies). Ray 2.56
> streams correctly but predates Gemma 4 entirely, so the version that runs this
> model is the version with the bug. Revisit when
> [#64996](https://github.com/ray-project/ray/pull/64996) ships.

> **Gemma 4 12B in bf16 does not fit on a 24GB card.** The weights alone are
> 22.83 GiB; at `gpu_memory_utilization: 0.90` an A10G or L4 budget is ~21.6 GiB,
> short before a single KV-cache byte. Use the QAT variant
> [`gemma-4-12B-it-qat-w4a16-ct`](https://huggingface.co/google/gemma-4-12B-it-qat-w4a16-ct)
> (8.3 GiB) and drop `accelerator_type` accordingly.

## Prerequisites

The `ray-on-eks` stack with `enable_raydata = true` and
`enable_nvidia_gpu_operator = true`.

```bash
export KUBECONFIG=<repo>/data-stacks/ray-on-eks/kubeconfig.yaml
export S3_BUCKET=$(cd ../../terraform/_local && terraform output -raw s3_bucket_id_spark_history_server)
export AWS_REGION=us-west-2
```

## Run it

```bash
./deploy.sh prepare    # one-time: stage weights in S3, mirror image to ECR
./deploy.sh verify     # confirm the image registers gemma4_unified
./deploy.sh service    # deploy the endpoint (Karpenter provisions the GPU node)

kubectl get rayservice gemma4-12b -n raydata -w   # wait for Ready (~10 min cold)

./deploy.sh test       # send a sample request
```

To deploy *and* get a phase-by-phase timing breakdown, run
`./measure-deployment.sh` **instead of** `./deploy.sh service` - it deletes any
existing RayService first so it can time a clean cold start.

Query it directly:

```bash
kubectl port-forward svc/gemma4-12b-serve-svc 8000 -n raydata &
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-4-12b-it",
  "messages": [{"role": "user", "content": "Explain vLLM continuous batching in two sentences."}],
  "max_tokens": 256
}'
```

## Image and audio input

Multimodal is on, capped at 2 images + 1 audio clip per prompt
(`limit_mm_per_prompt`). Requests over the cap get a clean 400. Set both to 0
for text-only serving - on Gemma 4 that buys back almost no KV cache (measured
at 32K context: a 41-token difference) because there is no separate vision
tower, but on encoder-based models the same knob matters.

```bash
# image, by URL (the server fetches it) - a data: URI with base64 also works
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-4-12b-it",
  "messages": [{"role": "user", "content": [
    {"type": "image_url", "image_url": {"url": "https://raw.githubusercontent.com/pytorch/hub/master/images/dog.jpg"}},
    {"type": "text", "text": "Describe this image in one sentence."}
  ]}], "max_tokens": 128
}'
# -> "A fluffy white Japanese Spitz dog sits on a green lawn..."

# audio, base64 wav (macOS: say -o sample.wav --data-format=LEI16@16000 "...")
AUDIO_B64=$(base64 -i sample.wav)
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-4-12b-it",
  "messages": [{"role": "user", "content": [
    {"type": "input_audio", "input_audio": {"data": "'"$AUDIO_B64"'", "format": "wav"}},
    {"type": "text", "text": "What exactly is said in this audio clip?"}
  ]}], "max_tokens": 128
}'
```

## Measured: startup

`./deploy.sh measure` times a fresh deploy and prints a phase breakdown.
Measured on a cold run (fresh on-demand `g6e.2xlarge`, us-west-2):

| Phase | Duration |
|---|---|
| Applied -> GPU pod scheduled (Karpenter provisions + boots) | 1m 22s |
| Scheduled -> image pulled (SOCI-accelerated 11.7GB ECR pull) | 2m 04s |
| Image pulled -> container Ready (init + start) | 51s |
| S3 -> node NVMe weight download (22.3 GiB @ ~123 MB/s) | 3m 06s |
| NVMe -> GPU model load | 2.5s |
| Engine init total (torch.compile 49s, graph capture 12s, warmup) | 84s |
| **Applied -> replica able to serve (cold)** | **9m 10s** |
| **Same, warm node with image cached** | **~6m 30s** |

Measured on a *verified* cold start - no GPU node **and** no pending NodeClaim
before the clock started. Deleting the RayService alone leaves the node up, so
a re-deploy straight afterwards is a warm start even though nothing is serving;
`measure-deployment.sh` now checks for both and says which it measured.

The weight download is the most variable phase: 2m 05s to 3m 06s observed for
the same 22.3 GiB. It runs at ~123 MB/s because Gemma 4 is a *single*
safetensors file, so ray-llm's across-files download pool has nothing to
parallelise and you get boto3's single-file default. Treat any single
cold-start total as +/- 1 minute.

Engine capacity on the 48GB L40S: 22.83 GiB weights + **15.11 GiB KV cache =
476,236 tokens**. The KV pool is sized by `gpu_memory_utilization`, not by
`max_model_len` - raising the limit from 32K to 64K left it at exactly 15.11 GiB.

Remaining headroom: persisting `~/.cache/vllm/torch_compile_cache` across
restarts removes most of the compile step, and the streaming loader above
removes the 2-minute download once it's usable.

## Measured: request latency

One request at a time, warm engine, 512 output tokens, client in-cluster:

| Input tokens | TTFT (cold cache) | TTFT (warm cache) | E2E (cold) | Decode |
|---:|---:|---:|---:|---:|
| 2,300 | 0.37 s | 115 ms | 18.8 s | ~28 tok/s |
| 20,500 | 3.77 s | 132 ms | 23.6 s | ~26 tok/s |
| 31,400 | 6.46 s | 170 ms | 26.7 s | ~25 tok/s |

Three things fall out of this:

- **TTFT tracks prompt length linearly** at roughly `0.21 ms x input_tokens`
  (~4,860 tok/s prefill).
- **Decode sits at 25-28 tok/s and does not degrade with context length**,
  thanks to the sliding-window attention above. That is 72-79% of the
  theoretical ceiling of 35.2 tok/s (22.83 GiB of weights re-read per token /
  864 GB/s of bandwidth) - high for a bf16 dense model on a fallback attention
  backend.
- **Prefix caching is the biggest single lever and it is free** - warm TTFT is
  flat at 115-172 ms whatever the prompt size. The win scales with prompt
  length: **3x on a 2.3K prompt, 28-38x on the 20K-31K ones**, because short
  prompts have little prefill to skip. It is a prompt-layout decision: put
  static instructions first.

Five of the six test prompts hit the 512-token cap and were still generating, so
these E2E figures are for a 512-token answer, not a complete one. Scale by your
real output length at roughly 3.8 s per extra 100 tokens.

Note the attention backend is **`TRITON_ATTN`, not FlashAttention** - Gemma 4's
sliding and global layers have different head dimensions (256 vs 512), so vLLM
forces the fallback. That applies on any GPU, not just L40S.

Reproduce with `benchmarks/` - see that folder's README.

## Batch inference with Ray

This endpoint is OpenAI-compatible, so the `ray-batch-inference` example's
Pattern 1 works against it unchanged. Point that example at
`http://gemma4-12b-serve-svc.raydata:8000/v1` with `model: gemma-4-12b-it`. For
best throughput per GPU-hour, adapt its Pattern 2 (`ray.data.llm`, engine inside
the job) using this example's `engine_kwargs`.

## Files

| File | Purpose |
|---|---|
| `01-model-staging-job.yaml` | HuggingFace -> S3 weight staging (no token needed) |
| `02-image-mirror-job.yaml` | Docker Hub -> ECR skopeo mirror |
| `03-rayservice-gemma4-12b.yaml` | The RayService itself |
| `deploy.sh` | Renders placeholders and applies everything |
| `measure-deployment.sh` | Times a fresh deploy end to end. **Deletes any existing RayService first** so the clock starts clean - use it *instead of* `./deploy.sh service`, not after it (`KEEP_EXISTING=1` skips the delete) |
| `benchmark-latency.py` | TTFT / E2E / decode measurement against any OpenAI-compatible endpoint |
| `run-latency-benchmark.sh` | Runs that harness in-cluster and collects results |
| `benchmarks/` | Benchmark docs; prompts and results stay local (gitignored) |

## Cleanup

```bash
./deploy.sh cleanup   # deletes the RayService; keeps S3 weights + ECR image
```

Karpenter reclaims the GPU node a few minutes later. To release it immediately,
delete its NodeClaim: `kubectl delete nodeclaim -l karpenter.sh/nodepool=gpu`.
