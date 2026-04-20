#!/usr/bin/env python3
"""Analyze TPC-DS benchmark results: compare a candidate engine vs Native Spark."""

import argparse
import csv
import json
import math
from pathlib import Path

def load_results(path):
    results = {}
    failed = []
    with open(path) as f:
        reader = csv.DictReader(f, delimiter=',')
        required = {'Name', 'Mean', 'Min', 'Max'}
        if not required.issubset(reader.fieldnames or []):
            missing = required - set(reader.fieldnames or [])
            raise ValueError(f"{path}: missing columns: {missing}")
        for i, row in enumerate(reader, start=2):
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

def validate_inputs(default, comet, default_path, comet_path):
    warnings = []
    only_default = set(default) - set(comet)
    only_comet = set(comet) - set(default)
    if only_default:
        warnings.append(f"{len(only_default)} queries only in baseline: {sorted(only_default)}")
    if only_comet:
        warnings.append(f"{len(only_comet)} queries only in candidate: {sorted(only_comet)}")
    common = set(default) & set(comet)
    if not common:
        raise ValueError(f"No common queries between {default_path} and {comet_path}")
    for w in warnings:
        print(f"WARNING: {w}")
    return sorted(common)

def analyze(default_path, comet_path, candidate_name='Comet'):
    default, default_failed = load_results(default_path)
    comet, comet_failed = load_results(comet_path)
    all_failed = sorted(set(default_failed) | set(comet_failed))
    if all_failed:
        print(f"WARNING: {len(all_failed)} queries failed (missing values): {all_failed}")
    queries = validate_inputs(default, comet, default_path, comet_path)

    per_query = []
    for q in queries:
        d, c = default[q]['mean'], comet[q]['mean']
        speedup_pct = (d - c) / d * 100  # positive = candidate faster
        per_query.append({
            'query': q,
            'default_mean': round(d, 3),
            'candidate_mean': round(c, 3),
            'diff_seconds': round(c - d, 3),
            'speedup_pct': round(speedup_pct, 2),
            'default_range': round(default[q]['max'] - default[q]['min'], 3),
            'candidate_range': round(comet[q]['max'] - comet[q]['min'], 3),
        })

    # Aggregates
    total_default = sum(default[q]['mean'] for q in queries)
    total_comet = sum(comet[q]['mean'] for q in queries)
    overall_speedup_pct = (total_default - total_comet) / total_default * 100

    speedups = [r['speedup_pct'] for r in per_query]
    geo_mean = math.exp(sum(math.log(comet[q]['mean'] / default[q]['mean']) for q in queries) / len(queries))
    sorted_speedups = sorted(speedups)
    median_speedup = sorted_speedups[len(sorted_speedups) // 2]

    # Distribution buckets
    buckets = {'20%+ improvement': 0, '10-20% improvement': 0, '±10%': 0, '10-20% degradation': 0, '20%+ degradation': 0}
    for s in speedups:
        if s >= 20: buckets['20%+ improvement'] += 1
        elif s >= 10: buckets['10-20% improvement'] += 1
        elif s > -10: buckets['±10%'] += 1
        elif s > -20: buckets['10-20% degradation'] += 1
        else: buckets['20%+ degradation'] += 1

    wins = sum(1 for s in speedups if s > 0)
    losses = sum(1 for s in speedups if s < 0)

    top_improvements = sorted(per_query, key=lambda r: r['speedup_pct'], reverse=True)[:10]
    top_regressions = sorted(per_query, key=lambda r: r['speedup_pct'])[:10]

    report = {
        'candidate_name': candidate_name,
        'summary': {
            'total_queries': len(queries),
            'total_default_seconds': round(total_default, 2),
            'total_candidate_seconds': round(total_comet, 2),
            'overall_speedup_pct': round(overall_speedup_pct, 2),
            'geometric_mean_ratio': round(geo_mean, 4),
            'median_speedup_pct': round(median_speedup, 2),
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
    name = report['candidate_name']
    print("=" * 60)
    print(f"TPC-DS Benchmark: {name} vs Native Spark")
    print("=" * 60)
    print(f"Queries compared:      {s['total_queries']}")
    print(f"Total Default (s):     {s['total_default_seconds']}")
    print(f"Total {name} (s):{' ' * max(1, 21 - len(name) - 5)}{s['total_candidate_seconds']}")
    print(f"Overall speedup:       {s['overall_speedup_pct']}%")
    print(f"Geometric mean ratio:  {s['geometric_mean_ratio']}x")
    print(f"Median query speedup:  {s['median_speedup_pct']}%")
    print(f"{name} wins/losses:{' ' * max(1, 21 - len(name) - 13)}{s['candidate_wins']} / {s['candidate_losses']}")
    print()

    print("Distribution:")
    for bucket, count in report['distribution'].items():
        print(f"  {bucket:25s} {count}")
    print()

    print("Top 10 Improvements:")
    for r in report['top_improvements']:
        print(f"  {r['query']:20s} {r['speedup_pct']:+.1f}%  ({r['default_mean']:.1f}s → {r['candidate_mean']:.1f}s)")
    print()

    print("Top 10 Regressions:")
    for r in report['top_regressions']:
        print(f"  {r['query']:20s} {r['speedup_pct']:+.1f}%  ({r['default_mean']:.1f}s → {r['candidate_mean']:.1f}s)")

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
    labels: ['Native Spark', '{candidate_name}'],
    datasets: [{{
      label: 'Runtime (seconds)',
      data: [{total_d}, {total_c}],
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
| Native Spark | {total_d_fmt} | Baseline |
| {candidate_name} | {total_c_fmt} | **{perf_sign}{perf_pct:.0f}%** |

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
    name = report['candidate_name']

    dist_rows = [[label, count, f"{round(count / total_q * 100)}%"] for label, count in dist.items()]
    imp_rows = [[r['query'], f"{r['default_mean']:.1f}", f"{r['candidate_mean']:.1f}", f"**{r['speedup_pct']:.0f}%** faster"] for r in report['top_improvements']]
    reg_rows = [[r['query'], f"{r['default_mean']:.1f}", f"{r['candidate_mean']:.1f}", f"**{abs(r['speedup_pct']):,.0f}%** slower"] for r in report['top_regressions']]

    failed = report.get('failed_queries', [])
    if failed:
        failed_rows = [[q, 'Failed (missing values)'] for q in failed]
        failed_section = '\n#### Failed Queries\n\n' + _md_table(['Query', 'Status'], failed_rows)
    else:
        failed_section = ''

    return MARKDOWN_TEMPLATE.format(
        candidate_name=name,
        total_d=f"{s['total_default_seconds']:.2f}",
        total_c=f"{s['total_candidate_seconds']:.2f}",
        total_d_fmt=f"{s['total_default_seconds']:,.2f}",
        total_c_fmt=f"{s['total_candidate_seconds']:,.2f}",
        candidate_bar_bg='#e74c3c' if s['overall_speedup_pct'] < 0 else '#27ae60',
        candidate_bar_border='#c0392b' if s['overall_speedup_pct'] < 0 else '#229954',
        perf_sign='-' if s['overall_speedup_pct'] < 0 else '+',
        perf_pct=abs(s['overall_speedup_pct']),
        dist_data=list(dist.values()),
        dist_table=_md_table(['Performance Range', 'Query Count', 'Percentage'], dist_rows),
        imp_labels=[r['query'].replace('-v2.4', '') for r in report['top_improvements']],
        imp_data=[round(r['speedup_pct']) for r in report['top_improvements']],
        imp_table=_md_table(['Query', 'Native Spark (s)', f'{name} (s)', 'Improvement'], imp_rows),
        reg_labels=[r['query'].replace('-v2.4', '') for r in report['top_regressions']],
        reg_data=[round(abs(r['speedup_pct'])) for r in report['top_regressions']],
        reg_table=_md_table(['Query', 'Native Spark (s)', f'{name} (s)', 'Degradation'], reg_rows),
        failed_section=failed_section,
    )

def main():
    base = Path(__file__).parent
    parser = argparse.ArgumentParser(description='Analyze TPC-DS benchmark results: baseline vs candidate engine')
    parser.add_argument('--baseline', default=str(base / 'default-results.csv'), help='Baseline results CSV (default: default-results.csv)')
    parser.add_argument('--candidate', default=str(base / 'comet-results.csv'), help='Candidate engine results CSV (default: comet-results.csv)')
    parser.add_argument('--candidate-name', default='Comet', help='Display name for the candidate engine (default: Comet)')
    parser.add_argument('-o', '--output', default=str(base / 'benchmark-report.json'), help='Output JSON report path')
    parser.add_argument('--markdown', default=None, help='Output markdown snippets file')
    args = parser.parse_args()

    report = analyze(args.baseline, args.candidate, args.candidate_name)
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
