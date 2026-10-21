"""Generate the agw-demo tenant dashboard (Grafana 12 JSON).

One dashboard, one row per customer requirement, filtered by a `team`
dropdown (All = platform view, one team = that tenant's view).

All chargeback numbers come from metrics agentgateway already emits
(team label added by the agw-demo-telemetry policy), plus one counter from
the custom gRPC embeddings service. No extra add-on.

  python3 observability/build_dashboard.py   # writes demo/dashboards/*.json
"""
import json
import os

DS = {"type": "prometheus", "uid": "${datasource}"}
GW = 'gateway="agentgateway-system/agw-demo-gw"'
TEAM = 'team=~"$team"'
# gRPC embedding tokens are counted by the service (gateway can't read gRPC
# trailers); priced with the same internal rate as HTTP embeddings.
GRPC_TOK = 'ray_embed_tokens_total{protocol="grpc", team=~"$team"}'

panels, _id, _y = [], [0], [0]


def nid():
    _id[0] += 1
    return _id[0]


def row(title):
    panels.append({"type": "row", "id": nid(), "title": title, "collapsed": False,
                   "gridPos": {"h": 1, "w": 24, "x": 0, "y": _y[0]}})
    _y[0] += 1


def t(expr, legend="", instant=False, fmt="time_series", ref=None):
    d = {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": ref or "A"}
    if instant:
        d.update({"instant": True, "range": False, "format": fmt})
    return d


def place(p, w, h, x):
    p["gridPos"] = {"h": h, "w": w, "x": x, "y": _y[0]}
    panels.append(p)


def stat(title, expr, unit, x, w=6, h=4, desc="", color="blue", decimals=None):
    p = {"type": "stat", "id": nid(), "title": title, "description": desc, "datasource": DS,
         "targets": [t(expr, instant=True)],
         "fieldConfig": {"defaults": {"unit": unit, "color": {"mode": "fixed", "fixedColor": color},
                                      **({"decimals": decimals} if decimals is not None else {})},
                         "overrides": []},
         "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background",
                     "graphMode": "none", "textMode": "value"}}
    place(p, w, h, x)


def ts(title, targets, unit, x, w=12, h=8, desc="", stack=False, extra=None):
    p = {"type": "timeseries", "id": nid(), "title": title, "description": desc, "datasource": DS,
         "targets": [t(e, l, ref=chr(65 + i)) for i, (e, l) in enumerate(targets)],
         "fieldConfig": {"defaults": {"unit": unit, "custom": {
             "lineWidth": 2, "fillOpacity": 15 if stack else 5,
             "stacking": {"mode": "normal" if stack else "none"}}}, "overrides": []},
         "options": {"legend": {"displayMode": "table", "placement": "right",
                                "calcs": ["lastNotNull", "max"]},
                     "tooltip": {"mode": "multi", "sort": "desc"}}}
    if extra:
        p.update(extra)
    place(p, w, h, x)


# ---------------------------------------------------------------- variables
templating = {"list": [
    {"name": "datasource", "type": "datasource", "query": "prometheus", "label": "Data source",
     "current": {"text": "Prometheus", "value": "prometheus"}},
    {"name": "team", "label": "Team (tenant)", "type": "query", "datasource": DS,
     "query": {"query": f'label_values(agentgateway_requests_total{{{GW}, team!="unknown"}}, team)',
               "refId": "team"},
     "refresh": 2, "includeAll": True, "multi": True, "allValue": ".+",
     "current": {"text": ["All"], "value": ["$__all"]}, "sort": 1},
    {"name": "embed_rate", "label": "gRPC embed $ / 1M tokens", "type": "constant",
     "query": "0.01", "hide": 2,
     "description": "Internal rate for gRPC embedding tokens (same as the catalog's qwen3-embedding-0.6b input rate)."},
]}

