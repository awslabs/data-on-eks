---
title: Gemma 4 12B RayServe GPU benchmark
sidebar_position: 9
sidebar_label: Gemma 4 12B on RayServe
---

import '@site/src/css/gemma-benchmark.css';

<div className="gemma-benchmark-hero">
  <p className="gemma-benchmark-eyebrow">RayServe and vLLM on Amazon EKS</p>
  <h1>Gemma 4 12B GPU benchmark</h1>
  <p className="gemma-benchmark-subtitle">Six deployment configurations compared across cold and warm latency, prefill, fixed decode, and concurrency from 1 to 16.</p>
  <div className="gemma-benchmark-chips">
    <span>48 primary tests</span>
    <span>6 prompt groups</span>
    <span>0 request errors</span>
    <span>L40S and H100</span>
    <span>TP=1 and TP=4</span>
  </div>
</div>

## Summary

Gemma 4 12B was deployed with Ray Serve and vLLM on Amazon EKS. The benchmark
compared BF16 baselines, FP8 KV cache with n-gram speculative decoding, W4A16
quantization-aware-trained weights, and four-GPU tensor parallelism. Every
configuration ran against the same prompt corpus and request schedule.

The benchmark answers two practical questions: which configuration delivers the
best latency and throughput, and which lower-cost configuration is worth taking
to an application quality test.

## Recommendation

<div className="gemma-benchmark-grid">
  <article className="gemma-benchmark-card gemma-benchmark-card-performance">
    <span className="gemma-benchmark-tag">Performance leader</span>
    <h3>H100 TP=4 BASE</h3>
    <p>Use when the latency target or aggregate throughput justifies four H100 GPUs.</p>
    <div className="gemma-benchmark-metric">1,067 tok/s<small>Concurrency-16 aggregate output</small></div>
  </article>
  <article className="gemma-benchmark-card gemma-benchmark-card-balanced">
    <span className="gemma-benchmark-tag">Best single H100</span>
    <h3>H100 TP=1 BASE</h3>
    <p>Strong long-prompt prefill and saturated throughput without allocating four GPUs.</p>
    <div className="gemma-benchmark-metric">896 ms<small>Average of prompt-level median cold TTFT</small></div>
  </article>
  <article className="gemma-benchmark-card gemma-benchmark-card-value">
    <span className="gemma-benchmark-tag">L40S candidate</span>
    <h3>L40S QAT W4A16</h3>
    <p>The fastest L40S configuration. Run an application quality gate before adoption.</p>
    <div className="gemma-benchmark-metric">61 tok/s<small>Single-request fixed decode</small></div>
  </article>
</div>

## Configuration and results

**BASE** uses BF16 weights, prefix caching, and no speculative decoding.
**OPT** adds FP8 KV cache and five-token n-gram speculation. **QAT** uses
W4A16 quantization-aware-trained weights with FP8 KV cache. **TP** is the number
of GPUs serving one model replica.

Lower is better for TTFT and end-to-end latency. Higher is better for token
throughput and C16 throughput per allocated hourly cost. Latency and throughput
values in this comparison average the six prompt-level medians; the per-test
tables below pool all raw requests.

