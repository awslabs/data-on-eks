import React from 'react';
import Link from '@docusaurus/Link';
import { Cpu, Waves, GitBranch, Database, Target, ArrowRight } from 'lucide-react';

const stacks = [
  {
    category: 'Processing',
    Icon: Cpu,
    color: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
    stacks: [
      { name: 'Spark on EKS', description: 'ETL, batch processing', link: '/data-on-eks/docs/datastacks/processing/spark-on-eks/' },
      { name: 'EMR on EKS', description: 'Managed Spark runtime', link: '/data-on-eks/docs/datastacks/processing/emr-on-eks/' },
      { name: 'Ray Data on EKS', description: 'Distributed ML/data', link: '/data-on-eks/docs/datastacks/processing/raydata-on-eks/' },
    ]
  },
  {
    category: 'Streaming',
    Icon: Waves,
    color: 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
    stacks: [
      { name: 'Kafka on EKS', description: 'Event streaming, pub/sub', link: '/data-on-eks/docs/datastacks/streaming/kafka-on-eks/' },
      { name: 'Flink on EKS', description: 'Stateful stream processing', link: '/data-on-eks/docs/datastacks/streaming/flink-on-eks/' },
      { name: 'EMR Flink', description: 'Managed Flink runtime', link: '/data-on-eks/docs/datastacks/streaming/emr-eks-flink/' },
    ]
  },
  {
    category: 'Orchestration',
    Icon: GitBranch,
    color: 'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)',
    stacks: [
      { name: 'Airflow on EKS', description: 'DAG-based workflows', link: '/data-on-eks/docs/datastacks/orchestration/airflow-on-eks/' },
      { name: 'Argo Workflows', description: 'K8s-native pipelines', link: '/data-on-eks/docs/datastacks/processing/spark-on-eks/argo-workflows' },
      { name: 'Amazon MWAA', description: 'Managed Airflow', link: '/data-on-eks/docs/datastacks/orchestration/amazon-mwaa/' },
    ]
  },
  {
    category: 'Databases',
    Icon: Database,
    color: 'linear-gradient(135deg, #43e97b 0%, #38f9d7 100%)',
    stacks: [
      { name: 'PostgreSQL', description: 'Transactional database', link: '/data-on-eks/docs/datastacks/databases/postgres-on-eks/' },
      { name: 'ClickHouse', description: 'OLAP analytics', link: '/data-on-eks/docs/datastacks/databases/clickhouse-on-eks/' },
      { name: 'Apache Pinot', description: 'Real-time OLAP', link: '/data-on-eks/docs/datastacks/databases/pinot-on-eks/' },
    ]
  }
];

export default function DataStacksShowcase() {
  return (
    <div style={{ margin: '4rem 0' }}>
      <h2 style={{
        textAlign: 'center',
        fontSize: '2.5rem',
        fontWeight: '800',
        marginBottom: '1rem',
        background: 'linear-gradient(135deg, #667eea, #764ba2)',
        WebkitBackgroundClip: 'text',
        WebkitTextFillColor: 'transparent',
        backgroundClip: 'text',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '1rem'
      }}>
        <Target size={36} style={{ color: '#667eea' }} />
        Data Stacks Catalog
      </h2>
      <p style={{
        textAlign: 'center',
        fontSize: '1.2rem',
        color: 'var(--ifm-color-content-secondary)',
        marginBottom: '3rem',
        maxWidth: '700px',
        marginLeft: 'auto',
        marginRight: 'auto'
      }}>
        Production-ready data platforms with complete deployment guides, examples, and best practices
      </p>

      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
        gap: '2rem',
        marginBottom: '3rem'
      }}>
        {stacks.map((category, idx) => (
          <div
            key={idx}
            style={{
              background: 'var(--ifm-background-color)',
              borderRadius: '20px',
              padding: '2rem',
              border: '2px solid rgba(102, 126, 234, 0.1)',
              transition: 'all 0.3s ease',
              boxShadow: '0 10px 40px rgba(0, 0, 0, 0.08)',
              cursor: 'pointer'
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.transform = 'translateY(-8px)';
              e.currentTarget.style.boxShadow = '0 20px 60px rgba(0, 0, 0, 0.15)';
              e.currentTarget.style.borderColor = 'rgba(102, 126, 234, 0.3)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.transform = 'translateY(0)';
              e.currentTarget.style.boxShadow = '0 10px 40px rgba(0, 0, 0, 0.08)';
              e.currentTarget.style.borderColor = 'rgba(102, 126, 234, 0.1)';
            }}
          >
            <div style={{
              display: 'flex',
              alignItems: 'center',
              gap: '1rem',
              marginBottom: '1.5rem'
            }}>
              <div style={{
                width: '64px',
                height: '64px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                background: category.color,
                borderRadius: '16px',
                boxShadow: '0 8px 25px rgba(0, 0, 0, 0.2)'
              }}>
                <category.Icon size={32} color="white" strokeWidth={2} />
              </div>
              <h3 style={{
                margin: 0,
                fontSize: '1.5rem',
                fontWeight: '700',
                color: 'var(--ifm-heading-color)'
              }}>
                {category.category}
              </h3>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
              {category.stacks.map((stack, stackIdx) => (
                <Link
                  key={stackIdx}
                  to={stack.link}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    padding: '1rem',
                    background: 'rgba(102, 126, 234, 0.05)',
                    borderRadius: '12px',
                    textDecoration: 'none',
                    transition: 'all 0.2s ease',
                    border: '1px solid rgba(102, 126, 234, 0.1)'
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.background = 'rgba(102, 126, 234, 0.1)';
                    e.currentTarget.style.transform = 'translateX(4px)';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.background = 'rgba(102, 126, 234, 0.05)';
                    e.currentTarget.style.transform = 'translateX(0)';
                  }}
                >
                  <div>
                    <div style={{
                      fontWeight: '700',
                      color: 'var(--ifm-heading-color)',
                      marginBottom: '0.25rem'
                    }}>
                      {stack.name}
                    </div>
                    <div style={{
                      fontSize: '0.875rem',
                      color: 'var(--ifm-color-content-secondary)'
                    }}>
                      {stack.description}
                    </div>
                  </div>
                  <ArrowRight size={20} style={{ color: '#667eea', flexShrink: 0 }} />
                </Link>
              ))}
            </div>
          </div>
        ))}
      </div>

      <div style={{ textAlign: 'center' }}>
        <Link
          to="/data-on-eks/docs/datastacks/"
          className="cta-button"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '0.75rem',
            padding: '1rem 2.5rem',
            background: 'linear-gradient(135deg, #667eea, #764ba2)',
            color: 'white',
            borderRadius: '50px',
            textDecoration: 'none',
            fontWeight: '700',
            fontSize: '1.1rem',
            boxShadow: '0 8px 25px rgba(102, 126, 234, 0.4)',
            transition: 'all 0.3s ease'
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.transform = 'translateY(-3px)';
            e.currentTarget.style.boxShadow = '0 12px 35px rgba(102, 126, 234, 0.6)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.transform = 'translateY(0)';
            e.currentTarget.style.boxShadow = '0 8px 25px rgba(102, 126, 234, 0.4)';
          }}
        >
          <span>View All Data Stacks</span>
          <ArrowRight size={20} />
        </Link>
      </div>
    </div>
  );
}
