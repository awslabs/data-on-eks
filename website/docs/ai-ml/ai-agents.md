---
title: AI Agents for Data
sidebar_position: 3
---

import { Cpu, Construction } from 'lucide-react';

<div style={{
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  justifyContent: 'center',
  padding: '4rem 2rem',
  textAlign: 'center',
  minHeight: '400px'
}}>
  <div style={{
    background: 'linear-gradient(135deg, rgba(251, 146, 60, 0.1), rgba(251, 113, 133, 0.1))',
    borderRadius: '50%',
    padding: '3rem',
    marginBottom: '2rem',
    border: '3px solid rgba(251, 146, 60, 0.3)'
  }}>
    <Construction size={80} strokeWidth={1.5} style={{ color: '#f97316' }} />
  </div>

  <h1 style={{
    fontSize: '2.5rem',
    fontWeight: '700',
    marginBottom: '1rem',
    background: 'linear-gradient(135deg, #f97316, #ec4899)',
    WebkitBackgroundClip: 'text',
    WebkitTextFillColor: 'transparent',
    backgroundClip: 'text'
  }}>
    Under Construction
  </h1>

  <p style={{
    fontSize: '1.25rem',
    color: 'var(--ifm-color-content-secondary)',
    maxWidth: '600px',
    marginBottom: '2rem'
  }}>
    We're building production-ready examples for AI agents on Amazon EKS. Check back soon!
  </p>

  <div style={{
    background: 'linear-gradient(135deg, rgba(59, 130, 246, 0.05), rgba(147, 51, 234, 0.05))',
    padding: '2rem',
    borderRadius: '16px',
    border: '2px solid rgba(59, 130, 246, 0.2)',
    maxWidth: '700px',
    textAlign: 'left'
  }}>
    <h3 style={{
      fontSize: '1.5rem',
      fontWeight: '700',
      marginBottom: '1rem',
      display: 'flex',
      alignItems: 'center',
      gap: '0.5rem'
    }}>
      <Cpu size={24} />
      Coming Soon
    </h3>

    <p style={{ marginBottom: '1rem', color: 'var(--ifm-color-content-secondary)' }}>
      Intelligent agents that automatically monitor, diagnose, and optimize your data workloads using AI.
    </p>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      Planned Examples:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li><strong>Spark Diagnostics Agent</strong> - AI-powered Spark job analyzer using LangGraph</li>
      <li><strong>Performance Optimization Agent</strong> - Automated query and configuration tuning</li>
      <li><strong>Anomaly Detection Agent</strong> - Real-time detection of unusual patterns</li>
      <li><strong>Cost Optimization Agent</strong> - ML-driven resource recommendations</li>
    </ul>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      Key Capabilities:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li>Automatic root cause analysis for job failures</li>
      <li>Intelligent configuration recommendations</li>
      <li>Predictive failure detection</li>
      <li>Self-healing data pipelines</li>
    </ul>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      Technology Stack:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li><strong>LangChain</strong> - Agent orchestration framework</li>
      <li><strong>LangGraph</strong> - Workflow state machines</li>
      <li><strong>Amazon Bedrock</strong> - Foundation models</li>
      <li><strong>Prometheus</strong> - Metrics collection</li>
    </ul>
  </div>
</div>