# ------------------------------------------------------- 1. chargeback
row("1 · Usage metering & team chargeback  (totals for the selected time range)")
cost_llm = f'sum(increase(agentgateway_gen_ai_client_cost_usd_total{{{GW}, {TEAM}}}[$__range]))'
cost_grpc = f'sum(increase({GRPC_TOK}[$__range])) * $embed_rate / 1e6'
stat("Total cost (USD)", f"({cost_llm} or vector(0)) + ({cost_grpc} or vector(0))", "currencyUSD", 0,
     desc="LLM cost priced by agentgateway's model catalog + gRPC embedding tokens x internal rate.",
     color="green", decimals=4)
stat("Requests", f'sum(increase(agentgateway_requests_total{{{GW}, {TEAM}}}[$__range]))', "short", 6,
     decimals=0)
stat("Tokens (LLM in + out, HTTP embeddings)",
     f'sum(increase(agentgateway_gen_ai_client_token_usage_sum{{{GW}, {TEAM}}}[$__range]))', "short", 12,
     decimals=0)
stat("gRPC embedding tokens", f"sum(increase({GRPC_TOK}[$__range]))", "short", 18, decimals=0,
     desc="Counted by the embeddings service from the gateway-injected x-team-id header.")
_y[0] += 4

# Per-team chargeback table: one instant query per column, joined on team.
cols = [
    ("Requests", f'sum by (team) (increase(agentgateway_requests_total{{{GW}, {TEAM}}}[$__range]))', "short"),
    ("Input tokens", f'sum by (team) (increase(agentgateway_gen_ai_client_token_usage_sum{{{GW}, {TEAM}, gen_ai_token_type="input"}}[$__range]))', "short"),
    ("Output tokens", f'sum by (team) (increase(agentgateway_gen_ai_client_token_usage_sum{{{GW}, {TEAM}, gen_ai_token_type="output"}}[$__range]))', "short"),
    ("gRPC embed tokens", f"sum by (team) (increase({GRPC_TOK}[$__range]))", "short"),
    ("LLM cost $", f'sum by (team) (increase(agentgateway_gen_ai_client_cost_usd_total{{{GW}, {TEAM}}}[$__range]))', "currencyUSD"),
    ("gRPC embed cost $", f"sum by (team) (increase({GRPC_TOK}[$__range])) * $embed_rate / 1e6", "currencyUSD"),
    ("Total cost $", f'(sum by (team) (increase(agentgateway_gen_ai_client_cost_usd_total{{{GW}, {TEAM}}}[$__range])) or sum by (team) (increase({GRPC_TOK}[$__range])) * 0) + (sum by (team) (increase({GRPC_TOK}[$__range])) * $embed_rate / 1e6 or sum by (team) (increase(agentgateway_gen_ai_client_cost_usd_total{{{GW}, {TEAM}}}[$__range])) * 0)', "currencyUSD"),
    ("Rate-limited (429)", f'sum by (team) (increase(agentgateway_requests_total{{{GW}, {TEAM}, status="429"}}[$__range]))', "short"),
    ("Errors (5xx)", f'sum by (team) (increase(agentgateway_requests_total{{{GW}, {TEAM}, status=~"5.."}}[$__range]))', "short"),
]
overrides, rename = [], {"team": "Team"}
for i, (name, _, unit) in enumerate(cols):
    ref = chr(65 + i)
    rename[f"Value #{ref}"] = name
    overrides.append({"matcher": {"id": "byName", "options": name},
                      "properties": [{"id": "unit", "value": unit},
                                     {"id": "decimals", "value": 4 if unit == "currencyUSD" else 0}]})
overrides.append({"matcher": {"id": "byName", "options": "Total cost $"},
                  "properties": [{"id": "custom.cellOptions", "value": {"type": "color-background"}},
                                 {"id": "color", "value": {"mode": "fixed", "fixedColor": "green"}}]})
overrides.append({"matcher": {"id": "byName", "options": "Rate-limited (429)"},
                  "properties": [{"id": "custom.cellOptions", "value": {"type": "color-text"}},
                                 {"id": "color", "value": {"mode": "fixed", "fixedColor": "orange"}}]})
