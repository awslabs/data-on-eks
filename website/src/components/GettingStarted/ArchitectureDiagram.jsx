import React from 'react';
import { Boxes, Wrench, Cloud } from 'lucide-react';

export default function ArchitectureDiagram() {
  return (
    <div className="architecture-section">
      <h2 className="architecture-title">
        <Wrench size={32} className="inline-block mr-3" strokeWidth={2.5} />
        Layered Architecture Pattern
      </h2>
      <div className="architecture-diagram">
        <div style={{
          display: 'flex',
          flexDirection: 'column',
          gap: '2rem',
          padding: '2rem'
        }}>
          {/* Data Stacks Layer */}
          <div style={{
            background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
            borderRadius: '16px',
            padding: '2rem',
            color: 'white',
            boxShadow: '0 8px 25px rgba(102, 126, 234, 0.4)',
            transition: 'all 0.3s ease'
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.transform = 'translateY(-4px)';
            e.currentTarget.style.boxShadow = '0 12px 35px rgba(102, 126, 234, 0.6)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.transform = 'translateY(0)';
            e.currentTarget.style.boxShadow = '0 8px 25px rgba(102, 126, 234, 0.4)';
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', marginBottom: '1rem' }}>
              <Boxes size={32} />
              <h3 style={{ margin: 0, fontSize: '1.5rem', fontWeight: '700' }}>
                Data Stacks (Application Layer)
              </h3>
            </div>
            <p style={{ margin: 0, fontSize: '0.95rem', opacity: 0.95 }}>
              Spark, Kafka, Airflow configurations • Custom Helm values • Job examples and blueprints
            </p>
          </div>

          {/* Arrow */}
          <div style={{ textAlign: 'center', margin: '-1rem 0' }}>
            <svg width="40" height="40" viewBox="0 0 40 40" style={{ opacity: 0.5 }}>
              <path d="M 20 5 L 20 35 M 15 30 L 20 35 L 25 30" stroke="var(--ifm-color-primary)" strokeWidth="3" fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </div>

          {/* Infrastructure Layer */}
          <div style={{
            background: 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
            borderRadius: '16px',
            padding: '2rem',
            color: 'white',
            boxShadow: '0 8px 25px rgba(240, 147, 251, 0.4)',
            transition: 'all 0.3s ease'
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.transform = 'translateY(-4px)';
            e.currentTarget.style.boxShadow = '0 12px 35px rgba(240, 147, 251, 0.6)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.transform = 'translateY(0)';
            e.currentTarget.style.boxShadow = '0 8px 25px rgba(240, 147, 251, 0.4)';
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', marginBottom: '1rem' }}>
              <Wrench size={32} />
              <h3 style={{ margin: 0, fontSize: '1.5rem', fontWeight: '700' }}>
                Infrastructure Modules (Platform Layer)
              </h3>
            </div>
            <p style={{ margin: 0, fontSize: '0.95rem', opacity: 0.95 }}>
              Terraform modules (/infra/terraform/) • EKS, VPC, IAM, Karpenter • ArgoCD addon deployment
            </p>
          </div>

          {/* Arrow */}
          <div style={{ textAlign: 'center', margin: '-1rem 0' }}>
            <svg width="40" height="40" viewBox="0 0 40 40" style={{ opacity: 0.5 }}>
              <path d="M 20 5 L 20 35 M 15 30 L 20 35 L 25 30" stroke="var(--ifm-color-primary)" strokeWidth="3" fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </div>

          {/* AWS Foundation Layer */}
          <div style={{
            background: 'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)',
            borderRadius: '16px',
            padding: '2rem',
            color: 'white',
            boxShadow: '0 8px 25px rgba(79, 172, 254, 0.4)',
            transition: 'all 0.3s ease'
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.transform = 'translateY(-4px)';
            e.currentTarget.style.boxShadow = '0 12px 35px rgba(79, 172, 254, 0.6)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.transform = 'translateY(0)';
            e.currentTarget.style.boxShadow = '0 8px 25px rgba(79, 172, 254, 0.4)';
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', marginBottom: '1rem' }}>
              <Cloud size={32} />
              <h3 style={{ margin: 0, fontSize: '1.5rem', fontWeight: '700' }}>
                AWS Foundation (Cloud Layer)
              </h3>
            </div>
            <p style={{ margin: 0, fontSize: '0.95rem', opacity: 0.95 }}>
              Amazon EKS managed control plane • EC2, VPC, S3, CloudWatch • IAM, KMS, Secrets Manager
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
