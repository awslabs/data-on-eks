---
title: 벡터 데이터베이스
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
    준비 중
  </h1>

  <div style={{
    fontSize: '1.25rem',
    color: 'var(--ifm-color-content-secondary)',
    maxWidth: '600px',
    marginBottom: '2rem'
  }}>
    Amazon EKS에서 벡터 데이터베이스를 위한 프로덕션 준비 예제를 구축하고 있습니다. 곧 다시 확인해 주세요!
  </div>

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
      곧 제공 예정
    </h3>

    <div style={{ marginBottom: '1rem', color: 'var(--ifm-color-content-secondary)' }}>
      AI 애플리케이션, 임베딩 및 시맨틱 데이터 검색을 위한 고성능 벡터 스토리지 및 유사성 검색.
    </div>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      계획된 스택:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li><strong>Milvus on EKS</strong> - 분산 벡터 데이터베이스 배포</li>
      <li><strong>pgvector</strong> - 벡터 유사성 검색을 위한 PostgreSQL 확장</li>
      <li><strong>Weaviate</strong> - 클라우드 네이티브 벡터 데이터베이스</li>
      <li><strong>Qdrant</strong> - 고성능 벡터 검색 엔진</li>
    </ul>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      사용 사례:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li>문서 및 데이터에 대한 시맨틱 검색</li>
      <li>추천 시스템</li>
      <li>이미지 및 비디오 유사성 검색</li>
      <li>검색 증강 생성(RAG) 파이프라인</li>
    </ul>
  </div>
</div>
