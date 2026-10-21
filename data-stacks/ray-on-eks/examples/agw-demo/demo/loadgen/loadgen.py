"""Multi-team load generator for the agw-demo gateway (runs as an in-cluster Job).

Each team sends its own mix of traffic with its own API key:
  chat   POST /v1/chat/completions   (model gemma-12b)
  embed  POST /v1/embeddings          (model qwen3-embedding-0.6b, HTTP)
  grpc   embeddings.v1.EmbeddingService/Embed (gRPC, port 9090)

Rates are requests/second per team per kind (open loop: requests are fired on
schedule whether or not earlier ones finished, so overload shows up as errors
or latency instead of the client slowing down).

Prints a per-team summary (status counts, p50/p95/p99 latency, tokens) as
JSON at the end. Usage:
  python loadgen.py --duration 180 --profile mixed
  python loadgen.py --duration 60 --profile custom --spec 'team-labs:chat=5'
"""
import argparse
import asyncio
import json
import os
import random
import statistics
import time
from collections import defaultdict

import grpc
import httpx

import embeddings_pb2
import embeddings_pb2_grpc

GW_HTTP = os.environ.get("GW_HTTP", "http://agw-demo-gw.agentgateway-system:8080")
GW_GRPC = os.environ.get("GW_GRPC", "agw-demo-gw.agentgateway-system:9090")
KEYS = {
    "team-search": os.environ.get("TEAM_SEARCH_KEY", ""),
    "team-support": os.environ.get("TEAM_SUPPORT_KEY", ""),
    "team-labs": os.environ.get("TEAM_LABS_KEY", ""),
}

PROFILES = {
    # Steady, realistic mix (rates are PER JOB; run.sh starts one Job per AZ,
    # so cluster-wide traffic is 3x). Stays within Gemma's capacity: search is
    # big on embeddings, support on chat, labs is small and occasionally hits
    # its per-pod limits.
    "mixed": {
        "team-search": {"chat": 0.3, "grpc": 2.0},
        "team-support": {"chat": 0.3, "embed": 0.5},
        "team-labs": {"chat": 0.2},
    },
    # Noisy neighbour: labs floods, search keeps normal traffic.
    "noisy": {
        "team-search": {"chat": 1.0},
        "team-labs": {"chat": 8.0},
    },
    # Background traffic for availability drills (per Job; 3 Jobs = 3x).
    # Low enough that ONE Gemma replica can carry it alone.
    "steady": {
        "team-search": {"chat": 0.4, "grpc": 2.0},
        "team-support": {"embed": 0.5},
    },
    # Saturate Gemma: far beyond max_ongoing_requests x replicas.
    "overload": {
        "team-search": {"chat": 40.0},
    },
}

QUESTIONS = [
    "Summarise the benefits of Kubernetes for ML platforms in three bullet points.",
    "Explain what a KV cache is in LLM inference.",
    "Write a short SQL query that counts orders per customer.",
    "What is the difference between spot and on-demand EC2 instances?",
    "Give me a haiku about GPUs.",
    "Explain gRPC vs REST for internal APIs in two sentences.",
    "List four ways to reduce LLM serving cost.",
    "Describe multi-AZ high availability in one paragraph.",
]
DOCS = [
    "Amazon EKS runs Kubernetes on AWS.",
    "Ray Serve scales Python model serving.",
    "vLLM uses paged attention for efficient KV cache management.",
    "agentgateway enforces per-team rate limits and records token usage.",
    "Embeddings map text to dense vectors for semantic search.",
]


class Stats:
    def __init__(self):
        self.window = defaultdict(lambda: defaultdict(int))  # per-interval counts for --timeline
        self.codes = defaultdict(lambda: defaultdict(int))  # (team,kind) -> code -> n
        self.lat = defaultdict(list)  # (team,kind) -> [ms] for successes
        self.tokens = defaultdict(lambda: defaultdict(int))  # (team,kind) -> in/out -> n

    def add(self, team, kind, code, ms, tin=0, tout=0):
        self.codes[(team, kind)][str(code)] += 1
        self.window[f"{team}/{kind}"][str(code)] += 1
        if str(code) in ("200", "OK"):
            self.lat[(team, kind)].append(ms)
            self.tokens[(team, kind)]["in"] += tin
            self.tokens[(team, kind)]["out"] += tout

    def summary(self):
        out = {}
        for key in sorted(self.codes):
            lat = sorted(self.lat[key])
            pct = lambda p: round(lat[min(len(lat) - 1, int(p * len(lat)))], 1) if lat else None
            out[f"{key[0]}/{key[1]}"] = {
                "status": dict(self.codes[key]),
                "p50_ms": pct(0.50), "p95_ms": pct(0.95), "p99_ms": pct(0.99),
                "mean_ms": round(statistics.mean(lat), 1) if lat else None,
                "tokens_in": self.tokens[key]["in"], "tokens_out": self.tokens[key]["out"],
            }
        return out


