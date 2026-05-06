import React from 'react';
import { Brain, Database, Activity, Bot } from 'lucide-react';

export default function AIforDataHero() {
  return (
    <div className="hero-section">
      <div className="hero-content">
        <h1 className="hero-title">
          <Brain size={56} className="inline-block mr-3" strokeWidth={2.5} />
          AI for Data
        </h1>
        <p className="hero-subtitle">
          Production-ready reference architectures for AI agents that autonomously monitor,
          investigate, and act on data platforms and data workloads.
        </p>

        <div className="hero-badges">
          <span className="badge">
            <Bot size={18} className="inline-block mr-2" />
            Agentic Workflows
          </span>
          <span className="badge">
            <Database size={18} className="inline-block mr-2" />
            Data Platforms
          </span>
          <span className="badge">
            <Activity size={18} className="inline-block mr-2" />
            Real-time Investigation
          </span>
        </div>
      </div>

      {/* Floating particles background */}
      <div className="hero-particles">
        {[...Array(15)].map((_, i) => (
          <div
            key={i}
            className="particle"
            style={{
              left: `${Math.random() * 100}%`,
              top: `${Math.random() * 100}%`,
              animationDelay: `${Math.random() * 5}s`,
              animationDuration: `${5 + Math.random() * 10}s`
            }}
          />
        ))}
      </div>
    </div>
  );
}
