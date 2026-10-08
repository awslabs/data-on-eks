#!/usr/bin/env python3
"""KV cache tiering benchmark: revisit long prefixes after they leave GPU memory.

Phase 1 (populate) sends N distinct long documents, each followed by question A.
Their KV blocks fill the GPU cache and, with KV offloading enabled, cascade to
CPU DRAM and local NVMe. Phase 2 (revisit) sends the same documents with
question B, sharing the document prefix. With a working set larger than the
GPU KV cache:

  * without tiering, revisited prefixes were evicted, so phase 2 prefills again
    (TTFT ~= phase 1);
  * with tiering, prefixes are loaded back from CPU/NVMe (lower TTFT).

Size --docs x --doc-tokens to 2-4x the "GPU KV cache size" vLLM logs at start.
Uses one_request() from benchmark-latency.py (stdlib only).
"""
import argparse
import concurrent.futures as cf
import importlib.util
import json
import random
import statistics
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("bl", HERE / "benchmark-latency.py")
bl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bl)

WORDS = ("account renewal escalation contract pipeline forecast opportunity quota region "
         "segment churn adoption onboarding invoice discount approval stakeholder roadmap "
         "integration latency outage incident priority severity resolution workaround patch "
         "migration license seat usage telemetry dashboard report territory partner").split()


def make_doc(i, n_tokens, seed):
    rng = random.Random(seed * 100003 + i)
    # Unique leading line per doc so documents never share a prefix with each other.
    lines = [f"Case file {seed}-{i:04d}. Customer account ACCT-{rng.randint(10**7, 10**8 - 1)}."]
    approx = 0
    while approx < n_tokens:
        sent = " ".join(rng.choice(WORDS) for _ in range(rng.randint(12, 24)))
        lines.append(f"Note {len(lines)}: {sent}.")
        approx += len(sent.split()) * 1.3 + 4
    return "\n".join(lines)


def run_phase(args, docs, question, label):
    def call(idx):
        content = f"{docs[idx]}\n\nQuestion: {question}"
        try:
            r = bl.one_request(args.base_url, args.model, content, args.max_tokens,
                               0.0, False, args.timeout)
            r.pop("response", None)
        except Exception as e:  # keep the phase going; count the failure
            r = {"error": f"{type(e).__name__}: {e}"}
        return idx, r

    t0 = time.time()
    results = [None] * len(docs)
    with cf.ThreadPoolExecutor(max_workers=args.concurrency) as ex:
        for idx, r in ex.map(call, range(len(docs))):
            results[idx] = r
    wall = time.time() - t0
    ttft = [r["ttft_s"] for r in results if r.get("ttft_s") is not None]
    prompt_tokens = [r.get("prompt_tokens") for r in results if r.get("prompt_tokens")]
    summary = {
        "phase": label,
        "requests": len(results),
        "errors": sum(1 for r in results if r.get("error")),
        "wall_s": round(wall, 3),
        "ttft_p50_s": round(bl.pct(ttft, 50), 4) if ttft else None,
        "ttft_p90_s": round(bl.pct(ttft, 90), 4) if ttft else None,
        "ttft_mean_s": round(statistics.mean(ttft), 4) if ttft else None,
        "prompt_tokens_mean": round(statistics.mean(prompt_tokens)) if prompt_tokens else None,
    }
    print(json.dumps(summary))
    return summary, results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--docs", type=int, default=48)
    ap.add_argument("--doc-tokens", type=int, default=8000)
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--max-tokens", type=int, default=16)
    ap.add_argument("--seed", type=int, default=int(time.time()))
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--scenario", default="unknown")
    ap.add_argument("--out-json", required=True)
    args = ap.parse_args()

    docs = [make_doc(i, args.doc_tokens, args.seed) for i in range(args.docs)]
    populate, raw1 = run_phase(args, docs, "List the three most urgent issues in this case file.", "populate")
    revisit, raw2 = run_phase(args, docs, "Summarize this case file in two sentences.", "revisit")
    out = {
        "complete": True,
        "scenario": args.scenario,
        "config": vars(args),
        "summary": [populate, revisit],
        "revisit_ttft_speedup": (round(populate["ttft_p50_s"] / revisit["ttft_p50_s"], 2)
                                 if populate["ttft_p50_s"] and revisit["ttft_p50_s"] else None),
        "raw": {"populate": raw1, "revisit": raw2},
    }
    Path(args.out_json).write_text(json.dumps(out, indent=2))
    print(json.dumps({k: out[k] for k in ("scenario", "summary", "revisit_ttft_speedup")}, indent=2))


if __name__ == "__main__":
    main()
