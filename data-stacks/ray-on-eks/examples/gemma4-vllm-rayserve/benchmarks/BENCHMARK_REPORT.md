# Gemma 4 12B RayServe benchmark report

## Executive recommendation

- Choose **H100 TP=4** when user-facing latency or maximum throughput is the
  priority. It was the clear performance leader at every tested concurrency.
  On a p5.48xlarge it uses four of eight H100s; the other four can host another
  isolated TP=4 model or multiple smaller replicas, improving instance-level
  utilization. Validate aggregate host and network contention before production.
- Choose **H100 BASE TP=1** when one H100 is sufficient and prompt prefill/TTFT
  matters more than decode speed. On TP=1 H100, the OPT configuration improved
  decode but regressed cold prefill and did not improve saturated throughput.
- Choose **L40S QAT W4A16** for the strongest single-L40S result and likely the
  best cost-oriented option, subject to a task-quality acceptance test. It
  substantially outperformed both L40S BF16 configurations while using a
  smaller 9.6-GiB checkpoint.
- Do not select n-gram speculation merely because it is available. In these
  prompts it increased single-request decode speed, but its cold-prefill cost
  and concurrency overhead made the result workload-dependent.

## Test coverage and evidence

Six scenarios completed T03-T10: 48 primary test artifacts covering cold and
warm-prefix latency, fixed 512-token decode, one-token prefill, and concurrency
1/4/8/16. All accepted artifacts contain all six supplied prompt groups, the
expected request count, and zero request/transport errors.

The values below are averages of the six prompt-level medians. They are useful
for configuration comparison; the raw per-prompt medians and percentiles remain
authoritative for sizing a specific prompt distribution.

## Single-request comparison

| Scenario | Cold TTFT (ms) | Cold E2E (s) | Fixed decode (tok/s) | Prefill (tok/s) |
|---|---:|---:|---:|---:|
| L40S BASE BF16 | 3,553 | 22.86 | 26.48 | 5,597 |
| L40S OPT BF16 + FP8 KV + n-gram | 2,984 | 14.92 | 44.85 | 6,265 |
| L40S QAT W4A16 + FP8 KV | 2,871 | 11.15 | 61.14 | 6,474 |
| H100 BASE TP=1 | 896 | 7.23 | 80.57 | 20,509 |
| H100 OPT TP=1 + FP8 KV + n-gram | 1,815 | 7.65 | 93.33 | 12,397 |
| H100 BASE TP=4 | 382 | 3.82 | 148.28 | 46,623 |

Key findings:

- H100 TP=4 versus H100 BASE TP=1 reduced average cold TTFT by about **57%**
  and E2E latency by **47%**, while increasing fixed decode by **84%** and
  prefill throughput by **127%**.
- L40S QAT versus L40S BASE reduced cold E2E by about **51%** and increased
  fixed decode throughput by about **131%**.
- H100 OPT TP=1 increased fixed decode by about **16%** over H100 BASE, but
  cold TTFT approximately doubled and prefill throughput fell about **40%**.
  The five-token n-gram setup therefore favors decode-heavy requests with a
  sufficiently high speculation acceptance rate, not these long cold prompts.

## Concurrency comparison

Average aggregate output throughput across the six prompt groups:

| Scenario | C1 tok/s | C4 tok/s | C8 tok/s | C16 tok/s |
|---|---:|---:|---:|---:|
| L40S BASE BF16 | 22.8 | 66.3 | 102.2 | 147.3 |
| L40S OPT | 37.0 | 104.5 | 159.6 | 227.2 |
| L40S QAT W4A16 | 47.9 | 127.4 | 185.8 | 252.4 |
| H100 BASE TP=1 | 71.4 | 217.4 | 344.2 | 511.5 |
| H100 OPT TP=1 | 78.2 | 206.0 | 335.1 | 507.5 |
| H100 BASE TP=4 | 135.5 | 438.2 | 709.2 | 1,067.2 |

At concurrency 16, H100 TP=4 delivered about **2.09x** H100 BASE TP=1 and
**4.23x** L40S QAT output throughput. H100 OPT did not beat H100 BASE at C4,
C8, or C16, so speculation should not be enabled by default for a saturated
multi-request service without workload-specific validation.

## Prefix caching

Warm-prefix TTFT fell to roughly 98-139 ms across scenarios. Prefix caching is
therefore strongly recommended when requests reuse a stable long prefix. The
harness primed each prompt separately so related prompt pairs did not silently
prewarm one another.

## Quality and interpretation limits

- T03/T04 capped generation at 512 tokens. Most structured responses reached
  `finish_reason=length` before producing complete JSON. These runs are valid
  performance comparisons but are not proof of natural-completion quality.
- W4A16 can change answer quality. The QAT model passed serving and transport
  validation, but customer acceptance should compare extracted facts,
  omissions, schema validity, and hallucinations against BF16 using a larger
  labeled set and natural-EOS output.
- FP8 KV cache can introduce small numerical differences. Validate it on the
  customer's quality thresholds even when throughput improves.
- TP=4 uses four H100s for less than linear single-request scaling. Its value is
  strongest when latency/SLA or aggregate capacity justifies four GPUs.
- Cost per request is not stated because the P5 Capacity Block and on-demand
  L40S prices were not normalized in these measurements. Combine the measured
  throughput with the customer's actual reservation price before making a
  cost-only decision.

## Production decision guide

| Requirement | Recommended configuration | Reason |
|---|---|---|
| Lowest latency / highest throughput | H100 TP=4 BASE | Best TTFT, E2E, prefill, decode, and C16 throughput |
| Strong performance on one H100 | H100 TP=1 BASE | Better cold prefill and saturated throughput than H100 OPT |
| Decode-heavy, low concurrency on one H100 | H100 TP=1 OPT, after acceptance check | Faster single-request decode; workload-dependent prefill penalty |
| Best tested L40S performance | L40S QAT W4A16 | Best L40S latency and throughput; quality validation required |
| Conservative L40S quality baseline | L40S BF16 BASE | No weight quantization, but materially slower |
| Repeated long system/context prefix | Enable prefix caching | Warm TTFT around 0.1 seconds in this corpus |

## Next validation

Run a dedicated natural-EOS quality suite with a larger output limit and score
BF16 versus QAT for valid JSON, required fields, fact precision/recall, and
semantic equivalence. That quality gate should be completed before choosing
L40S QAT solely from its strong performance result.
