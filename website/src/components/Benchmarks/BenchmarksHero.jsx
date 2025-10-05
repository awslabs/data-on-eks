import React from 'react';
import { BarChart3, Zap, TrendingUp, Target } from 'lucide-react';

export default function BenchmarksHero() {
  return (
    <div className="hero-section">
      <div className="hero-content">
        <h1 className="hero-title">
          <BarChart3 size={56} className="inline-block mr-3" strokeWidth={2.5} />
          Performance Benchmarks
        </h1>
        <p className="hero-subtitle">
          Real-world performance testing results for data processing workloads on Amazon EKS.
          TPC-DS benchmarks, Graviton comparisons, and acceleration technologies.
        </p>

        <div className="hero-badges">
          <span className="badge">
            <Zap size={18} className="inline-block mr-2" />
            TPC-DS Standard
          </span>
          <span className="badge">
            <TrendingUp size={18} className="inline-block mr-2" />
            Real Datasets
          </span>
          <span className="badge">
            <Target size={18} className="inline-block mr-2" />
            Production Scale
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