<div className="gemma-benchmark-table-shell gemma-benchmark-table-summary">
  <table aria-label="Deployment configuration comparison">
    <thead>
      <tr>
        <th scope="col">Rank and configuration</th>
        <th scope="col">GPU allocation</th>
        <th scope="col">Cold TTFT</th>
        <th scope="col">Cold E2E</th>
        <th scope="col">Decode</th>
        <th scope="col">Prefill</th>
        <th scope="col">C16 output</th>
        <th scope="col">C16 tok/s per allocated $/hr</th>
        <th scope="col">Allocated compute cost</th>
      </tr>
    </thead>
    <tbody>
      <tr className="gemma-benchmark-winner">
        <th scope="row">1 · H100 BASE TP=4</th>
        <td>4x H100</td>
        <td>382 ms</td>
        <td>3.82 s</td>
        <td>148.3 tok/s</td>
        <td>46,623 tok/s</td>
        <td>1,067 tok/s</td>
        <td>61.7</td>
        <td><strong>$17.304/hr</strong><small>4/8 of P5</small></td>
      </tr>
      <tr>
        <th scope="row">2 · H100 BASE TP=1</th>
        <td>1x H100</td>
        <td>896 ms</td>
        <td>7.23 s</td>
        <td>80.6 tok/s</td>
        <td>20,509 tok/s</td>
        <td>512 tok/s</td>
        <td><strong>118.2</strong></td>
        <td><strong>$4.326/hr</strong><small>1/8 of P5</small></td>
      </tr>
      <tr>
        <th scope="row">3 · H100 OPT TP=1</th>
        <td>1x H100</td>
        <td>1,815 ms</td>
        <td>7.65 s</td>
        <td>93.3 tok/s</td>
        <td>12,397 tok/s</td>
        <td>507 tok/s</td>
        <td>117.3</td>
        <td><strong>$4.326/hr</strong><small>1/8 of P5</small></td>
      </tr>
      <tr>
        <th scope="row">4 · L40S QAT W4A16</th>
        <td>1x L40S</td>
        <td>2,871 ms</td>
        <td>11.15 s</td>
        <td>61.1 tok/s</td>
        <td>6,474 tok/s</td>
        <td>252 tok/s</td>
        <td>112.6</td>
        <td><strong>$2.2421/hr</strong><small>Full G6E</small></td>
      </tr>
      <tr>
        <th scope="row">5 · L40S OPT</th>
        <td>1x L40S</td>
        <td>2,984 ms</td>
        <td>14.92 s</td>
        <td>44.9 tok/s</td>
        <td>6,265 tok/s</td>
        <td>227 tok/s</td>
        <td>101.3</td>
        <td><strong>$2.2421/hr</strong><small>Full G6E</small></td>
      </tr>
      <tr>
        <th scope="row">6 · L40S BASE BF16</th>
        <td>1x L40S</td>
        <td>3,553 ms</td>
        <td>22.86 s</td>
        <td>26.5 tok/s</td>
        <td>5,597 tok/s</td>
        <td>147 tok/s</td>
        <td>65.7</td>
        <td><strong>$2.2421/hr</strong><small>Full G6E</small></td>
      </tr>
    </tbody>
  </table>
</div>

<div className="gemma-benchmark-table-note">
  Cost basis: us-west-2 Linux <a href="https://aws.amazon.com/ec2/pricing/on-demand/">On-Demand pricing</a> for <code>g6e.2xlarge</code> and AWS <a href="https://aws.amazon.com/ec2/capacityblocks/pricing/">Capacity Block pricing</a> for <code>p5.48xlarge</code>. P5 allocation assumes all eight GPUs perform useful work; otherwise a deployment must absorb a larger share, or all, of the $34.608 hourly instance cost. Storage, data transfer, EKS, and observability are excluded. Revalidate rates before making a purchasing decision.
</div>

### Concurrency-16 throughput

Average aggregate output tokens per second across the six prompt groups:

<div className="gemma-benchmark-bars" aria-label="Concurrency-16 output throughput comparison">
  <div className="gemma-benchmark-bar-row"><span>H100 TP=4 BASE</span><div className="gemma-benchmark-track"><div className="gemma-benchmark-fill gemma-benchmark-fill-100"></div></div><strong>1,067</strong></div>
  <div className="gemma-benchmark-bar-row"><span>H100 TP=1 BASE</span><div className="gemma-benchmark-track"><div className="gemma-benchmark-fill gemma-benchmark-fill-48"></div></div><strong>512</strong></div>
  <div className="gemma-benchmark-bar-row"><span>H100 TP=1 OPT</span><div className="gemma-benchmark-track"><div className="gemma-benchmark-fill gemma-benchmark-fill-47"></div></div><strong>507</strong></div>
  <div className="gemma-benchmark-bar-row"><span>L40S QAT W4A16</span><div className="gemma-benchmark-track"><div className="gemma-benchmark-fill gemma-benchmark-fill-24"></div></div><strong>252</strong></div>
  <div className="gemma-benchmark-bar-row"><span>L40S OPT</span><div className="gemma-benchmark-track"><div className="gemma-benchmark-fill gemma-benchmark-fill-21"></div></div><strong>227</strong></div>
  <div className="gemma-benchmark-bar-row"><span>L40S BASE BF16</span><div className="gemma-benchmark-track"><div className="gemma-benchmark-fill gemma-benchmark-fill-14"></div></div><strong>147</strong></div>
