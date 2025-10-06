---
title: Vector Databases
sidebar_position: 2
---

import { Database, Construction } from 'lucide-react';

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
    We're building production-ready examples for vector databases on Amazon EKS. Check back soon!
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
      <Database size={24} />
      Coming Soon
    </h3>

    <p style={{ marginBottom: '1rem', color: 'var(--ifm-color-content-secondary)' }}>
      High-performance vector storage and similarity search for AI applications, embeddings, and semantic data retrieval.
    </p>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      Planned Stacks:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li><strong>Milvus on EKS</strong> - Distributed vector database deployment</li>
      <li><strong>pgvector</strong> - PostgreSQL extension for vector similarity search</li>
      <li><strong>Weaviate</strong> - Cloud-native vector database</li>
      <li><strong>Qdrant</strong> - High-performance vector search engine</li>
    </ul>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      Use Cases:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li>Semantic search across documents and data</li>
      <li>Recommendation systems</li>
      <li>Image and video similarity search</li>
      <li>Retrieval-Augmented Generation (RAG) pipelines</li>
    </ul>
  </div>
</div>
