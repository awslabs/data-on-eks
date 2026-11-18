import React from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';
import styles from './TechMarquee.module.css';

/*
 * Project logos, shown to identify the open source projects the data stacks use.
 * All names and logos are trademarks of their respective owners (ASF, CNCF, etc.)
 * and their use here does not imply endorsement.
 *
 * Sources:
 *  - static/img/tech-logos/<slug>.svg: Simple Icons (https://simpleicons.org, CC0),
 *    simple-icons@16.38.0. Monochrome paths, painted in each brand's official colour.
 *  - static/img/tech-logos/kubeflow.svg: github.com/kubeflow/website (official logo).
 *  - static/img/emr.svg: existing Data on EKS asset.
 *
 * `mask` logos are single-colour shapes painted with `brand` (and `brandDark` in dark
 * mode when the brand colour would disappear on the dark background).
 * `image` logos are full-colour and rendered as-is.
 */
const technologies = [
  // KUBEFLOW
  { name: 'Kubeflow', url: 'https://www.kubeflow.org/', category: 'Kubeflow', image: 'kubeflow', brand: '#4279f4' },
  { name: 'Kubeflow Spark Operator', url: 'https://github.com/kubeflow/spark-operator', category: 'Kubeflow', image: 'kubeflow', brand: '#4279f4', badge: 'apachespark', badgeBrand: '#E25A1C' },
  { name: 'Spark History Server MCP', url: 'https://github.com/kubeflow/mcp-apache-spark-history-server', category: 'Kubeflow', image: 'kubeflow', brand: '#4279f4', badge: 'apachespark', badgeBrand: '#E25A1C' },
  { name: 'Kubeflow Semantic Operator', url: 'https://github.com/kubeflow/semantic-operator', category: 'Kubeflow', image: 'kubeflow', brand: '#4279f4' },

  // PROCESSING
  { name: 'Apache Spark', url: 'https://spark.apache.org/', category: 'Processing', mask: 'apachespark', brand: '#E25A1C' },
  { name: 'Amazon EMR on EKS', url: 'https://aws.amazon.com/emr/features/eks/', category: 'Processing', mask: 'emr', brand: '#8C4FFF', brandDark: '#B48CFF' },
  { name: 'Ray', url: 'https://www.ray.io/', category: 'Processing', mask: 'ray', brand: '#028CF0' },

  // STREAMING
  { name: 'Apache Kafka', url: 'https://kafka.apache.org/', category: 'Streaming', mask: 'apachekafka', brand: '#231F20', brandDark: '#F4F3FF' },
  { name: 'Apache Flink', url: 'https://flink.apache.org/', category: 'Streaming', mask: 'apacheflink', brand: '#E6526F' },
  { name: 'Flink Operator', url: 'https://github.com/apache/flink-kubernetes-operator', category: 'Streaming', mask: 'apacheflink', brand: '#E6526F' },

  // ORCHESTRATION
  { name: 'Apache Airflow', url: 'https://airflow.apache.org/', category: 'Orchestration', mask: 'apacheairflow', brand: '#017CEE', brandDark: '#4AA3FF' },
  { name: 'Argo Workflows', url: 'https://argoproj.github.io/workflows/', category: 'Orchestration', mask: 'argo', brand: '#EF7B4D' },

  // DATABASES
  { name: 'PostgreSQL', url: 'https://www.postgresql.org/', category: 'Databases', mask: 'postgresql', brand: '#4169E1', brandDark: '#7B9BFF' },
  { name: 'ClickHouse', url: 'https://clickhouse.com/', category: 'Databases', mask: 'clickhouse', brand: '#E0B000', brandDark: '#FFCC01' },
  {
    name: 'Apache Pinot', url: 'https://pinot.apache.org/',
    category: 'Databases',
    brand: '#D9232E',
    brandDark: '#FF6B73',
    // No downloadable official logo; keep the simple glyph.
    icon: (
      <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="2" />
        <path d="M12 3V12L18 16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      </svg>
    ),
  },

  // QUERY ENGINES
  { name: 'Trino', url: 'https://trino.io/', category: 'Query Engines', mask: 'trino', brand: '#DD00A1', brandDark: '#FF4DC4' },
  { name: 'Presto', url: 'https://prestodb.io/', category: 'Query Engines', mask: 'presto', brand: '#5890FF' },

  // BI & VISUALIZATION
  { name: 'Apache Superset', url: 'https://superset.apache.org/', category: 'BI & Visualization', mask: 'apachesuperset', brand: '#20A6C9' },
  { name: 'Grafana', url: 'https://grafana.com/', category: 'BI & Visualization', mask: 'grafana', brand: '#F46800' },

  // NOTEBOOKS & AI
  { name: 'JupyterHub', url: 'https://jupyter.org/hub', category: 'Notebooks & AI', mask: 'jupyter', brand: '#F37626' },
  { name: 'Milvus', url: 'https://milvus.io/', category: 'Notebooks & AI', mask: 'milvus', brand: '#00A1EA' },
];

