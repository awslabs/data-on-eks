#!/usr/bin/env python3
"""Embedding throughput/latency sweep against an OpenAI-compatible /v1/embeddings.

For each (concurrency, batch size) it sends --requests requests of `batch`
synthetic passages (~--input-tokens tokens each) and reports latency p50/p90/p99,
requests/s, embeddings/s and input tokens/s (server-reported usage).
Stdlib only, so it runs on the Ray head pod without extra installs.
"""
import argparse
import concurrent.futures as cf
import json
import random
import time
import urllib.request
from pathlib import Path

WORDS = ("customer account renewal contract pipeline forecast opportunity escalation "
         "support case priority resolution integration migration license adoption usage "
         "billing invoice territory partner product feature release incident outage").split()


def passage(rng, n_tokens):
    return "passage: " + " ".join(rng.choice(WORDS) for _ in range(int(n_tokens / 1.3)))


def pct(values, p):
    v = sorted(values)
    if not v:
        return None
    k = (len(v) - 1) * p / 100
    f = int(k)
    c = min(f + 1, len(v) - 1)
    return v[f] + (v[c] - v[f]) * (k - f)


def embed(base_url, model, inputs, timeout):
    body = json.dumps({"model": model, "input": inputs}).encode()
    req = urllib.request.Request(base_url.rstrip("/") + "/v1/embeddings", data=body,
                                 headers={"Content-Type": "application/json"}, method="POST")
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        out = json.loads(resp.read())
    dt = time.perf_counter() - t0
    return {"latency_s": dt, "n": len(out["data"]), "dim": len(out["data"][0]["embedding"]),
            "prompt_tokens": (out.get("usage") or {}).get("prompt_tokens")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--concurrency", default="1,8,32,64")
    ap.add_argument("--batch", default="1,32")
    ap.add_argument("--input-tokens", type=int, default=256)
    ap.add_argument("--requests", type=int, default=200)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--scenario", default="unknown")
    ap.add_argument("--out-json", required=True)
    args = ap.parse_args()

    rng = random.Random(7)
    corpus = [passage(rng, args.input_tokens) for _ in range(2048)]
    embed(args.base_url, args.model, corpus[:8], args.timeout)  # warm-up
    results = []
    for batch in [int(x) for x in args.batch.split(",")]:
        for conc in [int(x) for x in args.concurrency.split(",")]:
            def call(i):
                start = (i * batch) % (len(corpus) - batch)
                try:
                    return embed(args.base_url, args.model, corpus[start:start + batch], args.timeout)
                except Exception as e:
                    return {"error": f"{type(e).__name__}: {e}"}
            t0 = time.perf_counter()
            with cf.ThreadPoolExecutor(max_workers=conc) as ex:
                runs = list(ex.map(call, range(args.requests)))
            wall = time.perf_counter() - t0
            ok = [r for r in runs if "error" not in r]
            lat = [r["latency_s"] for r in ok]
            toks = sum(r["prompt_tokens"] or 0 for r in ok)
            row = {"batch": batch, "concurrency": conc, "requests": len(runs),
                   "errors": len(runs) - len(ok), "wall_s": round(wall, 3),
                   "latency_p50_ms": round(pct(lat, 50) * 1000, 1) if lat else None,
                   "latency_p90_ms": round(pct(lat, 90) * 1000, 1) if lat else None,
                   "latency_p99_ms": round(pct(lat, 99) * 1000, 1) if lat else None,
                   "requests_per_s": round(len(ok) / wall, 2),
                   "embeddings_per_s": round(sum(r["n"] for r in ok) / wall, 1),
                   "input_tokens_per_s": round(toks / wall, 1),
                   "dim": ok[0]["dim"] if ok else None}
            print(json.dumps(row), flush=True)
            results.append(row)
    Path(args.out_json).write_text(json.dumps(
        {"complete": True, "scenario": args.scenario, "config": vars(args), "results": results}, indent=2))


if __name__ == "__main__":
    main()
