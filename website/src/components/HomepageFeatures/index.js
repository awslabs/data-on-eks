import React from 'react';
import clsx from 'clsx';
import styles from './styles.module.css';

const FeatureList = [
    {
        title: 'Amazon EMR on EKS',
        // Svg: require('@site/static/img/undraw_docusaurus_mountain.svg').default,
        description: (
            <>
                Easily build, deploy and scale Spark workloads with Amazon EMR on EKS multi-tenant clusters and optimized EMR runtime.<br/>
                Simplify Management, Reduce Costs and faster performance with optimized EMR Spark.
            </>
        ),
    },
  {
    title: 'Apache Spark on EKS',
    // Svg: require('@site/static/img/undraw_docusaurus_mountain.svg').default,
    description: (
      <div>
        Self-managed Apache Spark on Amazon EKS. <br/> Build, deploy and run self-managed Spark clusters on Amazon EKS with custom schedulers.
          <br/>e.g., spark-submit, spark-operator, Apache YuniKorn, Volcano
      </div>
    ),
  },
  {
    title: 'AI/ML on EKS',
    // Svg: require('@site/static/img/ml.svg').default,
    description: (
      <>
        Build, deploy and scale open source AI/ML platforms on Amazon EKS integrations with Machine Learning on AWS.<br/>
          e.g., KubeFlow, MLFlow, JupyterHub
      </>
    ),
  },
  {
    title: 'Distributed Databases on EKS',
    // Svg: require('@site/static/img/undraw_docusaurus_react.svg').default,
    description: (
      <>
        Build and scale highly scalable self-managed open source distributed databases on Amazon EKS. <br/>
          e.g., Cassandra, CockroachDB, MongoDB etc.
      </>
    ),
  },
    {
        title: 'Streaming Data Platforms on EKS',
        // Svg: require('@site/static/img/undraw_docusaurus_react.svg').default,
        description: (
            <>
                Self-managed open source streaming platforms to build and scale on Amazon EKS. <br/>e.g., Kafka, Spark structured streaming, Flink etc.
            </>
        ),
    },
    {
        title: 'Observability on EKS',
        // Svg: require('@site/static/img/undraw_docusaurus_react.svg').default,
        description: (
            <>
                Observability patterns for Spark workloads and other data platforms on Amazon EKS. <br/>
                e.g., AWS Managed Prometheus, AWS Managed Grafana
            </>
        ),
    },
];

function Feature({Svg, title, description}) {
  return (
    <div className={clsx('col col--4')}>
      {/*<div className="text--center">*/}
      {/*  <Svg className={styles.featureSvg} role="img" />*/}
      {/*</div>*/}
      <div className="text--center padding-horiz--md">
        <h2>{title}</h2>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