async def do_chat(client, team, stats, max_tokens):
    # Half the chats stream (the gateway records time-to-first-token for those).
    stream = random.random() < 0.5
    body = {"model": "gemma-12b", "max_tokens": max_tokens, "stream": stream,
            "messages": [{"role": "user", "content": random.choice(QUESTIONS)}]}
    headers = {"Authorization": f"Bearer {KEYS[team]}"}
    kind = "chat-stream" if stream else "chat"
    t0 = time.perf_counter()
    try:
        if not stream:
            r = await client.post(f"{GW_HTTP}/v1/chat/completions", json=body, headers=headers)
            ms = (time.perf_counter() - t0) * 1000
            u = r.json().get("usage", {}) if r.status_code == 200 else {}
            stats.add(team, kind, r.status_code, ms, u.get("prompt_tokens", 0), u.get("completion_tokens", 0))
            return
        async with client.stream("POST", f"{GW_HTTP}/v1/chat/completions", json=body, headers=headers) as r:
            u = {}
            if r.status_code == 200:
                async for line in r.aiter_lines():
                    if line.startswith("data: {") and '"usage":{' in line:
                        u = json.loads(line[6:]).get("usage") or u
            else:
                await r.aread()
            stats.add(team, kind, r.status_code, (time.perf_counter() - t0) * 1000,
                      u.get("prompt_tokens", 0), u.get("completion_tokens", 0))
    except Exception as e:  # timeouts, resets
        stats.add(team, kind, type(e).__name__, (time.perf_counter() - t0) * 1000)


async def do_embed(client, team, stats):
    body = {"model": "qwen3-embedding-0.6b", "input": random.sample(DOCS, 3)}
    t0 = time.perf_counter()
    try:
        r = await client.post(f"{GW_HTTP}/v1/embeddings", json=body,
                              headers={"Authorization": f"Bearer {KEYS[team]}"})
        ms = (time.perf_counter() - t0) * 1000
        u = r.json().get("usage", {}) if r.status_code == 200 else {}
        stats.add(team, "embed", r.status_code, ms, u.get("prompt_tokens", 0))
    except Exception as e:
        stats.add(team, "embed", type(e).__name__, (time.perf_counter() - t0) * 1000)


async def do_grpc(stub, team, stats):
    req = embeddings_pb2.EmbedRequest(model="qwen3-embedding-0.6b", texts=random.sample(DOCS, 3))
    t0 = time.perf_counter()
    try:
        resp = await stub.Embed(req, metadata=[("authorization", f"Bearer {KEYS[team]}")], timeout=10)
        stats.add(team, "grpc", "OK", (time.perf_counter() - t0) * 1000, resp.prompt_tokens)
    except grpc.aio.AioRpcError as e:
        stats.add(team, "grpc", e.code().name, (time.perf_counter() - t0) * 1000)


async def loop(kind, team, rps, deadline, stats, client, stub, max_tokens):
    tasks = []
    while time.time() < deadline:
        if kind == "chat":
            tasks.append(asyncio.create_task(do_chat(client, team, stats, max_tokens)))
        elif kind == "embed":
            tasks.append(asyncio.create_task(do_embed(client, team, stats)))
        else:
            tasks.append(asyncio.create_task(do_grpc(stub, team, stats)))
        await asyncio.sleep(random.expovariate(rps))
    await asyncio.gather(*tasks)


async def timeline(stats, every, deadline):
    """Print status counts per interval, so failure drills show when errors happen."""
    while time.time() < deadline + every:
        await asyncio.sleep(every)
        snap, stats.window = stats.window, defaultdict(lambda: defaultdict(int))
        line = " | ".join(f"{k} {dict(v)}" for k, v in sorted(snap.items()))
        print(f"TL {time.strftime('%H:%M:%S')} {line}", flush=True)


def parse_spec(spec):
    prof = defaultdict(dict)
    for part in spec.split(","):
        team, kinds = part.split(":")
        for kv in kinds.split("+"):
            k, v = kv.split("=")
            prof[team][k] = float(v)
    return prof


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--duration", type=int, default=120)
    ap.add_argument("--profile", default="mixed", choices=list(PROFILES) + ["custom"])
    ap.add_argument("--spec", default="", help="custom: 'team-a:chat=1+grpc=2,team-b:embed=1'")
    ap.add_argument("--max-tokens", type=int, default=120)
    ap.add_argument("--timeline", type=int, default=0, help="print status counts every N seconds")
    args = ap.parse_args()
    profile = parse_spec(args.spec) if args.profile == "custom" else PROFILES[args.profile]

    stats = Stats()
    deadline = time.time() + args.duration
    limits = httpx.Limits(max_connections=1000, max_keepalive_connections=200)
    async with httpx.AsyncClient(timeout=httpx.Timeout(120.0), limits=limits) as client, \
            grpc.aio.insecure_channel(GW_GRPC) as channel:
        stub = embeddings_pb2_grpc.EmbeddingServiceStub(channel)
        print(json.dumps({"start": time.strftime("%H:%M:%S"), "profile": profile, "duration_s": args.duration}), flush=True)
        tl = [timeline(stats, args.timeline, deadline)] if args.timeline else []
        await asyncio.gather(*tl, *[
            loop(kind, team, rps, deadline, stats, client, stub, args.max_tokens)
            for team, kinds in profile.items() for kind, rps in kinds.items()
        ])
    print("SUMMARY " + json.dumps(stats.summary(), indent=2), flush=True)


if __name__ == "__main__":
    asyncio.run(main())