</div>

At concurrency 16, H100 TP=4 delivered 2.09 times the output throughput of
H100 BASE TP=1 and 4.23 times that of L40S QAT. H100 OPT did not beat H100 BASE
at concurrency 4, 8, or 16, so speculation is not a default choice for a
saturated service.

## How to read the metrics

<div className="gemma-benchmark-grid gemma-benchmark-grid-metrics">
  <article className="gemma-benchmark-card"><h3>TTFT</h3><p>Time from request submission to the first response token. It captures prompt processing and queueing. Lower is better.</p></article>
  <article className="gemma-benchmark-card"><h3>End-to-end latency</h3><p>Total time from request submission until the complete response returns. Lower is better.</p></article>
  <article className="gemma-benchmark-card"><h3>Prefill</h3><p>Input-token processing rate before generation. It matters most for long documents and shared context. Higher is better.</p></article>
  <article className="gemma-benchmark-card"><h3>Decode</h3><p>Output-token generation rate for one active request after the first token. Higher is better.</p></article>
  <article className="gemma-benchmark-card"><h3>C16 output</h3><p>Combined output throughput from 16 simultaneous requests. It measures service capacity, not one request's speed.</p></article>
  <article className="gemma-benchmark-card"><h3>P50, P90, and P95</h3><p>P50 is the median. P90 and P95 expose tail behavior: 90% or 95% of requests completed at or below that value.</p></article>
</div>

## Complete timings by test type

Each table is calculated from all raw requests across the six prompt groups.
Mean is the arithmetic average; P50 is the median; P90 and P95 show tail
latency. These percentiles pool prompts of different lengths, so the tail
includes the longest prompts.

### T03 · Cold-prefix latency — concurrency 1

A unique prefix prevents cache reuse. Responses use natural EOS with a 512-token
maximum. Lower is better.

<div className="gemma-benchmark-table-shell gemma-benchmark-table-detail">
  <table aria-label="T03 cold-prefix latency results">
    <thead><tr><th scope="col">Deployment</th><th scope="col">Requests</th><th scope="col">Mean TTFT</th><th scope="col">P90 TTFT</th><th scope="col">Mean E2E</th><th scope="col">P50 E2E</th><th scope="col">P90 E2E</th><th scope="col">P95 E2E</th></tr></thead>
    <tbody>
      <tr><th scope="row">L40S BASE</th><td>60</td><td>3,553 ms</td><td>6,657 ms</td><td>22.86 s</td><td>23.53 s</td><td>26.62 s</td><td>26.64 s</td></tr>
      <tr><th scope="row">L40S OPT</th><td>60</td><td>2,981 ms</td><td>5,467 ms</td><td>14.96 s</td><td>14.35 s</td><td>22.78 s</td><td>23.43 s</td></tr>
      <tr><th scope="row">L40S QAT W4A16</th><td>60</td><td>2,872 ms</td><td>5,225 ms</td><td>11.17 s</td><td>11.85 s</td><td>14.08 s</td><td>14.10 s</td></tr>
      <tr><th scope="row">H100 BASE TP=1</th><td>60</td><td>898 ms</td><td>1,627 ms</td><td>7.21 s</td><td>7.32 s</td><td>8.04 s</td><td>8.04 s</td></tr>
      <tr><th scope="row">H100 OPT TP=1</th><td>60</td><td>1,816 ms</td><td>3,591 ms</td><td>7.70 s</td><td>7.45 s</td><td>12.00 s</td><td>12.23 s</td></tr>
      <tr className="gemma-benchmark-winner"><th scope="row">H100 BASE TP=4</th><td>60</td><td>381 ms</td><td>636 ms</td><td>3.81 s</td><td>3.84 s</td><td>4.13 s</td><td>4.14 s</td></tr>
    </tbody>
  </table>
