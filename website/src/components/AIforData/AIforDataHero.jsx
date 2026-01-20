import React from 'react';
import { Brain, Database, Cpu, Sparkles, TrendingUp, Zap } from 'lucide-react';

export default function AIforDataHero() {
  return (
    <div className="hero-section">
      <div className="hero-content">
        <h1 className="hero-title">
          <Brain size={56} className="inline-block mr-3" strokeWidth={2.5} />
          AI for Data
        </h1>
        <p className="hero-subtitle">
          Intelligent data systems powered by vector databases, AI agents, and modern ML infrastructure.
          Build next-generation data platforms with AI-native capabilities for semantic search, automated diagnostics,
          and intelligent data operations on Amazon EKS.
        </p>
        <div className="hero-badges">
          <span className="badge">
            <Database size={16} />
            Vector Databases
          </span>
          <span className="badge">
            <Cpu size={16} />
            AI Agents
          </span>
          <span className="badge">
            <Sparkles size={16} />
            Semantic Search
          </span>
          <span className="badge">
            <TrendingUp size={16} />
            Auto-Diagnostics
          </span>
          <span className="badge">
            <Zap size={16} />
            RAG Pipelines
          </span>
        </div>
      </div>
      <div className="hero-particles">
        {[...Array(20)].map((_, i) => (
          <div
            key={i}
            className="particle"
            style={{
              left: `${Math.random() * 100}%`,
              top: `${Math.random() * 100}%`,
              animationDelay: `${Math.random() * 3}s`,
              animationDuration: `${3 + Math.random() * 4}s`
            }}
          />
        ))}
      </div>
    </div>
  );
}
