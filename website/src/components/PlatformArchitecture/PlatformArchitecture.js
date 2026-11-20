import React, { useCallback, useEffect, useRef, useState } from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import styles from './PlatformArchitecture.module.css';

/*
 * End-to-end agentic data platform reference architecture.
 *
 * Layout (desktop):
 *   Agentic layer   [Spark agent] [Semantic Operator] [Ad intelligence]
 *                         \              \               /
 *   Compute         Ingest -> Stream   Batch   Query & serve   AI inference
 *                              |  write  | r/w    ^ read         | r/w
 *   Lakehouse       storage [ Amazon S3 · S3 Tables · S3 Vectors · Apache Iceberg ]
 *                   catalog [ AWS Glue Data Catalog · Apache Polaris · DataHub ]
 *   Control         Develop & orchestrate | Batch scheduling
 *   Foundation      EKS, EC2, Karpenter, ArgoCD, Terraform, observability
 *
 * Boxes are HTML/CSS. The wires are an SVG overlay measured from the boxes'
 * positions (see `useWires`), drawn only when the compute row is one line wide.
 * On narrower screens each box shows a short text hint instead.
 *
 * Logos: Simple Icons (CC0) in static/img/tech-logos, AWS Architecture Icons in
 * static/img/aws-icons, Kubeflow's own logo; projects without a published icon
 * get a two-letter monogram. All names and logos belong to their owners.
 */

const EXTERNAL = { target: '_blank', rel: 'noopener noreferrer' };

// icon kinds: tile = full-colour square (AWS service icons), img = full-colour
// image, mask = single-colour shape painted with the node colour, mono = letters.
const tech = (slug) => ({ kind: 'mask', src: `tech-logos/${slug}.svg` });
const aws = (slug) => ({ kind: 'tile', src: `aws-icons/${slug}.svg` });
const awsLine = (slug) => ({ kind: 'mask', src: `aws-icons/${slug}.svg` });
const mono = (text) => ({ kind: 'mono', text });

const agents = [
  {
    id: 'agent-spark',
    tag: 'Spark History Server MCP',
    title: 'Spark troubleshooting agent',
    text: 'Reads Spark event logs through MCP, finds the bottleneck stage in failed or slow jobs and recommends a fix.',
    target: 'Batch',
    href: 'https://github.com/kubeflow/mcp-apache-spark-history-server',
  },
  {
    id: 'agent-semantic',
    tag: 'Semantic layer · MCP',
    title: 'Kubeflow Semantic Operator',
    text: 'Governed semantic models as Kubernetes resources, so agents query business metrics instead of guessing at raw tables.',
    target: 'Query & serve',
    href: 'https://github.com/kubeflow/semantic-operator',
  },
  {
    id: 'agent-ads',
    tag: 'StarRocks MCP · Amazon Bedrock',
    title: 'Agentic ad intelligence',
    text: 'Watches live ad metrics in StarRocks, investigates anomalies across every dimension and writes the root-cause report.',
    target: 'Query & serve',
    to: '/docs/ai-ml/agentic-ad-intelligence',
  },
];