</div>

### T04 · Warm-prefix latency — concurrency 1

Each prompt is primed before measurement to evaluate reusable-prefix behavior.
Responses use natural EOS with a 512-token maximum. Lower is better.

<div className="gemma-benchmark-table-shell gemma-benchmark-table-detail">
  <table aria-label="T04 warm-prefix latency results">
    <thead><tr><th scope="col">Deployment</th><th scope="col">Requests</th><th scope="col">Mean TTFT</th><th scope="col">P90 TTFT</th><th scope="col">Mean E2E</th><th scope="col">P50 E2E</th><th scope="col">P90 E2E</th><th scope="col">P95 E2E</th></tr></thead>
    <tbody>
      <tr><th scope="row">L40S BASE</th><td>60</td><td>140 ms</td><td>172 ms</td><td>19.44 s</td><td>19.79 s</td><td>20.12 s</td><td>20.12 s</td></tr>
      <tr><th scope="row">L40S OPT</th><td>60</td><td>139 ms</td><td>173 ms</td><td>11.78 s</td><td>11.04 s</td><td>18.14 s</td><td>18.15 s</td></tr>
      <tr><th scope="row">L40S QAT W4A16</th><td>60</td><td>109 ms</td><td>150 ms</td><td>8.37 s</td><td>8.73 s</td><td>8.98 s</td><td>8.98 s</td></tr>
      <tr><th scope="row">H100 BASE TP=1</th><td>60</td><td>99 ms</td><td>119 ms</td><td>6.42 s</td><td>6.46 s</td><td>6.52 s</td><td>6.52 s</td></tr>
      <tr><th scope="row">H100 OPT TP=1</th><td>60</td><td>104 ms</td><td>136 ms</td><td>5.95 s</td><td>5.71 s</td><td>8.69 s</td><td>8.70 s</td></tr>
      <tr className="gemma-benchmark-winner"><th scope="row">H100 BASE TP=4</th><td>60</td><td>98 ms</td><td>119 ms</td><td>3.52 s</td><td>3.53 s</td><td>3.60 s</td><td>3.63 s</td></tr>
    </tbody>
  </table>
</div>

### T05 · Fixed-length decode — concurrency 1

Every request generates exactly 512 output tokens with EOS ignored. Decode
throughput excludes TTFT. Lower E2E and higher decode throughput are better.

<div className="gemma-benchmark-table-shell gemma-benchmark-table-detail">
  <table aria-label="T05 fixed decode results">
    <thead><tr><th scope="col">Deployment</th><th scope="col">Requests</th><th scope="col">Mean E2E</th><th scope="col">P50 E2E</th><th scope="col">P90 E2E</th><th scope="col">P95 E2E</th><th scope="col">P50 decode</th><th scope="col">P95 decode</th></tr></thead>
    <tbody>
      <tr><th scope="row">L40S BASE</th><td>60</td><td>22.85 s</td><td>23.51 s</td><td>26.55 s</td><td>26.58 s</td><td>26.1 tok/s</td><td>27.9 tok/s</td></tr>
      <tr><th scope="row">L40S OPT</th><td>60</td><td>15.06 s</td><td>14.46 s</td><td>22.73 s</td><td>23.36 s</td><td>46.0 tok/s</td><td>65.3 tok/s</td></tr>
      <tr><th scope="row">L40S QAT W4A16</th><td>60</td><td>11.26 s</td><td>11.84 s</td><td>14.11 s</td><td>14.12 s</td><td>59.3 tok/s</td><td>66.6 tok/s</td></tr>
      <tr><th scope="row">H100 BASE TP=1</th><td>60</td><td>7.24 s</td><td>7.38 s</td><td>7.98 s</td><td>7.99 s</td><td>80.6 tok/s</td><td>81.5 tok/s</td></tr>
      <tr><th scope="row">H100 OPT TP=1</th><td>60</td><td>7.72 s</td><td>7.45 s</td><td>12.13 s</td><td>12.22 s</td><td>91.9 tok/s</td><td>151.8 tok/s</td></tr>
      <tr className="gemma-benchmark-winner"><th scope="row">H100 BASE TP=4</th><td>60</td><td>3.82 s</td><td>3.87 s</td><td>4.13 s</td><td>4.15 s</td><td>149.0 tok/s</td><td>151.3 tok/s</td></tr>
    </tbody>
  </table>
