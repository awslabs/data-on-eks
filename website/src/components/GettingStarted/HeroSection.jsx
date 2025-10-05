import React from 'react';
import { Zap, Rocket, Target, Lock, DollarSign, BarChart3, Cloud, BookOpen, ArrowRight } from 'lucide-react';

export default function HeroSection() {
  return (
    <div className="hero-section">
      <div className="hero-content">
        <h1 className="hero-title">
          <Zap size={56} className="inline-block mr-3" strokeWidth={2.5} />
          Build Production-Grade Data Platforms in Minutes
        </h1>
        <p className="hero-subtitle">
          Deploy enterprise-scale data infrastructure on Amazon EKS with CNCF-native patterns,
          battle-tested configurations, and day-1 operational readiness.
        </p>

        <div className="hero-badges">
          <span className="badge">
            <Target size={18} className="inline-block mr-2" />
            Opinionated
          </span>
          <span className="badge">
            <Lock size={18} className="inline-block mr-2" />
            Secure by Default
          </span>
          <span className="badge">
            <DollarSign size={18} className="inline-block mr-2" />
            Cost-Optimized
          </span>
          <span className="badge">
            <BarChart3 size={18} className="inline-block mr-2" />
            Observable
          </span>
          <span className="badge">
            <Cloud size={18} className="inline-block mr-2" />
            CNCF-Native
          </span>
        </div>

        <div className="hero-cta">
          <a href="#quick-start" className="cta-button cta-primary">
            <Rocket size={20} />
            <span>Deploy in 15 Minutes</span>
            <ArrowRight size={20} />
          </a>
          <a href="/data-on-eks/docs/datastacks/" className="cta-button cta-secondary">
            <BookOpen size={20} />
            <span>Explore Data Stacks</span>
            <ArrowRight size={20} />
          </a>
        </div>
      </div>

      {/* Floating particles background */}
      <div className="hero-particles">
        {[...Array(20)].map((_, i) => (
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

      <style jsx>{`
        .hero-particles {
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          overflow: hidden;
          z-index: 1;
          pointer-events: none;
        }

        .particle {
          position: absolute;
          width: 4px;
          height: 4px;
          background: rgba(255, 255, 255, 0.5);
          border-radius: 50%;
          animation: float-particle linear infinite;
        }

        @keyframes float-particle {
          0% {
            transform: translateY(0) translateX(0);
            opacity: 0;
          }
          10% {
            opacity: 1;
          }
          90% {
            opacity: 1;
          }
          100% {
            transform: translateY(-100vh) translateX(50px);
            opacity: 0;
          }
        }
      `}</style>
    </div>
  );
}
