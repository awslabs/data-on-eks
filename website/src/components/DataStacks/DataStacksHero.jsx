import React from 'react';
import { Boxes, Rocket, GitBranch, Sparkles } from 'lucide-react';

export default function DataStacksHero() {
  return (
    <div className="hero-section">
      <div className="hero-content">
        <h1 className="hero-title">
          <Boxes size={56} className="inline-block mr-3" strokeWidth={2.5} />
          Production-Ready Data Stacks
        </h1>
        <p className="hero-subtitle">
          Curated data platform stacks for Amazon EKS with complete deployment guides,
          battle-tested configurations, and real-world examples from AWS customers.
        </p>

        <div className="hero-badges">
          <span className="badge">
            <Rocket size={18} className="inline-block mr-2" />
            Deploy in Minutes
          </span>
          <span className="badge">
            <GitBranch size={18} className="inline-block mr-2" />
            GitOps Ready
          </span>
          <span className="badge">
            <Sparkles size={18} className="inline-block mr-2" />
            Production Tested
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
