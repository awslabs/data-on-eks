# /// script
# requires-python = ">=3.9"
# dependencies = ["kubernetes==29.0.0"]
# ///
"""Sets tpcds-static replicas to 0 when the run has ended: no new app for QUIET_S and every app
of the run is in a final state. DEADLINE scales down anyway, so a stuck app cannot keep the nodes.

Usage: uv run load-test-scale-down.py <start time, ISO 8601> <deadline, ISO 8601>
"""
import sys
import time
from datetime import datetime, timedelta, timezone

from k8s_api import get, merge_patch

START = datetime.fromisoformat(sys.argv[1])
DEADLINE = datetime.fromisoformat(sys.argv[2])
QUIET_S = 180
FINAL = {"COMPLETED", "FAILED", "SUBMISSION_FAILED"}


def scale_to_zero():
    return merge_patch("/apis/karpenter.sh/v1/nodepools/tpcds-static", {"spec": {"replicas": 0}})["spec"]["replicas"]


while True:
    now = datetime.now(timezone.utc)
    reason = None
    try:
        apps = [a for a in get("/apis/sparkoperator.k8s.io/v1beta2/namespaces/spark-team-a/sparkapplications")["items"]
                if datetime.strptime(a["metadata"]["creationTimestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc) >= START]
        if apps:
            last = max(datetime.strptime(a["metadata"]["creationTimestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc) for a in apps)
            open_apps = [a for a in apps if a.get("status", {}).get("applicationState", {}).get("state") not in FINAL]
            if now - last > timedelta(seconds=QUIET_S) and not open_apps:
                reason = f"run ended: {len(apps)} apps final, last created {last:%H:%M:%S}"
        if now >= DEADLINE:
            reason = f"deadline {DEADLINE:%H:%M}"
        if reason:
            print(f"{now:%H:%M:%S} {reason}; replicas -> {scale_to_zero()}", flush=True)
            break
    except Exception as e:
        print(f"{now:%H:%M:%S} error {e!r}", flush=True)
    time.sleep(30)
