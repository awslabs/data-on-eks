"""
Agentic Analytics Agent — LangGraph + Amazon Bedrock + official StarRocks MCP server.

State machine: Decompose → Execute → Analyze → Summarize

  Decompose  — Claude writes 4-6 targeted SQL investigation queries
  Execute    — fans out concurrent read_query calls to the official StarRocks MCP server
  Analyze    — Claude identifies the outlier dimension and value from results
  Summarize  — Claude synthesizes a concise markdown root-cause report

MCP server: github.com/StarRocks/mcp-server-starrocks (official, Streamable-HTTP transport)
LLM:        Amazon Bedrock — Claude Sonnet 4.6 via IRSA (no API key needed)

Endpoints
---------
POST /investigate       → {report, analysis, trace}
GET  /health            → liveness probe
GET  /docs              → Swagger UI
"""

import asyncio
import json
import logging
import os
import time
from typing import TypedDict

import boto3
import httpx
from fastapi import FastAPI, HTTPException
from fastmcp import Client as MCPClient
from langgraph.graph import END, StateGraph
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

app = FastAPI(
    title="Agentic Analytics Agent",
    description=(
        "LangGraph agent that investigates ad-metric anomalies by writing SQL "
        "against StarRocks via the official StarRocks MCP server."
    ),
    version="2.0.0",
)

AWS_REGION  = os.environ.get("AWS_REGION", "us-east-1")
MODEL_ID    = os.environ.get("BEDROCK_MODEL_ID", "us.anthropic.claude-sonnet-4-6")
MCP_URL     = os.environ.get(
    "MCP_SERVER_URL",
    "http://mcp-server.agentic-analytics.svc.cluster.local:8000/mcp",
)

bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)

# Schema provided upfront so Claude can write correct StarRocks SQL
_SCHEMA = """
Database : ad_analytics
Table    : ad_events

Columns:
  event_id      BIGINT    primary key
  event_ts      DATETIME  event timestamp (UTC)
  advertiser_id INT       advertiser identifier
  creative_id   INT       ad creative identifier
  placement_id  INT       placement identifier (101-105)
  device_type   VARCHAR   'mobile' | 'desktop' | 'tablet'
  country_code  VARCHAR   ISO-3166 country code: US, GB, DE, FR, JP, CA, AU
  impressions   INT       impression count per row
  clicks        INT       click count per row

Useful patterns:
  CTR %  = ROUND(SUM(clicks) / NULLIF(SUM(impressions), 0) * 100, 4)
  Recent = event_ts >= NOW() - INTERVAL <N> MINUTE
  Rows   ≈ 1,000,000 spanning 2 hours
"""


# ──────────────────────────────────────────────────────────────────────────────
# Bedrock helper
# ──────────────────────────────────────────────────────────────────────────────

def _bedrock(messages: list[dict], system: str = "") -> tuple[str, float]:
    body: dict = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 4096,
        "messages": messages,
    }
    if system:
        body["system"] = system
    t0   = time.time()
    resp = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps(body),
        contentType="application/json",
        accept="application/json",
    )
    return json.loads(resp["body"].read())["content"][0]["text"], round(time.time() - t0, 2)


# ──────────────────────────────────────────────────────────────────────────────
# LangGraph state
# ──────────────────────────────────────────────────────────────────────────────

class InvestigationState(TypedDict):
    question:         str
    advertiser_id:    int
    plan:             list[dict]   # [{description, sql, dimension_drilled}]
    tool_results:     list[dict]   # [{description, sql, rows_csv, elapsed_ms}]
    outlier_analysis: str
    report:           str
    timing:           dict


# ──────────────────────────────────────────────────────────────────────────────
# Nodes
# ──────────────────────────────────────────────────────────────────────────────

def decompose(state: InvestigationState) -> dict:
    log.info("=== DECOMPOSE ===")
    system = f"""You are an analytics engineer investigating a CTR anomaly in StarRocks.

{_SCHEMA}

Write exactly 4–6 SQL queries to drill into the reported issue.
Each query must GROUP BY one dimension column and compute CTR %.
Include a comparison to the 60-minute prior baseline using UNION ALL.
Keep queries focused and efficient — avoid SELECT *.
Order results by ctr_pct ASC so outliers (near-zero CTR) appear first.

Return ONLY a JSON array. Each element:
  description      (string) — one sentence explaining what this query investigates
  dimension_drilled (string) — which column is the key GROUP BY
  sql              (string) — complete, valid StarRocks SQL (no placeholders)

No markdown, no explanation — raw JSON array only."""

    raw, elapsed = _bedrock(
        messages=[{
            "role": "user",
            "content": (
                f"Question: {state['question']}\n"
                f"Filter: advertiser_id = {state['advertiser_id']}"
            ),
        }],
        system=system,
    )
    # Strip markdown code fences if model wrapped the JSON
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("```", 2)[1]
        if cleaned.startswith("json"):
            cleaned = cleaned[4:]
        cleaned = cleaned.rsplit("```", 1)[0].strip()
    plan = json.loads(cleaned)
    log.info("Decompose %.1fs → %d queries planned", elapsed, len(plan))
    return {"plan": plan, "timing": {"decompose_s": elapsed}}


