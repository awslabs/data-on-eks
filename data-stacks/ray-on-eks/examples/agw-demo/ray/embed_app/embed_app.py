"""Custom embeddings service on Ray Serve: simulates a customer's gRPC API.

One deployment serves two protocols from the same GPU replica:
  - gRPC  embeddings.v1.EmbeddingService/Embed      (Serve gRPC proxy, :9000)
  - HTTP  POST /v1/embeddings  (OpenAI-compatible)  (Serve HTTP proxy, :8000)
          GET  /v1/models

Model: Qwen3-Embedding-0.6B with transformers (last-token pooling, L2 norm),
dynamic GPU batching with @serve.batch.

Metering:
  - prompt_tokens in the response body (gRPC and HTTP)
  - gRPC trailing metadata  x-usage-prompt-tokens  (Ray Serve can set trailing
    metadata only, not initial metadata)
  - Ray metric embed_tokens_total{team,protocol,model}; team comes from the
    x-team-id header that the gateway sets from the caller's API key
"""
import logging
import os
import time
from typing import List

import torch
import torch.nn.functional as F
from pyarrow import fs as pafs
from ray import serve
from ray.serve.grpc_util import RayServegRPCContext
from ray.util.metrics import Counter, Histogram
from starlette.requests import Request
from starlette.responses import JSONResponse
from transformers import AutoModel, AutoTokenizer

import embeddings_pb2

logger = logging.getLogger("ray.serve")

MODEL_ID = os.environ.get("EMBED_MODEL_ID", "qwen3-embedding-0.6b")
MODEL_SOURCE = os.environ["EMBED_MODEL_SOURCE"]  # s3://bucket/models/qwen3-embedding-0.6b
MAX_TEXTS = int(os.environ.get("EMBED_MAX_TEXTS", "64"))
MAX_TOKENS_PER_TEXT = int(os.environ.get("EMBED_MAX_TOKENS_PER_TEXT", "8192"))
LOCAL_DIR = "/tmp/models/" + MODEL_ID


def download_from_s3(source: str, dest: str) -> float:
    """Copy the model prefix to local disk. pyarrow's S3 client supports EKS
    Pod Identity; the boto3 in this image is too old to."""
    t0 = time.time()
    if os.path.exists(os.path.join(dest, "config.json")):
        return 0.0
    os.makedirs(dest, exist_ok=True)
    region = os.environ.get("AWS_REGION", "us-west-2")
    s3 = pafs.S3FileSystem(region=region)
    pafs.copy_files(source.removeprefix("s3://"), dest, source_filesystem=s3,
                    destination_filesystem=pafs.LocalFileSystem(), use_threads=True)
    return time.time() - t0


@serve.deployment
class Embedder:
    def __init__(self):
        dl_s = download_from_s3(MODEL_SOURCE, LOCAL_DIR)
        t0 = time.time()
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        # Left padding so the last position is the real last token for pooling.
        self.tokenizer = AutoTokenizer.from_pretrained(LOCAL_DIR, padding_side="left")
        self.model = AutoModel.from_pretrained(LOCAL_DIR, torch_dtype=torch.float16).to(self.device).eval()
        logger.info("MODEL_LOAD model=%s s3_download_s=%.1f load_s=%.1f device=%s",
                    MODEL_ID, dl_s, time.time() - t0, self.device)

        self.tokens_total = Counter(
            "embed_tokens_total", description="Embedding input tokens by team",
            tag_keys=("team", "protocol", "model"))
        self.requests_total = Counter(
            "embed_requests_total", description="Embedding requests by team",
            tag_keys=("team", "protocol", "model"))
        self.latency_ms = Histogram(
            "embed_latency_ms", description="Embedding latency inside the replica",
            boundaries=[2, 5, 10, 20, 50, 100, 200, 500, 1000], tag_keys=("protocol",))

    # ---- batched GPU path ---------------------------------------------------
    @serve.batch(max_batch_size=16, batch_wait_timeout_s=0.005)
    async def _embed_batch(self, requests: List[List[str]]):
        flat = [t for texts in requests for t in texts]
        enc = self.tokenizer(flat, padding=True, truncation=True,
                             max_length=MAX_TOKENS_PER_TEXT, return_tensors="pt").to(self.device)
        with torch.inference_mode():
            out = self.model(**enc).last_hidden_state
        vecs = F.normalize(out[:, -1].float(), p=2, dim=1).cpu().tolist()
        counts = enc["attention_mask"].sum(dim=1).tolist()
        results, i = [], 0
        for texts in requests:
            n = len(texts)
            results.append((vecs[i:i + n], int(sum(counts[i:i + n]))))
            i += n
        return results

    def _meter(self, team: str, protocol: str, tokens: int, started: float):
        tags = {"team": team or "unknown", "protocol": protocol, "model": MODEL_ID}
        self.tokens_total.inc(tokens, tags=tags)
        self.requests_total.inc(1, tags=tags)
        self.latency_ms.observe((time.time() - started) * 1000, tags={"protocol": protocol})

    # ---- gRPC: embeddings.v1.EmbeddingService/Embed ------------------------
    async def Embed(self, request: embeddings_pb2.EmbedRequest,
                    grpc_context: RayServegRPCContext) -> embeddings_pb2.EmbedResponse:
        import grpc
        started = time.time()
        texts = list(request.texts)
        if not texts or len(texts) > MAX_TEXTS:
            grpc_context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            grpc_context.set_details(f"texts must contain 1..{MAX_TEXTS} items")
            return embeddings_pb2.EmbedResponse()
        md = dict(grpc_context.invocation_metadata())
        vecs, tokens = await self._embed_batch(texts)
        grpc_context.set_trailing_metadata([("x-usage-prompt-tokens", str(tokens))])
        self._meter(md.get("x-team-id", ""), "grpc", tokens, started)
        return embeddings_pb2.EmbedResponse(
            embeddings=[embeddings_pb2.Embedding(values=v) for v in vecs],
            prompt_tokens=tokens, model=MODEL_ID)

    # ---- HTTP: OpenAI-compatible -------------------------------------------
    async def __call__(self, request: Request):
        if request.method == "GET" and request.url.path.rstrip("/").endswith("/v1/models"):
            return JSONResponse({"object": "list", "data": [
                {"id": MODEL_ID, "object": "model", "owned_by": "agw-demo"}]})
        if request.method != "POST" or not request.url.path.rstrip("/").endswith("/v1/embeddings"):
            return JSONResponse({"error": {"message": "not found"}}, status_code=404)
        started = time.time()
        body = await request.json()
        inp = body.get("input")
        texts = [inp] if isinstance(inp, str) else list(inp or [])
        if not texts or len(texts) > MAX_TEXTS or not all(isinstance(t, str) for t in texts):
            return JSONResponse({"error": {"message": f"input must be 1..{MAX_TEXTS} strings"}},
                                status_code=400)
        vecs, tokens = await self._embed_batch(texts)
        self._meter(request.headers.get("x-team-id", ""), "http", tokens, started)
        return JSONResponse(
            {"object": "list", "model": MODEL_ID,
             "data": [{"object": "embedding", "index": i, "embedding": v} for i, v in enumerate(vecs)],
             "usage": {"prompt_tokens": tokens, "total_tokens": tokens}},
            headers={"x-usage-prompt-tokens": str(tokens)})


app = Embedder.bind()
