import React, { useState } from 'react';
import Link from '@docusaurus/Link';
import styles from './TechMarquee.module.css';

// Row 1: Data Analytics & Streaming
const dataStreamingTools = [
  { name: "Apache Spark", color: "linear-gradient(135deg, #FFB84D 0%, #E25A1C 100%)" },
  { name: "Apache Flink", color: "linear-gradient(135deg, #FF8A9B 0%, #E6526F 100%)" },
  { name: "Apache Kafka", color: "linear-gradient(135deg, #9CA3AF 0%, #374151 100%)" },
  { name: "Ray Data", color: "linear-gradient(135deg, #60A5FA 0%, #2563EB 100%)", url: "/docs/blueprints/data-analytics/ray-data-processing" },
  { name: "Spark Operator", color: "linear-gradient(135deg, #FCD34D 0%, #F59E0B 100%)" },
  { name: "Flink Operator", color: "linear-gradient(135deg, #F472B6 0%, #DB2777 100%)" }
];

// Row 2: Orchestration & Databases
const orchestrationDbTools = [
  { name: "Apache Airflow", color: "linear-gradient(135deg, #93C5FD 0%, #3B82F6 100%)" },
  { name: "Argo Workflows", color: "linear-gradient(135deg, #FDBA74 0%, #EA580C 100%)" },
  { name: "Trino", color: "linear-gradient(135deg, #F0ABFC 0%, #C026D3 100%)" },
  { name: "ClickHouse", color: "linear-gradient(135deg, #FDE047 0%, #CA8A04 100%)" },
  { name: "Apache Pinot", color: "linear-gradient(135deg, #A7F3D0 0%, #059669 100%)" },
  { name: "Apache Superset", color: "linear-gradient(135deg, #7DD3FC 0%, #0284C7 100%)" }
];

// Row 3: AWS Managed Services
const awsServices = [
  { name: "Amazon EMR on EKS", color: "linear-gradient(135deg, #FBBF24 0%, #F59E0B 100%)" },
  { name: "Amazon EKS", color: "linear-gradient(135deg, #FCD34D 0%, #D97706 100%)" },
  { name: "AWS Batch", color: "linear-gradient(135deg, #F97316 0%, #C2410C 100%)" },
  { name: "Amazon MWAA", color: "linear-gradient(135deg, #FB923C 0%, #EA580C 100%)" },
  { name: "Amazon Kinesis", color: "linear-gradient(135deg, #60A5FA 0%, #2563EB 100%)" },
  { name: "Amazon S3", color: "linear-gradient(135deg, #34D399 0%, #059669 100%)" }
];

export default function TechMarquee() {
  return (
    <div className={styles.marqueeContainer}>
      <div className={styles.marqueeContent}>
        {/* Row 1: Data Analytics & Streaming */}
        <div className={styles.marqueeRow}>
          {dataStreamingTools.map((tech, index) => {
            if (tech.url) {
              return (
                <Link
                  key={`data-${index}`}
                  to={tech.url}
                  className={styles.techItem}
                  style={{ background: tech.color, textDecoration: 'none' }}
                >
                  <span className={styles.techName}>{tech.name}</span>
                </Link>
              );
            }
            return (
              <div
                key={`data-${index}`}
                className={styles.techItem}
                style={{ background: tech.color }}
              >
                <span className={styles.techName}>{tech.name}</span>
              </div>
            );
          })}
        </div>

        {/* Row 2: Orchestration & Databases (Reverse Direction) */}
        <div className={styles.marqueeRow} data-reverse="true">
          {orchestrationDbTools.map((tech, index) => (
            <div
              key={`orch-${index}`}
              className={styles.techItem}
              style={{ background: tech.color }}
            >
              <span className={styles.techName}>{tech.name}</span>
            </div>
          ))}
        </div>

        {/* Row 3: AWS Managed Services */}
        <div className={styles.marqueeRow}>
          {awsServices.map((tech, index) => (
            <div
              key={`aws-${index}`}
              className={styles.techItem}
              style={{ background: tech.color }}
            >
              <span className={styles.techName}>{tech.name}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
