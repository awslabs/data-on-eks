"""Gateway overhead: same request direct to the backend vs through agentgateway.

Requests alternate direct/gateway one by one (same client pod, same AZ, same
payload) so model and network drift affect both sides equally.
  chat: non-streaming, max_tokens=1 (time ~ routing + prefill, minimal decode noise)
  grpc: Embed with one short text
Reports p50/p90/p99 for each path and the difference.
"""
import os, statistics, sys, time
import grpc, httpx
import embeddings_pb2, embeddings_pb2_grpc

N = int(os.environ.get("SAMPLES", "200"))
KEY = os.environ["TEAM_SEARCH_KEY"]
CHAT = {"model": "gemma-12b", "max_tokens": 1,
        "messages": [{"role": "user", "content": "Reply with one word: ok"}]}

def pct(xs, p):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(p * len(xs)))]

def report(name, d, g):
    out = {k: round(v, 2) for k, v in {
        "direct_p50": pct(d, .5), "gw_p50": pct(g, .5), "overhead_p50": pct(g, .5) - pct(d, .5),
        "direct_p90": pct(d, .9), "gw_p90": pct(g, .9), "overhead_p90": pct(g, .9) - pct(d, .9),
        "direct_p99": pct(d, .99), "gw_p99": pct(g, .99), "overhead_p99": pct(g, .99) - pct(d, .99),
        "mean_overhead": statistics.mean(g) - statistics.mean(d)}.items()}
    print(f"RESULT {name} (ms, n={len(d)} each): {out}", flush=True)

with httpx.Client(timeout=60) as c:
    for _ in range(10):  # warm both paths and connections
        c.post("http://gemma-12b-serve-svc.agw-demo:8000/v1/chat/completions", json=CHAT)
        c.post("http://agw-demo-gw.agentgateway-system:8080/v1/chat/completions", json=CHAT, headers={"Authorization": f"Bearer {KEY}"})
    d, g = [], []
    for i in range(N):
        for path in ("direct", "gw"):
            t0 = time.perf_counter()
            if path == "direct":
                r = c.post("http://gemma-12b-serve-svc.agw-demo:8000/v1/chat/completions", json=CHAT)
            else:
                r = c.post("http://agw-demo-gw.agentgateway-system:8080/v1/chat/completions", json=CHAT, headers={"Authorization": f"Bearer {KEY}"})
            ms = (time.perf_counter() - t0) * 1000
            if r.status_code == 200:
                (d if path == "direct" else g).append(ms)
    report("chat max_tokens=1", d, g)

direct = embeddings_pb2_grpc.EmbeddingServiceStub(grpc.insecure_channel("embeddings-grpc-svc.agw-demo:9000"))
gw = embeddings_pb2_grpc.EmbeddingServiceStub(grpc.insecure_channel("agw-demo-gw.agentgateway-system:9090"))
req = embeddings_pb2.EmbedRequest(model="qwen3-embedding-0.6b", texts=["latency probe"])
md = [("authorization", f"Bearer {KEY}")]
for _ in range(20):
    direct.Embed(req); gw.Embed(req, metadata=md)
d, g = [], []
for i in range(N * 2):
    t0 = time.perf_counter(); direct.Embed(req); d.append((time.perf_counter() - t0) * 1000)
    t0 = time.perf_counter(); gw.Embed(req, metadata=md); g.append((time.perf_counter() - t0) * 1000)
report("grpc embed", d, g)
