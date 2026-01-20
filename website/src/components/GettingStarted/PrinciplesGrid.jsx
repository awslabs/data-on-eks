import React from 'react';
import { Target, Lock, DollarSign, BarChart3 } from 'lucide-react';

const principles = [
  {
    Icon: Target,
    title: 'Opinionated, Not Prescriptive',
    description: 'Pre-configured with sane defaults for 80% use cases. Fully customizable via Terraform variables and Helm values. Modular architecture - adopt incrementally.',
    gradient: 'from-purple-500 to-pink-500'
  },
  {
    Icon: Lock,
    title: 'Security by Default',
    description: 'IAM Roles for Service Accounts (IRSA) for pod-level permissions. Private VPC with NAT gateways, security groups. Encryption at rest (EBS/EFS with KMS).',
    gradient: 'from-blue-500 to-cyan-500'
  },
  {
    Icon: DollarSign,
    title: 'Cost-Optimized',
    description: 'Karpenter for intelligent node provisioning (Spot + On-Demand). Right-sized instance recommendations. Auto-scaling with predictive capacity planning.',
    gradient: 'from-green-500 to-emerald-500'
  },
  {
    Icon: BarChart3,
    title: 'Observable from Day 1',
    description: 'Prometheus + Grafana with pre-built dashboards. Application-specific metrics (Spark, Flink, Kafka). CloudWatch integration for AWS-native tooling.',
    gradient: 'from-orange-500 to-red-500'
  }
];

export default function PrinciplesGrid() {
  return (
    <>
      <h2 style={{ textAlign: 'center', fontSize: '2.5rem', fontWeight: '800', marginBottom: '3rem', marginTop: '4rem' }}>
        Design Principles
      </h2>
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(2, 1fr)',
        gap: '2rem',
        margin: '3rem 0'
      }}>
        {principles.map((principle, index) => (
          <div key={index} className="principle-card">
            <div
              style={{
                display: 'inline-flex',
                padding: '1rem',
                borderRadius: '16px',
                marginBottom: '1.5rem',
                background: `linear-gradient(135deg, var(--ifm-color-primary), var(--ifm-color-primary-dark))`,
                boxShadow: '0 8px 25px rgba(102, 126, 234, 0.3)'
              }}
            >
              <principle.Icon size={40} color="white" strokeWidth={2} />
            </div>
            <h3 className="principle-title">{principle.title}</h3>
            <p className="principle-description">{principle.description}</p>
          </div>
        ))}
      </div>
    </>
  );
}