place({"type": "table", "id": nid(), "title": "Chargeback by team", "datasource": DS,
       "description": "Export: panel menu > Inspect > Data > Download CSV. Totals for the dashboard time range.",
       "targets": [t(e, instant=True, fmt="table", ref=chr(65 + i)) for i, (_, e, _) in enumerate(cols)],
       "transformations": [
           {"id": "merge", "options": {}},
           {"id": "organize", "options": {"excludeByName": {"Time": True}, "renameByName": rename,
                                          "indexByName": {"team": 0}}},
           {"id": "sortBy", "options": {"sort": [{"field": "Total cost $", "desc": True}]}}],
       "fieldConfig": {"defaults": {"custom": {"align": "auto"}}, "overrides": overrides},
       "options": {"showHeader": True, "footer": {"show": True, "reducer": ["sum"],
                                                  "fields": [c[0] for c in cols]}}}, 16, 9, 0)
place({"type": "piechart", "id": nid(), "title": "Cost share by team", "datasource": DS,
       "targets": [t(f'sum by (team) (increase(agentgateway_gen_ai_client_cost_usd_total{{{GW}, {TEAM}}}[$__range])) + on(team) group_left() (sum by (team) (increase({GRPC_TOK}[$__range])) * $embed_rate / 1e6 or sum by (team) (increase(agentgateway_gen_ai_client_cost_usd_total{{{GW}, {TEAM}}}[$__range])) * 0)', "{{team}}", instant=True)],
       "fieldConfig": {"defaults": {"unit": "currencyUSD", "decimals": 4}, "overrides": []},
       "options": {"pieType": "donut", "legend": {"displayMode": "table", "placement": "right",
                                                  "values": ["value", "percent"]},
                   "reduceOptions": {"calcs": ["lastNotNull"]}}}, 8, 9, 16)
_y[0] += 9
ts("Spend rate by team ($ / hour)",
   [(f'sum by (team) (rate(agentgateway_gen_ai_client_cost_usd_total{{{GW}, {TEAM}}}[5m])) * 3600', "{{team}} LLM"),
    (f'sum by (team) (rate({GRPC_TOK}[5m])) * $embed_rate / 1e6 * 3600', "{{team}} gRPC embed")],
   "currencyUSD", 0, stack=True)
ts("Tokens / second by team and type",
   [(f'sum by (team, gen_ai_token_type) (rate(agentgateway_gen_ai_client_token_usage_sum{{{GW}, {TEAM}}}[5m]))', "{{team}} {{gen_ai_token_type}}"),
    (f"sum by (team) (rate({GRPC_TOK}[5m]))", "{{team}} grpc-embed")],
   "short", 12, stack=True)
_y[0] += 8

# ------------------------------------------------ 2. rate limits / overload
row("2 · Rate limiting & overload protection")
ts("Requests / second by team and status",
   [(f'sum by (team, status) (rate(agentgateway_requests_total{{{GW}, {TEAM}}}[1m]))', "{{team}} {{status}}")],
   "reqps", 0, w=8, desc="200 = served, 429 = per-team limit, 401 = bad/missing key, 503 = backend queue full.")
ts("Rate-limited (429) / second by team",
   [(f'sum by (team) (rate(agentgateway_requests_total{{{GW}, {TEAM}, status="429"}}[1m]))', "{{team}}")],
   "reqps", 8, w=8, desc="Per-team token and request buckets (per proxy pod).")
ts("Backend overload: 503s and Ray queue depth",
   [(f'sum by (team) (rate(agentgateway_requests_total{{{GW}, {TEAM}, status=~"5.."}}[1m]))', "{{team}} 5xx/s"),
    ('sum by (deployment) (ray_serve_deployment_queued_queries)', "queued @ {{deployment}}"),
    ('sum by (deployment) (ray_serve_num_ongoing_requests_at_replicas)', "ongoing @ {{deployment}}")],
   "short", 16, w=8,
   desc="Ray Serve caps ongoing (64/replica) and queued (16/replica) requests; beyond that it returns 503 immediately.")
_y[0] += 8