const stages = [
  {
    id: 'stage-ingest',
    name: 'Ingest',
    caption: 'Events, CDC and logs',
    nodes: [
      { name: 'Apache Kafka', sub: 'Strimzi operator', icon: tech('apachekafka'), color: '#f4f3ff', href: 'https://kafka.apache.org/' },
    ],
    note: 'Real-time topics also feed Pinot, ClickHouse and StarRocks directly.',
  },
  {
    id: 'stage-stream',
    name: 'Stream',
    caption: 'Parallel choices',
    split: true,
    nodes: [
      { name: 'Apache Flink', sub: 'Flink operator', icon: tech('apacheflink'), color: '#ff7a93', href: 'https://flink.apache.org/' },
      { name: 'Spark Structured Streaming', icon: tech('apachespark'), color: '#ff8a4c', href: 'https://spark.apache.org/streaming/' },
    ],
    hint: '↓ Writes to the lakehouse',
  },
  {
    id: 'stage-batch',
    name: 'Batch',
    caption: 'Spark at scale',
    nodes: [
      { name: 'Spark Operator', sub: 'Kubeflow', icon: { kind: 'img', src: 'tech-logos/kubeflow.svg' }, color: '#6d9bff', href: 'https://github.com/kubeflow/spark-operator' },
      { name: 'EMR on EKS', icon: { kind: 'mask', src: 'emr.svg' }, color: '#b48cff', href: 'https://aws.amazon.com/emr/features/eks/' },
    ],
    extra: {
      label: 'Accelerators',
      nodes: [
        { name: 'DataFusion Comet', icon: mono('Co'), color: '#f7c948', href: 'https://datafusion.apache.org/comet/' },
        { name: 'Gluten + Velox', icon: mono('Gv'), color: '#7ee0a1', href: 'https://gluten.apache.org/' },
        { name: 'Spark RAPIDS', sub: 'GPU', icon: tech('nvidia'), color: '#9be22d', href: 'https://nvidia.github.io/spark-rapids/' },
      ],
    },
    hint: '↕ Reads and writes the lakehouse',
  },
  {
    id: 'stage-serve',
    name: 'Query & serve',
    caption: 'SQL, OLAP, search, BI and cache',
    nodes: [
      { name: 'Trino', icon: tech('trino'), color: '#ff4dc4', href: 'https://trino.io/' },
      { name: 'StarRocks', icon: mono('SR'), color: '#7aa7ff', href: 'https://www.starrocks.io/' },
      { name: 'ClickHouse', icon: tech('clickhouse'), color: '#ffcc01', href: 'https://clickhouse.com/' },
      { name: 'Apache Pinot', icon: mono('Pi'), color: '#ff6b73', href: 'https://pinot.apache.org/' },
      { name: 'OpenSearch', icon: tech('opensearch'), color: '#4fc3f7', href: 'https://opensearch.org/' },
      { name: 'Apache Superset', sub: 'BI dashboards', icon: tech('apachesuperset'), color: '#4fd1ef', href: 'https://superset.apache.org/' },
      { name: 'Valkey', sub: 'In-memory cache', icon: mono('Vk'), color: '#ff6f61', href: 'https://valkey.io/' },
    ],
    hint: '↑ Reads from the lakehouse',
  },
  {
    id: 'stage-ai',
    name: 'AI inference',
    caption: 'Batch, on GPUs',
    nodes: [
      { name: 'Ray Data', sub: 'KubeRay', icon: tech('ray'), color: '#4db2ff', href: 'https://docs.ray.io/en/latest/data/data.html' },
      { name: 'vLLM', sub: 'NVIDIA GPUs', icon: mono('vL'), color: '#fdb515', href: 'https://docs.vllm.ai/' },
    ],
    note: 'Reads Iceberg tables, writes predictions back and embeddings to S3 Vectors.',
    hint: '↕ Reads tables, writes results and embeddings',
  },
];

const lakeStorage = [
  { name: 'Amazon S3', sub: 'Object storage', icon: aws('s3'), color: '#8fd14f', href: 'https://aws.amazon.com/s3/' },
  { name: 'Amazon S3 Tables', sub: 'Managed Iceberg tables', icon: awsLine('s3-tables'), color: '#8fd14f', href: 'https://aws.amazon.com/s3/features/tables/' },
  { name: 'Amazon S3 Vectors', sub: 'Vector storage', icon: awsLine('s3-vectors'), color: '#8fd14f', href: 'https://aws.amazon.com/s3/features/vectors/' },
  { name: 'Apache Iceberg', sub: 'Open table format', icon: mono('Ic'), color: '#7cc7ff', href: 'https://iceberg.apache.org/' },
];

const lakeCatalog = [
  { name: 'AWS Glue Data Catalog', sub: 'Managed catalog', icon: aws('glue'), color: '#a98bff', href: 'https://aws.amazon.com/glue/' },
  { name: 'Apache Polaris', sub: 'Iceberg REST catalog', icon: mono('Po'), color: '#7cc7ff', href: 'https://polaris.apache.org/' },
  { name: 'DataHub', sub: 'Discovery and lineage', icon: mono('DH'), color: '#6fb6ff', href: 'https://datahubproject.io/' },
];