function Logo({ tech }) {
  const logosBase = useBaseUrl('/img/tech-logos/');
  const emrUrl = useBaseUrl('/img/emr.svg');
  const maskUrl = (slug) => (slug === 'emr' ? emrUrl : `${logosBase}${slug}.svg`);

  let mark;
  if (tech.image) {
    mark = <img className={styles.logoImg} src={`${logosBase}${tech.image}.svg`} alt="" loading="lazy" />;
  } else if (tech.mask) {
    mark = <span className={styles.logoMask} style={{ '--src': `url(${maskUrl(tech.mask)})` }} />;
  } else {
    mark = <span className={styles.logoGlyph}>{tech.icon}</span>;
  }

  return (
    <span className={styles.logoTile} aria-hidden="true">
      {mark}
      {tech.badge && (
        <span
          className={styles.badge}
          style={{ '--src': `url(${maskUrl(tech.badge)})`, '--badge-brand': tech.badgeBrand }}
        />
      )}
    </span>
  );
}

// Each chip links to the upstream project. Chips in the duplicate (aria-hidden)
// copy are taken out of the tab order so keyboard users meet each link once.
function Chip({ tech, hidden }) {
  return (
    <li
      className={styles.chipItem}
      style={{ '--brand': tech.brand, '--brand-dark': tech.brandDark || tech.brand }}
    >
      <a
        className={styles.chip}
        href={tech.url}
        target="_blank"
        rel="noopener noreferrer"
        tabIndex={hidden ? -1 : undefined}
        title={`${tech.name} (opens in a new tab)`}
      >
        <Logo tech={tech} />
        <span className={styles.techInfo}>
          <span className={styles.techName}>{tech.name}</span>
          <span className={styles.techCategory}>{tech.category}</span>
        </span>
        <svg className={styles.external} viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <path d="M5 11 11 5M6.5 5H11v4.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </a>
    </li>
  );
}

// Each row renders its list twice; the track slides by exactly one copy for a
// seamless loop. The second copy is hidden from assistive tech.
function MarqueeRow({ items, reverse }) {
  return (
    <div className={`${styles.row} ${reverse ? styles.reverse : ''}`}>
      <ul className={styles.track}>
        {items.map((tech) => (
          <Chip key={tech.name} tech={tech} />
        ))}
      </ul>
      <ul className={styles.track} aria-hidden="true">
        {items.map((tech) => (
          <Chip key={`dup-${tech.name}`} tech={tech} hidden />
        ))}
      </ul>
    </div>
  );
}

export default function TechMarquee() {
  const third = Math.ceil(technologies.length / 3);
  return (
    <div className={styles.techShowcase}>
      <div className={styles.showcaseHeader}>
        <h3 className={styles.showcaseTitle}>Powered by Open Source &amp; AWS</h3>
        <p className={styles.showcaseSubtitle}>
          Production-ready data stacks on Amazon EKS
        </p>
      </div>

      <div className={styles.marquee}>
        <MarqueeRow items={technologies.slice(0, third)} />
        <MarqueeRow items={technologies.slice(third, third * 2)} reverse />
        <MarqueeRow items={technologies.slice(third * 2)} />
      </div>
    </div>
  );
}
