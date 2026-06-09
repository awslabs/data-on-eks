#!/usr/bin/env python3
"""Analyze TPC-DS benchmark results: compare a candidate engine vs a baseline."""

import argparse
import csv
import json
import math
import re
from pathlib import Path

# Strip TPC-DS query version suffixes (e.g. q1-v2.4 -> q1, q1-v4.0 -> q1) for chart labels.
QUERY_VERSION_SUFFIX = re.compile(r'-v\d+(?:\.\d+)*$')

def _strip_version(query):
    return QUERY_VERSION_SUFFIX.sub('', query)

def _fmt_speedup(ratio):
    """Format a speedup ratio (T_baseline / T_candidate). >=1 means candidate faster."""
    if ratio >= 10:
        return f"{ratio:.1f}×"
    return f"{ratio:.2f}×"

def load_results(path):
    DEFAULT_FIELDS = ['Name', 'Mean', 'Min', 'Max']
    required = set(DEFAULT_FIELDS)
    results = {}
    failed = []
    with open(path) as f:
        # Peek at the first row to decide whether a header is present.
        first_line = f.readline()
        if not first_line.strip():
            raise ValueError(f"{path}: file is empty")
        first_row = next(csv.reader([first_line]), [])
        has_header = required.issubset({c.strip() for c in first_row})
        f.seek(0)
        if has_header:
            reader = csv.DictReader(f, delimiter=',')
            if not required.issubset(reader.fieldnames or []):
                missing = required - set(reader.fieldnames or [])
                raise ValueError(f"{path}: missing columns: {missing}")
            start_line = 2
        else:
            reader = csv.DictReader(f, fieldnames=DEFAULT_FIELDS, delimiter=',')
            start_line = 1
        for i, row in enumerate(reader, start=start_line):
            name = row['Name']
            if not name:
                raise ValueError(f"{path} line {i}: empty query name")
            try:
                mean, mn, mx = float(row['Mean']), float(row['Min']), float(row['Max'])
            except (ValueError, TypeError):
                failed.append(name)
                continue
            if mean <= 0 or mn <= 0 or mx <= 0:
                failed.append(name)
                continue
            if not (mn <= mean <= mx):
                raise ValueError(f"{path} line {i} ({name}): expected min <= mean <= max, got {mn} <= {mean} <= {mx}")
            if name in results:
                raise ValueError(f"{path} line {i}: duplicate query '{name}'")
            results[name] = {'mean': mean, 'min': mn, 'max': mx}
    if not results:
        raise ValueError(f"{path}: no data rows found")
    return results, failed

def validate_inputs(baseline, candidate, baseline_path, candidate_path):
    warnings = []
    only_baseline = set(baseline) - set(candidate)
    only_candidate = set(candidate) - set(baseline)
    if only_baseline:
        warnings.append(f"{len(only_baseline)} queries only in baseline: {sorted(only_baseline)}")
    if only_candidate:
        warnings.append(f"{len(only_candidate)} queries only in candidate: {sorted(only_candidate)}")
    common = set(baseline) & set(candidate)
    if not common:
        raise ValueError(f"No common queries between {baseline_path} and {candidate_path}")
    for w in warnings:
        print(f"WARNING: {w}")
    return sorted(common)