</div>

### T06 · Prefill — concurrency 1

Only one output token is requested, isolating input-prompt processing. Lower
TTFT and higher prefill throughput are better.

<div className="gemma-benchmark-table-shell gemma-benchmark-table-detail">
  <table aria-label="T06 prefill results">
    <thead><tr><th scope="col">Deployment</th><th scope="col">Requests</th><th scope="col">Mean TTFT</th><th scope="col">P50 TTFT</th><th scope="col">P90 TTFT</th><th scope="col">P95 TTFT</th><th scope="col">P50 prefill</th><th scope="col">P95 prefill</th></tr></thead>
    <tbody>
      <tr><th scope="row">L40S BASE</th><td>60</td><td>3,534 ms</td><td>3,896 ms</td><td>6,578 ms</td><td>6,611 ms</td><td>5,275 tok/s</td><td>6,852 tok/s</td></tr>
      <tr><th scope="row">L40S OPT</th><td>60</td><td>3,016 ms</td><td>3,383 ms</td><td>5,488 ms</td><td>5,503 ms</td><td>6,074 tok/s</td><td>7,214 tok/s</td></tr>
      <tr><th scope="row">L40S QAT W4A16</th><td>60</td><td>2,908 ms</td><td>3,254 ms</td><td>5,296 ms</td><td>5,317 ms</td><td>6,316 tok/s</td><td>7,228 tok/s</td></tr>
      <tr><th scope="row">H100 BASE TP=1</th><td>60</td><td>886 ms</td><td>988 ms</td><td>1,611 ms</td><td>1,612 ms</td><td>20,781 tok/s</td><td>21,466 tok/s</td></tr>
      <tr><th scope="row">H100 OPT TP=1</th><td>60</td><td>1,797 ms</td><td>1,845 ms</td><td>3,574 ms</td><td>3,579 ms</td><td>11,140 tok/s</td><td>17,169 tok/s</td></tr>
      <tr className="gemma-benchmark-winner"><th scope="row">H100 BASE TP=4</th><td>60</td><td>359 ms</td><td>401 ms</td><td>634 ms</td><td>636 ms</td><td>49,518 tok/s</td><td>51,286 tok/s</td></tr>
    </tbody>
  </table>
</div>

### T07 · Concurrency 1 — fixed 512-token output

Throughput reference with six measured requests per prompt. Aggregate output is
averaged across the six prompt groups.

<div className="gemma-benchmark-table-shell gemma-benchmark-table-detail">
  <table aria-label="T07 concurrency 1 results">
    <thead><tr><th scope="col">Deployment</th><th scope="col">Requests</th><th scope="col">P50 TTFT</th><th scope="col">P90 TTFT</th><th scope="col">Mean E2E</th><th scope="col">P50 E2E</th><th scope="col">P90 E2E</th><th scope="col">P95 E2E</th><th scope="col">Aggregate output</th></tr></thead>
    <tbody>
      <tr><th scope="row">L40S BASE</th><td>36</td><td>3,890 ms</td><td>6,657 ms</td><td>22.88 s</td><td>23.55 s</td><td>26.63 s</td><td>26.64 s</td><td>22.8 tok/s</td></tr>
      <tr><th scope="row">L40S OPT</th><td>36</td><td>3,351 ms</td><td>5,512 ms</td><td>15.20 s</td><td>14.29 s</td><td>23.31 s</td><td>23.42 s</td><td>37.0 tok/s</td></tr>
      <tr><th scope="row">L40S QAT W4A16</th><td>36</td><td>3,235 ms</td><td>5,300 ms</td><td>11.26 s</td><td>11.85 s</td><td>14.13 s</td><td>14.14 s</td><td>47.9 tok/s</td></tr>
      <tr><th scope="row">H100 BASE TP=1</th><td>36</td><td>1,019 ms</td><td>1,627 ms</td><td>7.22 s</td><td>7.33 s</td><td>7.98 s</td><td>7.99 s</td><td>71.4 tok/s</td></tr>
      <tr><th scope="row">H100 OPT TP=1</th><td>36</td><td>1,874 ms</td><td>3,589 ms</td><td>7.71 s</td><td>7.40 s</td><td>11.99 s</td><td>12.04 s</td><td>78.2 tok/s</td></tr>
      <tr className="gemma-benchmark-winner"><th scope="row">H100 BASE TP=4</th><td>36</td><td>417 ms</td><td>634 ms</td><td>3.79 s</td><td>3.83 s</td><td>4.10 s</td><td>4.10 s</td><td>135.5 tok/s</td></tr>
    </tbody>
  </table>