# --------------------------------------------------------- 3. latency
row("3 · Latency & availability")
ttft = 'agentgateway_gen_ai_server_time_to_first_token_bucket{%s, %s}' % (GW, TEAM)
tpot = 'agentgateway_gen_ai_server_time_per_output_token_bucket{%s, %s}' % (GW, TEAM)
ts("Time to first token (streaming) by model",
   [(f'histogram_quantile({q}, sum by (le, gen_ai_request_model) (rate({ttft}[5m])))', f"p{int(q*100)} {{{{gen_ai_request_model}}}}")
    for q in (0.5, 0.95, 0.99)], "s", 0, w=8)
ts("Time per output token by model",
   [(f'histogram_quantile({q}, sum by (le, gen_ai_request_model) (rate({tpot}[5m])))', f"p{int(q*100)} {{{{gen_ai_request_model}}}}")
    for q in (0.5, 0.95)], "s", 8, w=8)
ts("End-to-end request latency at the gateway (p99) by listener",
   [(f'histogram_quantile(0.99, sum by (le, listener) (rate(agentgateway_request_duration_seconds_bucket{{{GW}, {TEAM}, status="200"}}[5m])))', "p99 {{listener}}"),
    (f'histogram_quantile(0.50, sum by (le, listener) (rate(agentgateway_request_duration_seconds_bucket{{{GW}, {TEAM}, status="200"}}[5m])))', "p50 {{listener}}")],
   "s", 16, w=8, desc="http = LLM + HTTP embeddings, grpc = custom gRPC embeddings.")
_y[0] += 8
stat("Gateway proxies up", f'count(up{{job="agentgateway-system/agentgateway-proxy", namespace="agentgateway-system"}} == 1)',
     "short", 0, w=4, desc="3 replicas, one per AZ, PDB minAvailable 2.", color="green")
stat("Success ratio (non-5xx)",
     f'sum(rate(agentgateway_requests_total{{{GW}, {TEAM}, status!~"5.."}}[$__rate_interval])) / sum(rate(agentgateway_requests_total{{{GW}, {TEAM}}}[$__rate_interval]))',
     "percentunit", 4, w=4, color="green", decimals=3)
stat("Healthy Ray Serve replicas", 'sum(ray_serve_deployment_replica_healthy)', "short", 8, w=4,
     desc="gemma-12b: 2 (one per AZ) + embeddings: 2 (one per AZ).", color="green")
# Ray exports this gauge intermittently, so smooth over 2m to avoid gaps.
ts("vLLM KV-cache usage per Gemma replica",
   [('max by (pod) (max_over_time(ray_vllm_kv_cache_usage_perc[2m]))', "{{pod}}")], "percentunit", 12, w=12, h=4)
_y[0] += 4

# ---------------------------------------------------------- 4. telemetry
row("4 · Telemetry health (out of the box)")
ts("Cost catalog lookups by status",
   [(f'sum by (status, gen_ai_request_model) (rate(agentgateway_cost_catalog_lookups_total{{{GW}}}[5m]))', "{{status}} {{gen_ai_request_model}}")],
   "reqps", 0, w=12, h=6, desc="Exact = priced from our catalog. Missing/Unpriced = a model without a price (fix the catalog).")
ts("Requests / second by listener and model route",
   [(f'sum by (listener, route) (rate(agentgateway_requests_total{{{GW}}}[1m]))', "{{listener}} {{route}}")],
   "reqps", 12, w=12, h=6)
_y[0] += 6

dashboard = {
    "uid": "agw-demo-tenants", "title": "agw-demo · Tenant chargeback & SLOs",
    "description": "agentgateway + Ray Serve: per-team usage, cost, limits, latency, availability.",
    "tags": ["agw-demo", "agentgateway", "chargeback"], "timezone": "browser",
    "schemaVersion": 41, "version": 1, "editable": True, "refresh": "30s",
    "time": {"from": "now-1h", "to": "now"}, "templating": templating,
    "annotations": {"list": []}, "panels": panels,
}
out = os.path.join(os.path.dirname(__file__), "..", "demo", "dashboards", "agw-demo-tenant-chargeback.json")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    json.dump(dashboard, f, indent=2)
print("wrote", os.path.normpath(out), "panels:", len(panels))
