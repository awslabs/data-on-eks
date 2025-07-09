import React from 'react';
import clsx from 'clsx';
import Translate from '@docusaurus/Translate';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: (
      <Translate
        id="homepage.features.dataAnalytics.title"
        description="Title for Data Analytics feature">
        Data Analytics
      </Translate>
    ),
    Svg: require('@site/static/img/green-da.svg').default,
    description: (
      <div>
        <Translate
          id="homepage.features.dataAnalytics.description"
          description="Description for Data Analytics feature">
          Best Practice Data Analytics Deployment Templates and Examples for EKS with Apache Spark, Spark Operator, Dask, Beam, and More
        </Translate>
      </div>
    ),
  },
  {
    title: (
      <Translate
        id="homepage.features.streamingDataPlatforms.title"
        description="Title for Streaming Data Platforms feature">
        Streaming Data Platforms
      </Translate>
    ),
    Svg: require('@site/static/img/green-stream.svg').default,
    description: (
      <>
        <Translate
          id="homepage.features.streamingDataPlatforms.description"
          description="Description for Streaming Data Platforms feature">
          Building High-Scalability Streaming Data Platforms with Kafka, Flink, Spark Streaming, and More
        </Translate>
      </>
    ),
  },
  {
    title: (
      <Translate
        id="homepage.features.emrOnEks.title"
        description="Title for Amazon EMR on EKS feature">
        Amazon EMR on EKS
      </Translate>
    ),
    Svg: require('@site/static/img/green-emr.svg').default,
    description: (
      <>
        <Translate
          id="homepage.features.emrOnEks.description"
          description="Description for Amazon EMR on EKS feature">
          Optimized Multi-Tenant Deployment of Amazon EMR on EKS Cluster with Best Practices using Karpenter Autoscaler and Apache YuniKorn Templates
        </Translate><br/>
      </>
    ),
  },
  {
    title: (
      <Translate
        id="homepage.features.schedulers.title"
        description="Title for Schedulers feature">
        Schedulers
      </Translate>
    ),
    Svg: require('@site/static/img/green-schd.svg').default,
    description: (
      <>
        <Translate
          id="homepage.features.schedulers.description"
          description="Description for Schedulers feature">
          Optimizing Job Scheduling on EKS with Apache Airflow, Amazon MWAA, Argo Workflow, and More
        </Translate>
      </>
    ),
  },
  {
    title: (
      <Translate
        id="homepage.features.distributedDatabases.title"
        description="Title for Distributed Databases & Query Engines feature">
        Distributed Databases & Query Engines
      </Translate>
    ),
    Svg: require('@site/static/img/green-dd.svg').default,
    description: (
      <>
        <Translate
          id="homepage.features.distributedDatabases.description"
          description="Description for Distributed Databases & Query Engines feature">
          Constructing High-Performance, Scalable Distributed Databases and Query Engines with Cassandra, Trino, Presto, and More
        </Translate>
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