</div>

### T08 · Concurrency 4 — fixed 512-token output

Four simultaneous requests and twelve measured requests per prompt begin to
expose queueing and shared-execution latency.

<div className="gemma-benchmark-table-shell gemma-benchmark-table-detail">
  <table aria-label="T08 concurrency 4 results">
    <thead><tr><th scope="col">Deployment</th><th scope="col">Requests</th><th scope="col">P50 TTFT</th><th scope="col">P90 TTFT</th><th scope="col">Mean E2E</th><th scope="col">P50 E2E</th><th scope="col">P90 E2E</th><th scope="col">P95 E2E</th><th scope="col">Aggregate output</th></tr></thead>
    <tbody>
      <tr><th scope="row">L40S BASE</th><td>72</td><td>5,750 ms</td><td>12,231 ms</td><td>34.05 s</td><td>35.32 s</td><td>46.26 s</td><td>52.67 s</td><td>66.3 tok/s</td></tr>
      <tr><th scope="row">L40S OPT</th><td>72</td><td>3,676 ms</td><td>11,215 ms</td><td>24.65 s</td><td>24.45 s</td><td>40.11 s</td><td>43.46 s</td><td>104.5 tok/s</td></tr>
      <tr><th scope="row">L40S QAT W4A16</th><td>72</td><td>5,518 ms</td><td>9,871 ms</td><td>20.04 s</td><td>21.47 s</td><td>29.87 s</td><td>34.17 s</td><td>127.4 tok/s</td></tr>
      <tr><th scope="row">H100 BASE TP=1</th><td>72</td><td>1,976 ms</td><td>4,151 ms</td><td>10.03 s</td><td>10.41 s</td><td>12.90 s</td><td>12.95 s</td><td>217.4 tok/s</td></tr>
      <tr><th scope="row">H100 OPT TP=1</th><td>72</td><td>3,248 ms</td><td>7,083 ms</td><td>15.56 s</td><td>14.94 s</td><td>28.72 s</td><td>31.20 s</td><td>206.0 tok/s</td></tr>
      <tr className="gemma-benchmark-winner"><th scope="row">H100 BASE TP=4</th><td>72</td><td>771 ms</td><td>1,742 ms</td><td>4.87 s</td><td>5.03 s</td><td>6.01 s</td><td>6.02 s</td><td>438.2 tok/s</td></tr>
    </tbody>
  </table>
</div>

### T09 · Concurrency 8 — fixed 512-token output

Eight simultaneous requests and sixteen measured requests per prompt make tail
latency increasingly important.

