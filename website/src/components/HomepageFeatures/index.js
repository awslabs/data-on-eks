import React from 'react';
import clsx from 'clsx';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: 'Data Analytics',
    Svg: require('@site/static/img/green-da.svg').default,
    description: (
      <div>
        Best Practice Data Analytics Deployment Templates and Examples for EKS with Apache Spark, Spark Operator, Dask, Beam, and More
      </div>
    ),
  },
  {
    title: 'Streaming Data Platforms',
    Svg: require('@site/static/img/green-stream.svg').default,
    description: (
      <>
        Building High-Scalability Streaming Data Platforms with Kafka, Flink, Spark Streaming, and More
      </>
    ),
  },
  {
    title: 'Amazon EMR on EKS',
    Svg: require('@site/static/img/green-emr.svg').default,
    description: (
      <>
        Optimized Multi-Tenant Deployment of Amazon EMR on EKS Cluster with Best Practices using Karpenter Autoscaler and Apache YuniKorn Templates<br/>
      </>
    ),
  },
  {
    title: 'Schedulers',
    Svg: require('@site/static/img/green-schd.svg').default,
    description: (
      <>
        Optimizing Job Scheduling on EKS with Apache Airflow, Amazon MWAA, Argo Workflow, and More
      </>
    ),
  },
  {
    title: 'Distributed Databases & Query Engines',
    Svg: require('@site/static/img/green-dd.svg').default,
    description: (
      <>
        Constructing High-Performance, Scalable Distributed Databases and Query Engines with Cassandra, Trino, Presto, and More
      </>
    ),
  },
];

function Feature({Svg, title, description}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <Svg className={styles.featureSvg} style={{width: '40%'}} role="img" />
      </div>
      <div className="text--center padding-horiz--md">
        <h2><b>{title}</b></h2>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row" style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'center' }}>
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
