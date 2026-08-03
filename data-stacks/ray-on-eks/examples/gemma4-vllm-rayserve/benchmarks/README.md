# Single-request latency benchmark

Measures what a latency-sensitive caller actually feels against the Gemma 4
endpoint: **TTFT**, **end-to-end latency**, and **decode throughput**, one
request at a time.

## 1. Prerequisite: the endpoint must be running

The benchmark measures a live endpoint, so deploy it first. All commands run
from the example directory one level up (`gemma4-vllm-rayserve/`).

```bash
cd ..

export KUBECONFIG=<repo>/data-stacks/ray-on-eks/kubeconfig.yaml
export S3_BUCKET=$(cd ../../terraform/_local && terraform output -raw s3_bucket_id_spark_history_server)
export AWS_REGION=us-west-2

./deploy.sh prepare    # one-time: stage weights in S3, mirror image to ECR
./deploy.sh service    # deploy the endpoint; Karpenter provisions the GPU node
```

**Wait for it to report Ready before benchmarking.** A cold deploy takes about
10 minutes - Karpenter boots the node, pulls an 11.7 GB image, downloads 22.3 GiB
of weights, then vLLM compiles and captures CUDA graphs.

```bash
kubectl get rayservice gemma4-12b -n raydata -w
# wait for SERVICE STATUS: Running

./deploy.sh test       # sanity-check that it answers a request
```

Benchmarking before the engine finishes initialising gives meaningless numbers,
so do not skip the wait.

> If you also want deployment timings, run `./measure-deployment.sh` **instead
> of** `./deploy.sh service`. It deletes any existing RayService before starting
> its clock, so running it *after* a deploy throws that deploy away and starts
> the ~10 minute cold start over.

## 2. Add your prompts

One prompt per file, any extension. The whole file becomes the user message.

```bash
mkdir -p benchmarks/prompt-files     # gitignored - your prompts stay local
cp /path/to/your/prompts/* benchmarks/prompt-files/
```

## 3. Run the benchmark

Run both modes - they bracket the real-world number (see *Why it is built this
way* below).

```bash
# cache-cold: every request prefills. The conservative number.
./run-latency-benchmark.sh benchmarks/prompt-files \
    --cache-mode cold --repeats 3 --max-tokens 512

# cache-warm: repeated identical prefix. The best case.
./run-latency-benchmark.sh benchmarks/prompt-files \
    --cache-mode warm --repeats 3 --max-tokens 512
```

Each run takes a few minutes - it sends `repeats x prompts` requests
sequentially, plus warmup.

Useful flags: `--repeats N`, `--max-tokens N`, `--ignore-eos` (force exactly
`--max-tokens` output for a clean decode rate), `--temperature`.

## 4. Where to see the results

**On screen**, live, one line per request as it completes, then a summary table:

```
prompt                        in tok  out tok  TTFT p50  TTFT p95  E2E p50   decode   ITL p50
-------------------------------------------------------------------------------------------
prompt_2k_token.txt             2306      512    415.6m    459.2m   26.45s   19.6/s     50.0m
prompt_20K_token               20554      512   3854.0m   3875.4m   24.67s   24.5/s     50.1m
profile_fact_LARGE.txt         31405      512   6771.6m   6895.8m   31.02s   21.1/s     50.1m
```

Below that, vLLM's own server-side counters for the same window, as an
independent cross-check on the client-side timings.

**On disk**, full detail including every individual iteration and the model's
responses:

```
benchmarks/results-latency-<timestamp>.json
```

That file is gitignored - it contains your prompts' responses.

## Why it is built this way

**It runs inside the cluster.** TTFT is a millisecond measurement. Driving it
from a laptop through `kubectl port-forward` folds your internet round-trip and
the port-forward's own jitter into every number. The script copies itself into
the Ray head pod and runs there.

**It streams.** TTFT is only observable on a streaming response, and token
counts come from the server's `usage` block rather than being estimated.

**Cache state is explicit.** vLLM's prefix cache makes a repeated prompt cheap
to prefill, so averaging N repeats of one prompt silently reports a cache-hit
TTFT. `--cache-mode cold` prepends a unique nonce per iteration to force a real
prefill; `--cache-mode warm` repeats byte-identically. Real workloads sit
between the two, so run both.

## Reading the output

- **Decode tok/s** is the number to trust for generation speed. Median
  inter-token latency is misleading here - `async_scheduling` delivers tokens in
  bursts.
- **`max_model_len` bounds input + output combined.** If a prompt nearly fills
  it, generation truncates and E2E looks deceptively fast. Check output token
  counts against your cap before believing a result.
- Prompts sharing a long prefix will cache across *different* files, not just
  repeats of one.

## When you are done

```bash
./deploy.sh cleanup                                  # delete the RayService
kubectl delete nodeclaim -l karpenter.sh/nodepool=gpu # release the GPU now
```

Karpenter reclaims the node on its own after a few minutes, but the second
command stops the billing immediately.