def analyze(baseline_path, candidate_path, baseline_name='Native Spark', candidate_name='Comet'):
    baseline, baseline_failed = load_results(baseline_path)
    candidate, candidate_failed = load_results(candidate_path)
    all_failed = sorted(set(baseline_failed) | set(candidate_failed))
    if all_failed:
        print(f"WARNING: {len(all_failed)} queries failed (missing values): {all_failed}")
    queries = validate_inputs(baseline, candidate, baseline_path, candidate_path)

    per_query = []
    for q in queries:
        b, c = baseline[q]['mean'], candidate[q]['mean']
        speedup_pct = (b - c) / b * 100  # positive = candidate faster
        speedup = b / c  # >1 = candidate faster
        per_query.append({
            'query': q,
            'baseline_mean': round(b, 3),
            'candidate_mean': round(c, 3),
            'diff_seconds': round(c - b, 3),
            'speedup': round(speedup, 4),
            'speedup_pct': round(speedup_pct, 2),
            'baseline_range': round(baseline[q]['max'] - baseline[q]['min'], 3),
            'candidate_range': round(candidate[q]['max'] - candidate[q]['min'], 3),
        })

    # Aggregates
    total_baseline = sum(baseline[q]['mean'] for q in queries)
    total_candidate = sum(candidate[q]['mean'] for q in queries)
    overall_speedup = total_baseline / total_candidate
    overall_speedup_pct = (total_baseline - total_candidate) / total_baseline * 100

    speedups_pct = [r['speedup_pct'] for r in per_query]
    # Geometric mean of per-query speedup ratios (T_base / T_cand). >=1 means candidate faster.
    geo_mean_speedup = math.exp(
        sum(math.log(baseline[q]['mean'] / candidate[q]['mean']) for q in queries) / len(queries)
    )
    sorted_speedups_pct = sorted(speedups_pct)
    median_speedup_pct = sorted_speedups_pct[len(sorted_speedups_pct) // 2]
    sorted_speedups = sorted(r['speedup'] for r in per_query)
    median_speedup = sorted_speedups[len(sorted_speedups) // 2]

    # Distribution buckets (based on % time reduction; thresholds are intuitive in % terms)
    buckets = {'20%+ improvement': 0, '10-20% improvement': 0, '±10%': 0, '10-20% degradation': 0, '20%+ degradation': 0}
    for s in speedups_pct:
        if s >= 20: buckets['20%+ improvement'] += 1
        elif s >= 10: buckets['10-20% improvement'] += 1
        elif s > -10: buckets['±10%'] += 1
        elif s > -20: buckets['10-20% degradation'] += 1
        else: buckets['20%+ degradation'] += 1

    wins = sum(1 for s in speedups_pct if s > 0)
    losses = sum(1 for s in speedups_pct if s < 0)

    top_improvements = sorted(per_query, key=lambda r: r['speedup_pct'], reverse=True)[:10]
    top_regressions = sorted(per_query, key=lambda r: r['speedup_pct'])[:10]

    report = {
        'baseline_name': baseline_name,
        'candidate_name': candidate_name,
        'summary': {
            'total_queries': len(queries),
            'total_baseline_seconds': round(total_baseline, 2),
            'total_candidate_seconds': round(total_candidate, 2),
            'overall_speedup': round(overall_speedup, 4),
            'overall_speedup_pct': round(overall_speedup_pct, 2),
            'geometric_mean_speedup': round(geo_mean_speedup, 4),
            'median_speedup': round(median_speedup, 4),
            'median_speedup_pct': round(median_speedup_pct, 2),
            'candidate_wins': wins,
            'candidate_losses': losses,
            'ties': len(queries) - wins - losses,
        },
        'distribution': buckets,
        'top_improvements': top_improvements,
        'top_regressions': top_regressions,
        'per_query': sorted(per_query, key=lambda r: r['query']),
        'failed_queries': all_failed,
    }
    return report

def print_report(report):
    s = report['summary']
    baseline_name = report['baseline_name']
    candidate_name = report['candidate_name']
    labels = [
        'Queries compared:',
        f'Total {baseline_name} (s):',
        f'Total {candidate_name} (s):',
        'Overall speedup:',
        'Geometric mean speedup:',
        'Median query speedup:',
        f'{candidate_name} wins/losses:',
    ]
    label_width = max(len(lbl) for lbl in labels) + 2  # +2 for spacing before value
    print("=" * 60)
    print(f"TPC-DS Benchmark: {candidate_name} vs {baseline_name}")
    print("=" * 60)
    print(f"{labels[0]:{label_width}}{s['total_queries']}")
    print(f"{labels[1]:{label_width}}{s['total_baseline_seconds']}")
    print(f"{labels[2]:{label_width}}{s['total_candidate_seconds']}")
    print(f"{labels[3]:{label_width}}{_fmt_speedup(s['overall_speedup'])}  ({s['overall_speedup_pct']:+.2f}% time reduction)")
    print(f"{labels[4]:{label_width}}{_fmt_speedup(s['geometric_mean_speedup'])}")
    print(f"{labels[5]:{label_width}}{_fmt_speedup(s['median_speedup'])}  ({s['median_speedup_pct']:+.2f}% time reduction)")
    print(f"{labels[6]:{label_width}}{s['candidate_wins']} / {s['candidate_losses']}")
    print()

    print("Distribution:")
    for bucket, count in report['distribution'].items():
        print(f"  {bucket:25s} {count}")
    print()

    print("Top 10 Improvements:")
    for r in report['top_improvements']:
        print(f"  {r['query']:20s} {_fmt_speedup(r['speedup']):>7s}  ({r['baseline_mean']:.1f}s → {r['candidate_mean']:.1f}s, {r['speedup_pct']:+.0f}%)")
    print()

    print("Top 10 Regressions:")
    for r in report['top_regressions']:
        print(f"  {r['query']:20s} {_fmt_speedup(r['speedup']):>7s}  ({r['baseline_mean']:.1f}s → {r['candidate_mean']:.1f}s, {r['speedup_pct']:+.0f}%)")

    if report.get('failed_queries'):
        print()
        print("Failed (missing values):")
        for q in report['failed_queries']:
            print(f"  {q}")

MARKDOWN_TEMPLATE = """\

#### Overall Performance

<BarChart
  title="Total Runtime Comparison"
  data={{{{
    labels: ['{baseline_name}', '{candidate_name}'],
    datasets: [{{
      label: 'Runtime (seconds)',
      data: [{total_b}, {total_c}],
      backgroundColor: ['#27ae60', '{candidate_bar_bg}'],
      borderColor: ['#229954', '{candidate_bar_border}'],
      borderWidth: 2
    }}]
  }}}}
  options={{{{
    scales: {{
      y: {{ title: {{ display: true, text: 'Runtime (seconds)' }} }}
    }}
  }}}}
  height="300px"
/>

| Name | Completion Time (seconds) | Performance |
|------|---------------------------|-------------|
| {baseline_name} | {total_b_fmt} | Baseline |
| {candidate_name} | {total_c_fmt} | **{overall_speedup_fmt}** ({perf_sign}{perf_pct:.0f}% time) |

#### Performance Distribution

<PieChart
  title="Query Performance Distribution"
  type="doughnut"
  data={{{{
    labels: ['20%+ improvement', '10-20% improvement', '±10%', '10-20% degradation', '20%+ degradation'],
    datasets: [{{
      data: {dist_data},
      backgroundColor: ['#27ae60', '#3498db', '#f39c12', '#e67e22', '#e74c3c'],
      borderWidth: 2,
      borderColor: '#ffffff'
    }}]
  }}}}
/>

{dist_table}

#### Top 10 Query Improvements

<BarChart
  title="Top 10 Query Improvements (% faster with {candidate_name})"
  data={{{{
    labels: {imp_labels},
    datasets: [
      {{
        label: 'Improvement %',
        data: {imp_data},
        backgroundColor: '#27ae60',
        borderColor: '#229954',
        borderWidth: 1
      }}
    ]
  }}}}
  options={{{{
    scales: {{
      y: {{
        beginAtZero: true,
        title: {{ display: true, text: 'Improvement (%)' }}
      }},
      x: {{
        title: {{ display: true, text: 'TPC-DS Queries' }}
      }}
    }}
  }}}}
  height="400px"
/>

{imp_table}

#### Top 10 Query Regressions

<BarChart
  title="Top 10 Query Regressions (% slower with {candidate_name})"
  data={{{{
    labels: {reg_labels},
    datasets: [
      {{
        label: 'Degradation %',
        data: {reg_data},
        backgroundColor: '#e74c3c',
        borderColor: '#c0392b',
        borderWidth: 1
      }}
    ]
  }}}}
  options={{{{
    scales: {{
      y: {{
        beginAtZero: true,
        title: {{ display: true, text: 'Degradation (%)' }}
      }},
      x: {{
        title: {{ display: true, text: 'TPC-DS Queries' }}
      }}
    }}
  }}}}
  height="400px"
/>

{reg_table}
{failed_section}"""

def _md_table(headers, rows):
    sep = '|'.join(['---'] * len(headers))
    lines = ['| ' + ' | '.join(headers) + ' |', '|' + sep + '|']
    for row in rows:
        lines.append('| ' + ' | '.join(str(c) for c in row) + ' |')
    return '\n'.join(lines)

def generate_markdown(report):
    s = report['summary']
    dist = report['distribution']
    total_q = s['total_queries']
    baseline_name = report['baseline_name']
    candidate_name = report['candidate_name']

    dist_rows = [[label, count, f"{round(count / total_q * 100)}%"] for label, count in dist.items()]
    imp_rows = [[r['query'], f"{r['baseline_mean']:.1f}", f"{r['candidate_mean']:.1f}", f"**{_fmt_speedup(r['speedup'])}** ({r['speedup_pct']:+.0f}%)"] for r in report['top_improvements']]
    reg_rows = [[r['query'], f"{r['baseline_mean']:.1f}", f"{r['candidate_mean']:.1f}", f"**{abs(r['speedup_pct']):,.0f}%** slower ({_fmt_speedup(r['speedup'])})"] for r in report['top_regressions']]

    failed = report.get('failed_queries', [])
    if failed:
        failed_rows = [[q, 'Failed (missing values)'] for q in failed]
        failed_section = '\n#### Failed Queries\n\n' + _md_table(['Query', 'Status'], failed_rows)
    else:
        failed_section = ''

    return MARKDOWN_TEMPLATE.format(
        baseline_name=baseline_name,
        candidate_name=candidate_name,
        total_b=f"{s['total_baseline_seconds']:.2f}",
        total_c=f"{s['total_candidate_seconds']:.2f}",
        total_b_fmt=f"{s['total_baseline_seconds']:,.2f}",
        total_c_fmt=f"{s['total_candidate_seconds']:,.2f}",
        overall_speedup_fmt=_fmt_speedup(s['overall_speedup']),
        candidate_bar_bg='#e74c3c' if s['overall_speedup_pct'] < 0 else '#27ae60',
        candidate_bar_border='#c0392b' if s['overall_speedup_pct'] < 0 else '#229954',
        perf_sign='-' if s['overall_speedup_pct'] < 0 else '+',
        perf_pct=abs(s['overall_speedup_pct']),
        dist_data=list(dist.values()),
        dist_table=_md_table(['Performance Range', 'Query Count', 'Percentage'], dist_rows),
        imp_labels=[_strip_version(r['query']) for r in report['top_improvements']],
        imp_data=[round(r['speedup_pct']) for r in report['top_improvements']],
        imp_table=_md_table(['Query', f'{baseline_name} (s)', f'{candidate_name} (s)', 'Speedup'], imp_rows),
        reg_labels=[_strip_version(r['query']) for r in report['top_regressions']],
        reg_data=[round(abs(r['speedup_pct'])) for r in report['top_regressions']],
        reg_table=_md_table(['Query', f'{baseline_name} (s)', f'{candidate_name} (s)', 'Degradation'], reg_rows),
        failed_section=failed_section,
    )

def main():
    base = Path(__file__).parent
    parser = argparse.ArgumentParser(description='Analyze TPC-DS benchmark results: baseline vs candidate engine')
    parser.add_argument('--baseline', default=str(base / 'baseline-results.csv'), help='Baseline results CSV (default: baseline-results.csv)')
    parser.add_argument('--candidate', default=str(base / 'candidate-results.csv'), help='Candidate engine results CSV (default: candidate-results.csv)')
    parser.add_argument('--baseline-name', default='Native Spark', help='Display name for the baseline engine (default: Native Spark)')
    parser.add_argument('--candidate-name', default='Comet', help='Display name for the candidate engine (default: Comet)')
    parser.add_argument('-o', '--output', default=str(base / 'benchmark-report.json'), help='Output JSON report path')
    parser.add_argument('--markdown', default=None, help='Output markdown snippets file')
    args = parser.parse_args()

    report = analyze(args.baseline, args.candidate, args.baseline_name, args.candidate_name)
    print_report(report)

    with open(args.output, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nJSON report written to {args.output}")

    if args.markdown:
        md = generate_markdown(report)
        with open(args.markdown, 'w') as f:
            f.write(md)
        print(f"Markdown snippets written to {args.markdown}")

if __name__ == '__main__':
    main()
