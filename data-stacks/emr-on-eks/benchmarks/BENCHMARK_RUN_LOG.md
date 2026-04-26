# EMR on EKS PCP Benchmark Run Log

Use this file to record each benchmark run so results can be repeated and compared as submission rate increases.

## Endpoint Note

- The benchmark scripts are hardcoded to the EMR on EKS gamma endpoint only.
- All future benchmark runs must use the gamma endpoint.

## Capture For Every Run

- `Run ID`
- `Date`
- `Goal`
- `EMR endpoint`
- `Locust command`
- `Job shape`
- `Start time (UTC)`
- `End time (UTC)`
- `Duration`
- `Active jobs at start`
- `Active jobs at end`
- `API submission count`
- `Locust `start_job_run` rate`
- `Observed Jobs/min` in Grafana
- `Peak Pods Scheduled/min`
- `Peak Running Pods`
- `Peak Node Count`
- `PCP notes`
- `Outcome`
- `Follow-up change for next run`

## Template

Copy this block for each new run.

```md
## Run XXX

- `Run ID`:
- `Date`:
- `Goal`:
- `EMR endpoint`:
- `Start time (UTC)`:
- `End time (UTC)`:
- `Duration`:
- `Active jobs at start`:
- `Active jobs at end`:
- `Locust command`:
- `Job shape`:
- `API submission count`:
- `Locust start_job_run rate`:
- `Locust start_job_run latency`:
- `Observed Jobs/min` in Grafana:
- `Peak Pods Scheduled/min`:
- `Peak Running Pods`:
- `Peak Node Count`:
- `PCP notes`:
- `Outcome`:
- `Follow-up change for next run`:
```