<div className="gemma-benchmark-table-shell gemma-benchmark-table-detail">
  <table aria-label="T09 concurrency 8 results">
    <thead><tr><th scope="col">Deployment</th><th scope="col">Requests</th><th scope="col">P50 TTFT</th><th scope="col">P90 TTFT</th><th scope="col">Mean E2E</th><th scope="col">P50 E2E</th><th scope="col">P90 E2E</th><th scope="col">P95 E2E</th><th scope="col">Aggregate output</th></tr></thead>
    <tbody>
      <tr><th scope="row">L40S BASE</th><td>96</td><td>6,055 ms</td><td>28,685 ms</td><td>49.05 s</td><td>45.24 s</td><td>84.59 s</td><td>98.71 s</td><td>102.2 tok/s</td></tr>
      <tr><th scope="row">L40S OPT</th><td>96</td><td>5,450 ms</td><td>24,574 ms</td><td>36.78 s</td><td>34.58 s</td><td>66.25 s</td><td>80.15 s</td><td>159.6 tok/s</td></tr>
      <tr><th scope="row">L40S QAT W4A16</th><td>96</td><td>5,279 ms</td><td>23,821 ms</td><td>32.22 s</td><td>29.49 s</td><td>60.16 s</td><td>71.93 s</td><td>185.8 tok/s</td></tr>
      <tr><th scope="row">H100 BASE TP=1</th><td>96</td><td>2,972 ms</td><td>6,980 ms</td><td>13.79 s</td><td>14.36 s</td><td>20.45 s</td><td>23.90 s</td><td>344.2 tok/s</td></tr>
      <tr><th scope="row">H100 OPT TP=1</th><td>96</td><td>3,794 ms</td><td>14,441 ms</td><td>23.71 s</td><td>22.70 s</td><td>48.35 s</td><td>55.22 s</td><td>335.1 tok/s</td></tr>
      <tr className="gemma-benchmark-winner"><th scope="row">H100 BASE TP=4</th><td>96</td><td>1,195 ms</td><td>2,589 ms</td><td>6.39 s</td><td>6.74 s</td><td>8.69 s</td><td>9.86 s</td><td>709.2 tok/s</td></tr>
    </tbody>
  </table>
</div>

### T10 · Concurrency 16 — fixed 512-token output

Sixteen simultaneous requests and 32 measured requests per prompt represent the
highest tested load. These results must not be represented by concurrency-1 E2E
latency.

<div className="gemma-benchmark-table-shell gemma-benchmark-table-detail">
  <table aria-label="T10 concurrency 16 results">
    <thead><tr><th scope="col">Deployment</th><th scope="col">Requests</th><th scope="col">P50 TTFT</th><th scope="col">P90 TTFT</th><th scope="col">Mean E2E</th><th scope="col">P50 E2E</th><th scope="col">P90 E2E</th><th scope="col">P95 E2E</th><th scope="col">Aggregate output</th></tr></thead>
    <tbody>
      <tr><th scope="row">L40S BASE</th><td>192</td><td>6,324 ms</td><td>55,024 ms</td><td>79.18 s</td><td>67.80 s</td><td>155.91 s</td><td>186.27 s</td><td>147.3 tok/s</td></tr>
      <tr><th scope="row">L40S OPT</th><td>192</td><td>6,299 ms</td><td>47,232 ms</td><td>60.57 s</td><td>53.38 s</td><td>123.69 s</td><td>149.76 s</td><td>227.2 tok/s</td></tr>
      <tr><th scope="row">L40S QAT W4A16</th><td>192</td><td>5,658 ms</td><td>45,699 ms</td><td>56.74 s</td><td>47.15 s</td><td>118.92 s</td><td>143.81 s</td><td>252.4 tok/s</td></tr>
      <tr><th scope="row">H100 BASE TP=1</th><td>192</td><td>3,013 ms</td><td>13,394 ms</td><td>21.26 s</td><td>19.96 s</td><td>38.26 s</td><td>45.06 s</td><td>511.5 tok/s</td></tr>
      <tr><th scope="row">H100 OPT TP=1</th><td>192</td><td>4,175 ms</td><td>27,206 ms</td><td>38.67 s</td><td>34.19 s</td><td>86.14 s</td><td>103.44 s</td><td>507.5 tok/s</td></tr>
      <tr className="gemma-benchmark-winner"><th scope="row">H100 BASE TP=4</th><td>192</td><td>1,387 ms</td><td>4,951 ms</td><td>9.43 s</td><td>9.39 s</td><td>15.40 s</td><td>18.06 s</td><td>1,067.2 tok/s</td></tr>
    </tbody>
  </table>
</div>

## What changed the result

