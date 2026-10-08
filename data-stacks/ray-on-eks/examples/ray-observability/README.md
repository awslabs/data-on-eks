# Ray Observability Examples

Samples for the Ray on EKS observability stack: ADOT to Amazon Managed Prometheus and AWS X-Ray,
Amazon Managed Grafana, and the KubeRay History Server.

The architecture, setup and step-by-step verification are in the website guide:
[Ray Observability on EKS](https://awslabs.github.io/data-on-eks/docs/datastacks/processing/raydata-on-eks/observability).

| File | Purpose |
|---|---|
| `01-rayjob-history-server.yaml` | RayJob with the History Server collector sidecar (render with `envsubst`) |
| `02-otlp-trace-test.yaml` | Sends test traces through the ADOT collector to X-Ray |
| `dashboards/ray-*-dashboard.json` | Ray 2.56 Grafana dashboards (Default, Data, Serve, Serve LLM, Data LLM, Train) |
| `dashboards/nvidia-dcgm-exporter-dashboard.json` | GPU dashboard from [NVIDIA dcgm-exporter](https://github.com/NVIDIA/dcgm-exporter) (Apache-2.0) |
