#!/usr/bin/env python3
"""Render a benchmark RayService scenario using only the Python stdlib."""

import argparse
import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("scenario", help="scenario ID, for example DEP-L40-BASE")
    parser.add_argument("--template", default=str(ROOT / "03-rayservice-gemma4-12b.yaml"))
    args = parser.parse_args()

    scenario_id = args.scenario.upper()
    config_path = ROOT / "scenarios" / f"{scenario_id.lower()}.json"
    if not config_path.is_file():
        raise SystemExit(f"unknown scenario {scenario_id}: {config_path} not found")

    config = json.loads(config_path.read_text(encoding="utf-8"))
    if config["scenario_id"] != scenario_id:
        raise SystemExit(f"scenario_id mismatch in {config_path}")
    if len(config.get("instance_types", [])) != 1:
        raise SystemExit(
            f"{scenario_id} must select exactly one EC2 instance type; "
            f"got {config.get('instance_types')!r}"
        )

    required_env = ("S3_BUCKET", "AWS_REGION", "ECR_REGISTRY", "RAY_LLM_TAG")
    missing = [name for name in required_env if not os.environ.get(name)]
    if missing:
        raise SystemExit("missing environment: " + ", ".join(missing))

    extra = []
    for key, value in config.get("engine_kwargs_extra", {}).items():
        if isinstance(value, bool):
            rendered = str(value).lower()
        elif isinstance(value, (dict, list)):
            rendered = json.dumps(value, separators=(",", ":"))
        else:
            rendered = str(value)
        extra.append(f"                {key}: {rendered}")

    replacements = {
        "$S3_BUCKET": os.environ["S3_BUCKET"],
        "$AWS_REGION": os.environ["AWS_REGION"],
        "$ECR_REGISTRY": os.environ["ECR_REGISTRY"],
        "$RAY_LLM_TAG": os.environ["RAY_LLM_TAG"],
        "$SCENARIO_ID": scenario_id.lower(),
        "$SERVICE_NAME": config["service_name"],
        "$MODEL_DIR": config["model_dir"],
        "$MODEL_ID": config["model_id"],
        "$ACCELERATOR_TYPE": config["accelerator_type"],
        "$GPU_COUNT": str(config["gpu_count"]),
        "$ASYNC_SCHEDULING": str(config["async_scheduling"]).lower(),
        "$WORKER_CPU": str(config["worker_cpu"]),
        "$WORKER_MEMORY_REQUEST": config["worker_memory_request"],
        "$WORKER_MEMORY_LIMIT": config["worker_memory_limit"],
        "$ENGINE_KWARGS_EXTRA": "\n".join(extra),
        "$INSTANCE_TYPE": config["instance_types"][0],
        "$NODEPOOL_NAME": config.get("nodepool_name", "gpu"),
        "$CAPACITY_TYPE": config.get("capacity_type", "on-demand"),
    }

    rendered = Path(args.template).read_text(encoding="utf-8")
    for placeholder, value in replacements.items():
        rendered = rendered.replace(placeholder, value)

    unresolved = sorted({word for word in rendered.split() if word.startswith("$")})
    if unresolved:
        raise SystemExit("unresolved placeholders: " + ", ".join(unresolved))
    print(rendered, end="")


if __name__ == "__main__":
    main()
