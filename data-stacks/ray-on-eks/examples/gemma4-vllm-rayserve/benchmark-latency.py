#!/usr/bin/env python3
"""
Single-request latency benchmark for an OpenAI-compatible LLM endpoint.

Measures, per prompt, exactly what a latency-sensitive caller feels:

  TTFT     time from request send to the first *content* token
  E2E      time from request send to the final token
  decode   (completion_tokens - 1) / (E2E - TTFT)   [tokens/sec]
  ITL      inter-token latency distribution

Trust `decode` for generation speed, not the ITL median. With
`async_scheduling` enabled the engine delivers tokens in bursts, so the ITL
distribution is bimodal and its median overstates the gap between tokens
(measured: 50 ms median against a 35 ms mean on the same run). ITL is reported
because its *spread* tells you how smooth the stream feels to a user, which is
a different question from how fast it finishes.

Everything is measured client-side over a streaming response, so the numbers
include the serving stack the caller actually traverses (here: the Ray Serve
HTTP proxy in front of vLLM). Run it *inside* the cluster so client network
RTT does not leak into TTFT.

Prefix caching caveat
---------------------
vLLM's prefix cache makes a repeated identical prompt cheap to prefill, so
naively averaging N repeats of one prompt reports a cache-hit TTFT, not a real
one. This script makes the cache state explicit:

  --cache-mode cold   unique nonce prepended per iteration -> prefill every time
                      (pessimistic bound; matches a workload where each request
                      carries a different document)
  --cache-mode warm   byte-identical prompt each iteration -> prefix cache hit
                      (optimistic bound; matches a repeated shared prefix)

Real workloads land between the two. Report both.

Usage
-----
Normally you do not run this directly - ../run-latency-benchmark.sh copies it
into the Ray head pod and runs it there, which is what keeps client network RTT
out of TTFT. Use that wrapper unless you already have in-cluster access:

  ./run-latency-benchmark.sh benchmarks/prompt-files --cache-mode cold

Direct invocation, if you are already inside the cluster:

  python3 benchmark-latency.py \
      --base-url http://gemma4-12b-serve-svc.raydata:8000 \
      --model gemma-4-12b-it \
      --prompt-dir ./prompt-files \
      --repeats 3 --max-tokens 512 --cache-mode cold
"""

import argparse
import json
import os
import statistics
import sys
import time
import urllib.error
import urllib.request
import uuid