const lakeRows = [
  { label: 'Storage', nodes: lakeStorage },
  { label: 'Catalog & metadata', nodes: lakeCatalog },
];

const bands = [
  {
    name: 'Develop & orchestrate',
    nodes: [
      { name: 'JupyterHub', sub: 'Notebooks', icon: tech('jupyter'), color: '#f37726', href: 'https://jupyter.org/hub' },
      { name: 'Apache Airflow', icon: tech('apacheairflow'), color: '#4aa3ff', href: 'https://airflow.apache.org/' },
      { name: 'Argo Workflows', icon: tech('argo'), color: '#ef7b4d', href: 'https://argoproj.github.io/workflows/' },
    ],
  },
  {
    name: 'Batch scheduling',
    nodes: [
      { name: 'Apache YuniKorn', icon: mono('Yk'), color: '#ff9f43', href: 'https://yunikorn.apache.org/' },
      { name: 'Volcano', icon: mono('Vo'), color: '#ff6b6b', href: 'https://volcano.sh/' },
      { name: 'Kueue', icon: tech('kubernetes'), color: '#6d9bff', href: 'https://kueue.sigs.k8s.io/' },
    ],
  },
];

const foundation = [
  { name: 'Amazon EKS', icon: aws('eks'), color: '#ff9900', href: 'https://aws.amazon.com/eks/' },
  { name: 'Amazon EC2', sub: 'Graviton · Spot · GPUs', icon: aws('ec2'), color: '#ff9900', href: 'https://aws.amazon.com/ec2/' },
  { name: 'Karpenter', icon: mono('K'), color: '#b4a6ff', href: 'https://karpenter.sh/' },
  { name: 'ArgoCD', icon: tech('argo'), color: '#ef7b4d', href: 'https://argo-cd.readthedocs.io/' },
  { name: 'Terraform', icon: tech('terraform'), color: '#a98bff', href: 'https://www.terraform.io/' },
  { name: 'Prometheus · Grafana', icon: tech('prometheus'), color: '#ff7a45', href: 'https://prometheus.io/' },
];

// Wires drawn over the board. `from`/`to` are data-node ids. Agent wires run from
// the bottom of a card to the top of a stage; storage wires run vertically
// between a stage and the lakehouse. `offset` separates wires that share a target.
const wires = [
  { from: 'agent-spark', to: 'stage-batch', kind: 'agent', label: 'MCP' },
  { from: 'agent-semantic', to: 'stage-serve', kind: 'agent', label: 'MCP', offset: -22 },
  { from: 'agent-ads', to: 'stage-serve', kind: 'agent', label: 'MCP', offset: 22 },
  { from: 'stage-ingest', to: 'stage-stream', kind: 'flow' },
  { from: 'stage-stream', to: 'lake', kind: 'store', dir: 'down', label: 'write' },
  { from: 'stage-batch', to: 'lake', kind: 'store', dir: 'both', label: 'read · write' },
  { from: 'stage-serve', to: 'lake', kind: 'store', dir: 'up', label: 'read' },
  { from: 'stage-ai', to: 'lake', kind: 'store', dir: 'both', label: 'read · write' },
];

const WIDE_QUERY = '(min-width: 997px)';