<div className="gemma-benchmark-decisions">
  <article className="gemma-benchmark-card">
    <h3>Performance and GPU allocation</h3>
    <ul>
      <li>H100 TP=4 was the clear technical leader, but used four GPUs.</li>
      <li>H100 BASE TP=1 was the better one-GPU configuration for long cold prompts.</li>
      <li>L40S QAT led the L40S configurations and used a 9.6 GiB checkpoint.</li>
      <li>P5 economics assume the unallocated GPUs host other useful work.</li>
    </ul>
  </article>
  <article className="gemma-benchmark-card">
    <h3>Engine settings</h3>
    <ul>
      <li>Prefix caching reduced warm TTFT to approximately 98–139 ms.</li>
      <li>N-gram speculation helped low-concurrency decode but hurt cold prefill.</li>
      <li>FP8 KV cache should be checked against application quality thresholds.</li>
      <li>TP=4 scaling was valuable but not linear or free.</li>
    </ul>
  </article>
</div>

### Instance-level deployment choice

- **P5:** use TP=4 for the latency-sensitive replica, then place another isolated
  workload on the remaining GPUs. Benchmark the combined load because host,
  network, and storage paths are shared.
- **G6E:** use QAT W4A16 only after it passes a natural-EOS quality test. If it
  does not, L40S OPT retains BF16 weights and remains faster than the baseline.

:::warning Quality gate required
The 512-token latency runs often reached the output cap before producing complete
JSON. The performance comparison is valid, but it is not a natural-completion
quality evaluation. Compare QAT with BF16 for schema validity, fact precision
and recall, omissions, and hallucinations before production selection.
:::

## Method and evidence

Each deployment completed eight tests: cold-prefix latency, warm-prefix latency,
fixed 512-token decode, one-token prefill, and fixed-decode concurrency at 1, 4,
8, and 16. Warm tests primed each prompt independently; cold tests used a unique
nonce. The accepted artifacts contained all six prompt summaries, expected
request counts, and no errors.

The TP=4 run showed four vLLM ranks on GPUs 0–3 and approximately 62.64 GiB of
KV-cache capacity per rank. Host-level evidence showed those GPUs at 81–86%
utilization during load while GPUs 4–7 remained unused. The QAT run confirmed
the Marlin W4A16 kernel, a 72.57-second compile, and 29.68 GiB of available KV
cache.

<div className="gemma-benchmark-evidence">
  <span>48 result artifacts</span>
  <span>Expected request counts</span>
  <span>Zero request errors</span>
  <span>Independent prompt priming</span>
  <span>Checksum manifests</span>
  <span>Physical TP=4 GPU evidence</span>
</div>

## Cost interpretation

The cost-efficiency score divides concurrency-16 output throughput by the
hourly compute cost allocated to the tested GPUs. The allocation is valid only
when the remaining P5 GPUs run productive workloads. A partially idle
`p5.48xlarge` must assign a larger fraction of its full hourly cost to each
active model deployment. Replace these reference rates with current regional or
contracted rates before making a production decision.

## Prompt corpus

The six prompts model customer-memory extraction and multi-record summarization
without publishing the underlying transcripts. Four prompts perform profile-fact
extraction over short (approximately 2,300 input tokens) and long
(approximately 20,500 input tokens) multi-turn conversations. Each size has two
strict-JSON schema variants: one records the source turn for every fact and one
does not. The two hydrated prompts use longer multi-session histories: one
extracts new atomic facts while deduplicating against prior learning
(approximately 31,400 input tokens), and the other produces one event-focused
summary with confidence, domain, and validity metadata (approximately 29,500
input tokens).

Every prompt contains task constraints, conversation context, and an explicit
output schema; hydrated cases also exercise prior-learning merge or deduplication
behavior. Every deployment used the same prompt files and request schedule. The
files remain local because the transcript content is not needed to interpret the
benchmark results.

## Run the benchmark

Start with the Gemma example README to
[prepare, deploy, and verify a scenario](https://github.com/awslabs/data-on-eks/tree/main/data-stacks/ray-on-eks/examples/gemma4-vllm-rayserve#run-it).
Then follow the
[benchmark runbook](https://github.com/awslabs/data-on-eks/blob/main/data-stacks/ray-on-eks/examples/gemma4-vllm-rayserve/benchmarks/README.md)
to execute T03–T10, validate each result artifact, collect the results, and
clean up the deployment.

_Benchmark run: August 2026._
