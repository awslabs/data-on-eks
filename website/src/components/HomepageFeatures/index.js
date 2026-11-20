import React, { useCallback } from 'react';
import clsx from 'clsx';
import styles from './styles.module.css';
import TechMarquee from '../TechMarquee/TechMarquee';

// Bento layout: `size` maps to a grid-area span in styles.module.css.
const FeatureList = [
  {
    title: 'Agentic Data',
    Svg: require('@site/static/img/green-ai.svg').default,
    description: 'Production-ready reference architectures for AI agents built for data platforms. Deploy working agents that investigate metric anomalies, diagnose slow or failing Spark jobs, and trace pipeline breaks, built with open source frameworks like LangGraph and AWS services like Amazon Bedrock AgentCore.',
    link: 'https://awslabs.github.io/data-on-eks/docs/ai-ml',
    tags: ['AI agents', 'LangGraph', 'Bedrock AgentCore', 'Ray'],
    size: 'full',
    tone: 'agentic',
    badge: 'New',
  },
  {
    title: 'Data Analytics',
    Svg: require('@site/static/img/green-da.svg').default,
    description: 'Transform your data with enterprise-grade analytics solutions. Deploy Apache Spark, Ray, and Jupyter environments with production-ready configurations. Scale from terabytes to petabytes with confidence using battle-tested architectures.',
    link: 'https://awslabs.github.io/data-on-eks/docs/datastacks/processing',
    tags: ['Spark', 'Ray', 'Jupyter'],
    size: 'hero',
    tone: 'violet',
  },
  {
    title: 'Streaming Data Platforms',
    Svg: require('@site/static/img/green-stream.svg').default,
    description: 'Build real-time data pipelines that never sleep. Process millions of events per second with Apache Kafka, Flink, and Kinesis. From IoT sensors to financial transactions, handle any streaming workload at any scale.',
    link: 'https://awslabs.github.io/data-on-eks/docs/datastacks/streaming',
    tags: ['Kafka', 'Flink', 'Kinesis'],
    size: 'wide',
    tone: 'cyan',
  },
  {
    title: 'Amazon EMR on EKS',
    Svg: require('@site/static/img/green-emr.svg').default,
    description: 'Run enterprise-grade Spark workloads on Kubernetes with Amazon EMR on EKS. Get optimized Spark runtime, automatic scaling, simplified job management, and seamless integration with AWS services for faster, more cost-effective big data processing.',
    link: 'https://awslabs.github.io/data-on-eks/docs/category/amazon-emr-on-eks',
    tags: ['EMR', 'Spark runtime'],
    size: 'wide',
    tone: 'coral',
  },
  {
    title: 'Workflow Orchestration',
    Svg: require('@site/static/img/green-schd.svg').default,
    description: 'Orchestrate complex data workflows with precision. Deploy Apache Airflow and Argo Workflows to automate ETL pipelines, ML training, and data quality checks. Never miss a dependency again.',
    link: 'https://awslabs.github.io/data-on-eks/docs/datastacks/orchestration',
    tags: ['Airflow', 'Argo'],
    size: 'tall',
    tone: 'lime',
  },
  {
    title: 'Distributed Databases & Query Engines',
    Svg: require('@site/static/img/green-dd.svg').default,
    description: 'Query anything, anywhere, anytime. Deploy Trino, Presto, and ClickHouse for lightning-fast analytics across data lakes, warehouses, and real-time streams. Join data across 50+ sources in milliseconds.',
    link: 'https://awslabs.github.io/data-on-eks/docs/datastacks/databases',
    tags: ['Trino', 'Presto', 'ClickHouse'],
    size: 'banner',
    tone: 'violet',
  },
];

function Feature({ Svg, title, description, link, tags, size, tone, badge, index }) {
  // Cursor-following spotlight: store pointer position as CSS variables.
  const onPointerMove = useCallback((e) => {
    const r = e.currentTarget.getBoundingClientRect();
    e.currentTarget.style.setProperty('--mx', `${e.clientX - r.left}px`);
    e.currentTarget.style.setProperty('--my', `${e.clientY - r.top}px`);
  }, []);

  return (
    <a
      href={link}
      className={clsx(styles.tile, styles[size], styles[tone])}
      onPointerMove={onPointerMove}
    >
      <span className={styles.spotlight} aria-hidden="true" />
      <span className={styles.index} aria-hidden="true">
        {String(index + 1).padStart(2, '0')}
      </span>
      <div className={styles.art} aria-hidden="true">
        <Svg className={styles.illustration} />
      </div>
      <div className={styles.body}>
        <h3 className={styles.tileTitle}>
          {title}
          {badge && <span className={styles.badge}>{badge}</span>}
        </h3>
        <p className={styles.tileText}>{description}</p>
        <div className={styles.footer}>
          <ul className={styles.tags}>
            {tags.map((t) => (
              <li key={t}>{t}</li>
            ))}
          </ul>
          <span className={styles.more}>
            Learn more
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true">
              <path d="M3 8h9M8.5 4.5 12 8l-3.5 3.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
        </div>
      </div>
    </a>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className={styles.intro}>
        <p className={styles.kicker}>The platform</p>
        <h2 className={styles.introTitle}>
          What is <em>Data on EKS?</em>
        </h2>
        <p className={styles.introText}>
          Data on EKS is an open-source project for building agentic data platforms on Amazon EKS. It packages proven open-source data tools and AWS infrastructure as Terraform and ArgoCD blueprints, backed by performance benchmarks and best practices, so teams can run complex workloads across thousands of nodes with confidence. The agentic layer adds AI agents that investigate incidents and diagnose slow jobs, plus MCP servers and semantic layers that give AI structured access to your data.
        </p>
      </div>

      <TechMarquee />

      <div className={styles.bento}>
        {FeatureList.map((props, idx) => (
          <Feature key={props.title} {...props} index={idx} />
        ))}
      </div>
    </section>
  );
}
