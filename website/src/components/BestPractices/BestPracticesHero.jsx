import React from 'react';
import { Shield, CheckCircle, Lock, TrendingUp } from 'lucide-react';

export default function BestPracticesHero() {
  return (
    <div className="hero-section">
      <div className="hero-content">
        <h1 className="hero-title">
          <Shield size={56} className="inline-block mr-3" strokeWidth={2.5} />
          Data on EKS Best Practices
        </h1>
        <p className="hero-subtitle">
          Production-proven best practices for running data and ML workloads on Amazon EKS.
          Cluster configuration, resource management, security, monitoring, and optimization strategies.
        </p>

        <div className="hero-badges">
          <span className="badge">
            <CheckCircle size={18} className="inline-block mr-2" />
            Production Tested
          </span>
          <span className="badge">
            <Lock size={18} className="inline-block mr-2" />
            Security Hardened
          </span>
          <span className="badge">
            <TrendingUp size={18} className="inline-block mr-2" />
            Performance Optimized
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
