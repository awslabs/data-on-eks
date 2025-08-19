import React from 'react';
import clsx from 'clsx';
import styles from './styles.module.css';
import TechMarquee from '../TechMarquee/TechMarquee';

const FeatureList = [
  {
    title: 'Data Analytics',
    Svg: require('@site/static/img/green-da.svg').default,
    description: 'Transform your data with enterprise-grade analytics solutions. Deploy Apache Spark, Ray, Dask, and Jupyter environments with production-ready configurations. Scale from terabytes to petabytes with confidence using battle-tested architectures.',
    link: 'https://awslabs.github.io/data-on-eks/docs/category/data-analytics-on-eks',
    imagePosition: 'left'
  },
  {
    title: 'Streaming Data Platforms',
    Svg: require('@site/static/img/green-stream.svg').default,
    description: 'Build real-time data pipelines that never sleep. Process millions of events per second with Apache Kafka, Flink, and Kinesis. From IoT sensors to financial transactions, handle any streaming workload at any scale.',
    link: 'https://awslabs.github.io/data-on-eks/docs/category/streaming-platforms-on-eks',
    imagePosition: 'right'
  },
  {
    title: 'Amazon EMR on EKS',
    Svg: require('@site/static/img/green-emr.svg').default,
    description: 'Run enterprise-grade Spark workloads on Kubernetes with Amazon EMR on EKS. Get optimized Spark runtime, automatic scaling, simplified job management, and seamless integration with AWS services for faster, more cost-effective big data processing.',
    link: 'https://awslabs.github.io/data-on-eks/docs/category/amazon-emr-on-eks',
    imagePosition: 'left'
  },
  {
    title: 'Workflow Orchestration',
    Svg: require('@site/static/img/green-schd.svg').default,
    description: 'Orchestrate complex data workflows with precision. Deploy Apache Airflow, Argo Workflows, and Amazon MWAA to automate ETL pipelines, ML training, and data quality checks. Never miss a dependency again.',
    link: 'https://awslabs.github.io/data-on-eks/docs/category/job-schedulers-on-eks',
    imagePosition: 'right'
  },
  {
    title: 'Distributed Databases & Query Engines',
    Svg: require('@site/static/img/green-dd.svg').default,
    description: 'Query anything, anywhere, anytime. Deploy Trino, Presto, and ClickHouse for lightning-fast analytics across data lakes, warehouses, and real-time streams. Join data across 50+ sources in milliseconds.',
    link: 'https://awslabs.github.io/data-on-eks/docs/category/distributed-databases-on-eks',
    imagePosition: 'left'
  },
];

function Feature({Svg, title, description, link, imagePosition, isLast}) {
  const contentSection = (
    <div className={styles.featureContent}>
      <h2 className={styles.featureTitle}>{title}</h2>
      <p className={styles.featureDescription}>{description}</p>
      <a href={link} className={styles.featureLink}>
        Learn more
        <svg className={styles.featureLinkIcon} width="16" height="16" viewBox="0 0 16 16" fill="none">
          <path d="M6 12L10 8L6 4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      </a>
    </div>
  );

  const imageSection = (
    <div className={styles.featureImageContainer}>
      <Svg className={styles.featureImage} role="img" />
    </div>
  );

  return (
    <div className={clsx(styles.featureSection, !isLast && styles.featureSectionBorder)}>
      <div className={styles.featureContainer}>
        {imagePosition === 'left' ? (
          <>
            {imageSection}
            {contentSection}
          </>
        ) : (
          <>
            {contentSection}
            {imageSection}
          </>
        )}
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className={styles.featuresHeader}>
        <h2 className={styles.featuresTitle}>What is Data on EKS?</h2>
        <p className={styles.featuresSubtitle}>
          Data on EKS is an open-source, enterprise-ready framework for running scalable data platforms on Amazon EKS. It integrates open-source data tools with AWS infrastructure and offers Terraform and ArgoCD templates, proven blueprints, performance benchmarks, and best practices. Built for scale and resilience, it helps teams deploy and operate complex data workloads at thousands of nodes on EKS with confidence.
        </p>
      </div>
      <TechMarquee />
      {FeatureList.map((props, idx) => (
        <Feature key={idx} {...props} isLast={idx === FeatureList.length - 1} />
      ))}
    </section>
  );
}