def pct(values, p):
    """Percentile with linear interpolation; tolerates tiny samples."""
    if not values:
        return float("nan")
    if len(values) == 1:
        return values[0]
    s = sorted(values)
    k = (len(s) - 1) * (p / 100.0)
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def one_request(base_url, model, content, max_tokens, temperature, ignore_eos,
                timeout):
    """Send one streaming chat completion; return timing + token counts.

    Returns a dict with ttft_s, e2e_s, itls (list), prompt_tokens,
    completion_tokens, token_source ('usage' or 'chunks'), and text_len.
    """
    body = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": max_tokens,
        "temperature": temperature,
        "stream": True,
        # Ask the server for exact token accounting in the final chunk.
        "stream_options": {"include_usage": True},
    }
    if ignore_eos:
        # vLLM extension: generate exactly max_tokens so decode rate is
        # measured over a fixed length regardless of when the model would stop.
        body["ignore_eos"] = True

    req = urllib.request.Request(
        base_url.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    ttft = None
    last = None
    itls = []
    n_content_chunks = 0
    text_len = 0
    usage = None
    pieces = []

    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        for raw in resp:
            line = raw.decode("utf-8").strip()
            if not line or not line.startswith("data:"):
                continue
            payload = line[len("data:"):].strip()
            if payload == "[DONE]":
                break
            try:
                obj = json.loads(payload)
            except json.JSONDecodeError:
                continue

            # The usage-only final chunk has empty choices.
            if obj.get("usage"):
                usage = obj["usage"]

            choices = obj.get("choices") or []
            if not choices:
                continue
            delta = choices[0].get("delta") or {}
            piece = delta.get("content") or ""
            if not piece:
                # role-only opening chunk: not a token, do not count as TTFT
                continue

            now = time.perf_counter()
            if ttft is None:
                ttft = now - t0
            else:
                itls.append(now - last)
            last = now
            n_content_chunks += 1
            text_len += len(piece)
            pieces.append(piece)
    e2e = time.perf_counter() - t0

    if usage:
        prompt_tokens = usage.get("prompt_tokens")
        completion_tokens = usage.get("completion_tokens")
        token_source = "usage"
    else:
        # Fallback: vLLM streams ~1 token per content chunk.
        prompt_tokens = None
        completion_tokens = n_content_chunks
        token_source = "chunks"

    return {
        "ttft_s": ttft,
        "e2e_s": e2e,
        "itls": itls,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "token_source": token_source,
        "text_len": text_len,
        "response": "".join(pieces),
    }


def summarize(name, prompt_file_tokens, runs):
    """Aggregate repeats of one prompt into a report row."""
    ttfts = [r["ttft_s"] for r in runs if r["ttft_s"] is not None]
    e2es = [r["e2e_s"] for r in runs]
    outs = [r["completion_tokens"] for r in runs]
    all_itls = [x for r in runs for x in r["itls"]]

    decodes = []
    for r in runs:
        if r["ttft_s"] is None or r["completion_tokens"] in (None, 0, 1):
            continue
        decode_window = r["e2e_s"] - r["ttft_s"]
        if decode_window > 0:
            decodes.append((r["completion_tokens"] - 1) / decode_window)

    return {
        "prompt": name,
        "input_tokens_measured": runs[0].get("prompt_tokens"),
        "input_tokens_local": prompt_file_tokens,
        "n": len(runs),
        "ttft_med_ms": statistics.median(ttfts) * 1000 if ttfts else float("nan"),
        "ttft_p95_ms": pct(ttfts, 95) * 1000 if ttfts else float("nan"),
        "e2e_med_s": statistics.median(e2es),
        "e2e_p95_s": pct(e2es, 95),
        "out_tokens_med": statistics.median(outs) if outs else 0,
        "decode_med_tps": statistics.median(decodes) if decodes else float("nan"),
        "itl_med_ms": statistics.median(all_itls) * 1000 if all_itls else float("nan"),
        "itl_p95_ms": pct(all_itls, 95) * 1000 if all_itls else float("nan"),
        "token_source": runs[0]["token_source"],
        # Keep one full response per prompt so the report can show what the
        # model actually produced, not just how fast it produced it.
        "response_sample": runs[0].get("response", ""),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--prompt-dir", required=True)
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--warmup", type=int, default=1,
                    help="discarded requests before measuring (engine warm)")
    ap.add_argument("--max-tokens", type=int, default=512)
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--cache-mode", choices=["cold", "warm"], default="cold")
    ap.add_argument("--ignore-eos", action="store_true",
                    help="force exactly --max-tokens output for a clean decode rate")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--out-json", default=None)
    args = ap.parse_args()

    files = sorted(
        os.path.join(args.prompt_dir, f)
        for f in os.listdir(args.prompt_dir)
        if not f.startswith(".")
    )
    files = [f for f in files if os.path.isfile(f)]
    if not files:
        sys.exit(f"no prompt files in {args.prompt_dir}")

    print(f"endpoint    : {args.base_url}")
    print(f"model       : {args.model}")
    print(f"cache mode  : {args.cache_mode}")
    print(f"max_tokens  : {args.max_tokens}  ignore_eos={args.ignore_eos}")
    print(f"repeats     : {args.repeats} (+{args.warmup} warmup)")
    print(f"prompts     : {len(files)}")
    print()

    # Engine warmup: a few tiny requests so CUDA graphs / allocator are hot and
    # the first measured prompt is not paying one-time costs.
    for i in range(args.warmup):
        try:
            one_request(args.base_url, args.model, "Say OK.", 8,
                        args.temperature, False, args.timeout)
        except Exception as e:  # noqa: BLE001
            print(f"[warn] warmup {i} failed: {e}")

    results = []
    raw_records = []
    for path in files:
        name = os.path.basename(path)
        with open(path, encoding="utf-8") as fh:
            base_content = fh.read()

        runs = []
        for i in range(args.repeats):
            if args.cache_mode == "cold":
                # Unique leading bytes invalidate the prefix cache from token 0.
                content = f"[trace-id {uuid.uuid4().hex}]\n{base_content}"
            else:
                content = base_content
            try:
                r = one_request(args.base_url, args.model, content,
                                args.max_tokens, args.temperature,
                                args.ignore_eos, args.timeout)
            except urllib.error.HTTPError as e:
                detail = e.read().decode("utf-8", "replace")[:400]
                print(f"  {name} iter {i}: HTTP {e.code} {detail}")
                continue
            except Exception as e:  # noqa: BLE001
                print(f"  {name} iter {i}: {type(e).__name__} {e}")
                continue

            runs.append(r)
            raw_records.append(dict(prompt=name, iter=i, cache_mode=args.cache_mode,
                                    **{k: v for k, v in r.items() if k != "itls"}))
            preview = " ".join(r.get("response", "").split())[:70]
            print(f"  {name:44s} iter {i}: "
                  f"TTFT {r['ttft_s'] * 1000:8.1f} ms  "
                  f"E2E {r['e2e_s']:7.2f} s  "
                  f"in {str(r['prompt_tokens']):>6}  out {r['completion_tokens']:>5}"
                  f"  | {preview}", flush=True)

        if runs:
            results.append(summarize(name, None, runs))
        print()

    # ---- report -------------------------------------------------------------
    hdr = (f"{'prompt':44s} {'in tok':>7} {'out tok':>8} {'TTFT p50':>10} "
           f"{'TTFT p95':>10} {'E2E p50':>9} {'decode':>9} {'ITL p50':>9}")
    print("=" * len(hdr))
    print(f"RESULTS  (cache={args.cache_mode}, max_tokens={args.max_tokens}, "
          f"ignore_eos={args.ignore_eos})")
    print("=" * len(hdr))
    print(hdr)
    print("-" * len(hdr))
    for r in results:
        print(f"{r['prompt']:44s} "
              f"{str(r['input_tokens_measured']):>7} "
              f"{r['out_tokens_med']:>8.0f} "
              f"{r['ttft_med_ms']:>9.1f}m "
              f"{r['ttft_p95_ms']:>9.1f}m "
              f"{r['e2e_med_s']:>8.2f}s "
              f"{r['decode_med_tps']:>7.1f}/s "
              f"{r['itl_med_ms']:>8.1f}m")
    print("-" * len(hdr))
    print("TTFT/ITL in ms, E2E in s, decode in output tokens/s "
          f"(token counts from '{results[0]['token_source'] if results else 'n/a'}')")

    if args.out_json:
        with open(args.out_json, "w", encoding="utf-8") as fh:
            json.dump({"config": vars(args), "summary": results,
                       "raw": raw_records}, fh, indent=2)
        print(f"\nwrote {args.out_json}")


if __name__ == "__main__":
    main()
