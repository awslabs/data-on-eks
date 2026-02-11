import React from 'react';
import clsx from 'clsx';
import Translate, {translate} from '@docusaurus/Translate';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import styles from './styles.module.css';
import TechMarquee from '../TechMarquee/TechMarquee';

const BASE_URL = 'https://awslabs.github.io/data-on-eks';

function getFeatureList(locale) {
  const prefix = locale === 'ko' ? `${BASE_URL}/ko` : BASE_URL;
  return [
  {
    title: translate({id: 'features.dataAnalytics.title', message: 'Data Analytics'}),
    Svg: require('@site/static/img/green-da.svg').default,
    description: translate({id: 'features.dataAnalytics.description', message: 'Transform your data with enterprise-grade analytics solutions. Deploy Apache Spark, Ray, Dask, and Jupyter environments with production-ready configurations. Scale from terabytes to petabytes with confidence using battle-tested architectures.'}),
    link: `${prefix}/docs/datastacks/processing`,
    imagePosition: 'left'
  },
  {
    title: translate({id: 'features.streaming.title', message: 'Streaming Data Platforms'}),
    Svg: require('@site/static/img/green-stream.svg').default,
    description: translate({id: 'features.streaming.description', message: 'Build real-time data pipelines that never sleep. Process millions of events per second with Apache Kafka, Flink, and Kinesis. From IoT sensors to financial transactions, handle any streaming workload at any scale.'}),
    link: `${prefix}/docs/datastacks/streaming`,
    imagePosition: 'right'
  },
  {
    title: translate({id: 'features.emr.title', message: 'Amazon EMR on EKS'}),
    Svg: require('@site/static/img/green-emr.svg').default,
    description: translate({id: 'features.emr.description', message: 'Run enterprise-grade Spark workloads on Kubernetes with Amazon EMR on EKS. Get optimized Spark runtime, automatic scaling, simplified job management, and seamless integration with AWS services for faster, more cost-effective big data processing.'}),
    link: `${prefix}/docs/category/amazon-emr-on-eks`,
    imagePosition: 'left'
  },
  {
    title: translate({id: 'features.orchestration.title', message: 'Workflow Orchestration'}),
    Svg: require('@site/static/img/green-schd.svg').default,
    description: translate({id: 'features.orchestration.description', message: 'Orchestrate complex data workflows with precision. Deploy Apache Airflow, Argo Workflows, and Amazon MWAA to automate ETL pipelines, ML training, and data quality checks. Never miss a dependency again.'}),
    link: `${prefix}/docs/datastacks/orchestration`,
    imagePosition: 'right'
  },
  {
    title: translate({id: 'features.databases.title', message: 'Distributed Databases & Query Engines'}),
    Svg: require('@site/static/img/green-dd.svg').default,
    description: translate({id: 'features.databases.description', message: 'Query anything, anywhere, anytime. Deploy Trino, Presto, and ClickHouse for lightning-fast analytics across data lakes, warehouses, and real-time streams. Join data across 50+ sources in milliseconds.'}),
    link: `${prefix}/docs/datastacks/databases`,
    imagePosition: 'left'
  },
];
}

function Feature({Svg, title, description, link, imagePosition, isLast}) {
  const contentSection = (
    <div className={styles.featureContent}>
      <h2 className={styles.featureTitle}>{title}</h2>
      <p className={styles.featureDescription}>{description}</p>
      <a href={link} className={styles.featureLink}>
        <Translate id="features.learnMore">Learn more</Translate>
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
  const { i18n } = useDocusaurusContext();
  const featureList = getFeatureList(i18n.currentLocale);
  return (
    <section className={styles.features}>
      <div className={styles.featuresHeader}>
        <h2 className={styles.featuresTitle}><Translate id="features.whatIs.title">What is Data on EKS?</Translate></h2>
        <p className={styles.featuresSubtitle}>
          <Translate id="features.whatIs.description">Data on EKS is an open-source, enterprise-ready framework for running scalable data platforms on Amazon EKS. It integrates open-source data tools with AWS infrastructure and offers Terraform and ArgoCD templates, proven blueprints, performance benchmarks, and best practices. Built for scale and resilience, it helps teams deploy and operate complex data workloads at thousands of nodes on EKS with confidence.</Translate>
        </p>
      </div>
      <TechMarquee />
      {featureList.map((props, idx) => (
        <Feature key={idx} {...props} isLast={idx === featureList.length - 1} />
      ))}
    </section>
  );
}
