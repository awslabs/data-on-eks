---
title: 데이터용 AI 에이전트
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
    준비 중
  </h1>

  <div style={{
    fontSize: '1.25rem',
    color: 'var(--ifm-color-content-secondary)',
    maxWidth: '600px',
    marginBottom: '2rem'
  }}>
    Amazon EKS에서 AI 에이전트를 위한 프로덕션 준비 예제를 구축하고 있습니다. 곧 다시 확인해 주세요!
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
      <Cpu size={24} />
      곧 제공 예정
    </h3>

    <div style={{ marginBottom: '1rem', color: 'var(--ifm-color-content-secondary)' }}>
      AI를 사용하여 데이터 워크로드를 자동으로 모니터링, 진단 및 최적화하는 지능형 에이전트.
    </div>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      계획된 예제:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li><strong>Spark 진단 에이전트</strong> - LangGraph를 사용한 AI 기반 Spark 작업 분석기</li>
      <li><strong>성능 최적화 에이전트</strong> - 자동화된 쿼리 및 구성 튜닝</li>
      <li><strong>이상 탐지 에이전트</strong> - 비정상적인 패턴의 실시간 감지</li>
      <li><strong>비용 최적화 에이전트</strong> - ML 기반 리소스 권장 사항</li>
    </ul>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      주요 기능:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li>작업 실패에 대한 자동 근본 원인 분석</li>
      <li>지능형 구성 권장 사항</li>
      <li>예측 실패 감지</li>
      <li>자가 치유 데이터 파이프라인</li>
    </ul>

    <h4 style={{ fontSize: '1.1rem', fontWeight: '600', marginTop: '1.5rem', marginBottom: '0.75rem' }}>
      기술 스택:
    </h4>
    <ul style={{ color: 'var(--ifm-color-content-secondary)' }}>
      <li><strong>LangChain</strong> - 에이전트 오케스트레이션 프레임워크</li>
      <li><strong>LangGraph</strong> - 워크플로 상태 머신</li>
      <li><strong>Amazon Bedrock</strong> - 파운데이션 모델</li>
      <li><strong>Prometheus</strong> - 메트릭 수집</li>
    </ul>
  </div>
</div>