async def _run_query(item: dict) -> dict:
    """Call read_query on the official StarRocks MCP server via MCP Streamable-HTTP."""
    sql = item.get("sql", "")
    t0  = time.time()
    rows_csv = ""
    error    = None
    try:
        async with MCPClient(MCP_URL) as mcp:
            result = await mcp.call_tool("read_query", {"query": sql})
            # fastmcp >= 2.14 returns CallToolResult with .content list;
            # older versions returned a plain list of content items directly.
            content_list = getattr(result, "content", None) or (list(result) if result else [])
            if content_list:
                first = content_list[0]
                rows_csv = getattr(first, "text", None) or str(first)
            else:
                rows_csv = str(result)
    except Exception as exc:
        error    = str(exc)
        rows_csv = f"ERROR: {exc}"
        log.warning("Query failed for [%s]: %s", item.get("dimension_drilled"), exc)

    elapsed_ms = round((time.time() - t0) * 1000)
    log.info("read_query [%s] %dms — %d chars returned",
             item.get("dimension_drilled"), elapsed_ms, len(rows_csv))
    return {
        "description":       item.get("description", ""),
        "dimension_drilled": item.get("dimension_drilled", ""),
        "sql":               sql,
        "rows_csv":          rows_csv,
        "elapsed_ms":        elapsed_ms,
        "error":             error,
    }


async def execute(state: InvestigationState) -> dict:
    log.info("=== EXECUTE: %d concurrent MCP read_query calls ===", len(state["plan"]))
    t0      = time.time()
    results = await asyncio.gather(*[_run_query(item) for item in state["plan"]])
    elapsed = round(time.time() - t0, 2)
    log.info("Execute %.1fs — all queries done", elapsed)
    return {
        "tool_results": list(results),
        "timing": {**state.get("timing", {}), "execute_s": elapsed},
    }


def analyze(state: InvestigationState) -> dict:
    log.info("=== ANALYZE ===")
    # Pass raw CSV results — StarRocks returns CSV from the MCP server
    results_text = "\n\n".join(
        f"--- {r['dimension_drilled']}: {r['description']} ---\n{r['rows_csv'][:4000]}"
        for r in state["tool_results"]
    )
    system = """You are a senior data analyst. Identify the single dimension value
that is the root cause of the CTR drop. Be precise:
name the dimension, the exact value, current CTR %, baseline CTR %, and drop magnitude.
One paragraph, no fluff."""

    analysis, elapsed = _bedrock(
        messages=[{
            "role": "user",
            "content": (
                f"Investigation: {state['question']}\n\n"
                f"Query results:\n{results_text}\n\n"
                "Which dimension/value is the root cause?"
            ),
        }],
        system=system,
    )
    log.info("Analyze %.1fs", elapsed)
    return {
        "outlier_analysis": analysis,
        "timing": {**state.get("timing", {}), "analyze_s": elapsed},
    }


def report_node(state: InvestigationState) -> dict:
    log.info("=== REPORT ===")
    system = """Write a concise markdown root-cause report:
## Root Cause
## Evidence
## Impact
## Recommended Action
Under 300 words. Direct and actionable."""

    report, elapsed = _bedrock(
        messages=[{
            "role": "user",
            "content": (
                f"Question: {state['question']}\n"
                f"Analysis: {state['outlier_analysis']}"
            ),
        }],
        system=system,
    )
    log.info("Report %.1fs", elapsed)
    return {
        "report": report,
        "timing": {**state.get("timing", {}), "report_s": elapsed},
    }


# ──────────────────────────────────────────────────────────────────────────────
# LangGraph
# ──────────────────────────────────────────────────────────────────────────────

workflow = StateGraph(InvestigationState)
workflow.add_node("decompose",  decompose)
workflow.add_node("execute",    execute)
workflow.add_node("analyze",    analyze)
workflow.add_node("summarize",  report_node)

workflow.set_entry_point("decompose")
workflow.add_edge("decompose",  "execute")
workflow.add_edge("execute",    "analyze")
workflow.add_edge("analyze",    "summarize")
workflow.add_edge("summarize",  END)

graph = workflow.compile()


# ──────────────────────────────────────────────────────────────────────────────
# FastAPI
# ──────────────────────────────────────────────────────────────────────────────

class InvestigationRequest(BaseModel):
    question:      str = "CTR dropped for advertiser_42 in last 15 minutes — what is the root cause?"
    advertiser_id: int = 42


@app.post("/investigate", summary="Run a root-cause investigation")
async def investigate(req: InvestigationRequest):
    log.info("▶ Investigation: %s (advertiser_id=%d)", req.question, req.advertiser_id)
    t0 = time.time()
    try:
        result = await graph.ainvoke({
            "question":         req.question,
            "advertiser_id":    req.advertiser_id,
            "plan":             [],
            "tool_results":     [],
            "outlier_analysis": "",
            "report":           "",
            "timing":           {},
        })
    except Exception as exc:
        log.exception("Investigation failed")
        raise HTTPException(500, str(exc)) from exc

    timing = {**result.get("timing", {}), "total_s": round(time.time() - t0, 1)}

    return {
        "report":   result["report"],
        "analysis": result["outlier_analysis"],
        "trace": {
            "model":      MODEL_ID,
            "mcp_server": MCP_URL,
            "plan": [
                {"description": p["description"], "dimension": p.get("dimension_drilled")}
                for p in result["plan"]
            ],
            "tool_calls": [
                {
                    "dimension":   r["dimension_drilled"],
                    "description": r["description"],
                    "sql":         r["sql"],
                    "elapsed_ms":  r["elapsed_ms"],
                    "preview":     r["rows_csv"][:400] if r["rows_csv"] else "",
                }
                for r in result["tool_results"]
            ],
            "timing": timing,
        },
    }


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_ID, "mcp": MCP_URL}