function useWires(boardRef) {
  const [paths, setPaths] = useState([]);

  const measure = useCallback(() => {
    const board = boardRef.current;
    if (!board || !window.matchMedia(WIDE_QUERY).matches) {
      setPaths([]);
      return;
    }
    const origin = board.getBoundingClientRect();
    const box = (id) => {
      const r = board.querySelector(`[data-node="${id}"]`).getBoundingClientRect();
      return {
        l: r.left - origin.left,
        r: r.right - origin.left,
        t: r.top - origin.top,
        b: r.bottom - origin.top,
        cx: (r.left + r.right) / 2 - origin.left,
      };
    };

    setPaths(
      wires.map((w) => {
        const a = box(w.from);
        const z = box(w.to);

        if (w.kind === 'agent') {
          const x1 = a.cx;
          const y1 = a.b;
          const x2 = z.cx + (w.offset || 0);
          const y2 = z.t - 2;
          const my = (y1 + y2) / 2;
          return {
            ...w,
            d: `M${x1} ${y1} C${x1} ${my}, ${x2} ${my}, ${x2} ${y2}`,
            lx: (x1 + x2) / 2,
            ly: my,
          };
        }

        if (w.kind === 'flow') {
          const y = a.t + 30;
          return { ...w, d: `M${a.r} ${y} L${z.l - 2} ${y}` };
        }

        // store: vertical between a stage and the lakehouse band
        const x = a.cx;
        const top = a.b;
        const bottom = z.t;
        const d = w.dir === 'up' ? `M${x} ${bottom} L${x} ${top + 2}` : `M${x} ${top} L${x} ${bottom - 2}`;
        return { ...w, d, lx: x + 8, ly: (top + bottom) / 2 };
      }),
    );
  }, [boardRef]);

  useEffect(() => {
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(boardRef.current);
    const mq = window.matchMedia(WIDE_QUERY);
    mq.addEventListener('change', measure);
    if (document.fonts?.ready) document.fonts.ready.then(measure);
    return () => {
      ro.disconnect();
      mq.removeEventListener('change', measure);
    };
  }, [measure, boardRef]);

  return paths;
}

function Icon({ icon }) {
  const base = useBaseUrl('/img/');
  if (icon.kind === 'mono') return <span className={styles.markMono}>{icon.text}</span>;
  if (icon.kind === 'tile') return <img className={styles.markTile} src={base + icon.src} alt="" loading="lazy" />;
  if (icon.kind === 'img') return <img className={styles.markImg} src={base + icon.src} alt="" loading="lazy" />;
  return <span className={styles.markMask} style={{ '--src': `url(${base + icon.src})` }} />;
}

function Node({ node, compact }) {
  return (
    <a
      className={`${styles.node} ${compact ? styles.compact : ''}`}
      href={node.href}
      {...EXTERNAL}
      style={{ '--c': node.color }}
      title={`${node.name} (opens in a new tab)`}
    >
      <span className={`${styles.mark} ${node.icon.kind === 'tile' ? styles.markBare : ''}`} aria-hidden="true">
        <Icon icon={node.icon} />
      </span>
      <span className={styles.nodeText}>
        <span className={styles.nodeName}>{node.name}</span>
        {node.sub && <span className={styles.nodeSub}>{node.sub}</span>}
      </span>
    </a>
  );
}

function Stage({ stage, index }) {
  return (
    <li className={styles.stage} data-node={stage.id}>
      <header className={styles.stageHead}>
        <span className={styles.stageIndex}>{String(index + 1).padStart(2, '0')}</span>
        <h3 className={styles.stageName}>{stage.name}</h3>
        <p className={styles.stageCaption}>{stage.caption}</p>
      </header>

      <div className={styles.nodes}>
        {stage.nodes.map((node, i) => (
          <React.Fragment key={node.name}>
            {stage.split && i > 0 && <span className={styles.or}>or</span>}
            <Node node={node} />
          </React.Fragment>
        ))}
      </div>

      {stage.extra && (
        <div className={styles.extra}>
          <span className={styles.extraLabel}>{stage.extra.label}</span>
          {stage.extra.nodes.map((node) => (
            <Node key={node.name} node={node} compact />
          ))}
        </div>
      )}

      {stage.note && <p className={styles.note}>{stage.note}</p>}
      {stage.hint && <p className={styles.hint}>{stage.hint}</p>}
    </li>
  );
}

function AgentCard({ agent }) {
  const body = (
    <>
      <span className={styles.agentTag}>{agent.tag}</span>
      <h3 className={styles.agentTitle}>{agent.title}</h3>
      <p className={styles.agentText}>{agent.text}</p>
      <span className={styles.agentTarget}>
        <span aria-hidden="true">→</span> Acts on {agent.target}
      </span>
    </>
  );
  const props = { className: styles.agent, 'data-node': agent.id };

  return agent.to ? (
    <Link {...props} to={agent.to}>{body}</Link>
  ) : (
    <a {...props} href={agent.href} {...EXTERNAL}>{body}</a>
  );
}

function Wires({ paths }) {
  if (!paths.length) return null;
  return (
    <>
      <svg className={styles.wires} aria-hidden="true">
        <defs>
          <marker id="pa-arrow-lime" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
            <path d="M0 0 10 5 0 10z" fill="#c6f23e" />
          </marker>
          <marker id="pa-arrow-violet" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
            <path d="M0 0 10 5 0 10z" fill="#a898ff" />
          </marker>
          <marker id="pa-arrow-green" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
            <path d="M0 0 10 5 0 10z" fill="#8fd14f" />
          </marker>
        </defs>
        {paths.map((p) => {
          const marker = p.kind === 'agent' ? 'lime' : p.kind === 'flow' ? 'violet' : 'green';
          return (
            <path
              key={`${p.from}-${p.to}`}
              d={p.d}
              className={`${styles.wire} ${styles[`wire_${p.kind}`]}`}
              markerEnd={`url(#pa-arrow-${marker})`}
              markerStart={p.dir === 'both' ? `url(#pa-arrow-${marker})` : undefined}
            />
          );
        })}
      </svg>
      {paths
        .filter((p) => p.label)
        .map((p) => (
          <span
            key={`label-${p.from}-${p.to}`}
            className={`${styles.wireLabel} ${styles[`label_${p.kind}`]}`}
            style={{ left: p.lx, top: p.ly }}
            aria-hidden="true"
          >
            {p.label}
          </span>
        ))}
    </>
  );
}

export default function PlatformArchitecture() {
  const boardRef = useRef(null);
  const paths = useWires(boardRef);

  return (
    <section className={styles.section} aria-labelledby="architecture-heading">
      <div className={styles.head}>
        <p className={styles.kicker}>Reference architecture</p>
        <h2 id="architecture-heading" className={styles.title}>
          One platform, <em>end to end.</em>
        </h2>
        <p className={styles.lede}>
          From streaming ingest to GPU inference, every layer is an open-source blueprint
          on Amazon EKS, built on an open lakehouse, with AI agents working across it.
        </p>
      </div>

      <div className={`${styles.board} ${paths.length ? styles.wired : ''}`} ref={boardRef}>
        <div className={styles.glow} aria-hidden="true" />
        <Wires paths={paths} />

        <div className={styles.layerHead}>
          <span className={styles.layerDot} />
          <span className={styles.layerName}>Agentic layer</span>
          <span className={styles.layerRule} />
        </div>
        <div className={styles.agents}>
          {agents.map((a) => (
            <AgentCard key={a.id} agent={a} />
          ))}
        </div>

        <div className={`${styles.layerHead} ${styles.layerGap}`}>
          <span className={`${styles.layerDot} ${styles.layerDotData}`} />
          <span className={styles.layerName}>Data plane</span>
        </div>
        <ol className={styles.pipeline}>
          {stages.map((s, i) => (
            <Stage key={s.id} stage={s} index={i} />
          ))}
        </ol>

        <div className={styles.lakehouse} data-node="lake">
          <div className={styles.lakeHead}>
            <span className={styles.lakeTag}>Shared data</span>
            <h3 className={styles.lakeName}>Open lakehouse</h3>
            <p className={styles.stageCaption}>Tables, files and vectors on Amazon S3, governed by one catalog</p>
          </div>
          <div className={styles.lakeRows}>
            {lakeRows.map((row) => (
              <div key={row.label} className={styles.lakeRow}>
                <span className={styles.lakeRowLabel}>{row.label}</span>
                <div className={styles.lakeNodes}>
                  {row.nodes.map((n) => (
                    <Node key={n.name} node={n} />
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className={styles.bands}>
          {bands.map((b) => (
            <div key={b.name} className={styles.band}>
              <span className={styles.bandName}>{b.name}</span>
              <div className={styles.bandNodes}>
                {b.nodes.map((n) => (
                  <Node key={n.name} node={n} compact />
                ))}
              </div>
            </div>
          ))}
        </div>

        <div className={styles.foundation}>
          <span className={styles.bandName}>Foundation</span>
          <div className={styles.bandNodes}>
            {foundation.map((n) => (
              <Node key={n.name} node={n} compact />
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
