import React from 'react';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import VideoGrid from '@site/src/components/VideoGrid/VideoGrid';
import WorkshopBanner from '@site/src/components/WorkshopBanner/WorkshopBanner';
import styles from './index.module.css';

const ArrowIcon = () => (
  <svg className={styles.buttonIcon} width="18" height="18" viewBox="0 0 20 20" fill="none" aria-hidden="true">
    <path d="M4 10h11M11 5.5 15.5 10 11 14.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const deploySteps = ['VPC', 'EKS cluster', 'Karpenter', 'ArgoCD', 'Spark Operator'];

function DeployTerminal() {
  return (
    <div className={styles.terminal} aria-hidden="true">
      <div className={styles.terminalBar}>
        <span className={styles.dot} />
        <span className={styles.dot} />
        <span className={styles.dot} />
        <span className={styles.terminalTitle}>data-stacks/spark-on-eks</span>
      </div>
      <div className={styles.terminalBody}>
        <p className={styles.line} style={{ '--i': 0 }}>
          <span className={styles.prompt}>$</span> ./deploy.sh
        </p>
        {deploySteps.map((step, i) => (
          <p key={step} className={styles.line} style={{ '--i': i + 1 }}>
            <span className={styles.ok}>✓</span> {step}
            <span className={styles.leader} />
            <span className={styles.status}>ready</span>
          </p>
        ))}
        <p className={styles.line} style={{ '--i': deploySteps.length + 1 }}>
          <span className={styles.prompt}>$</span> kubectl get nodes
          <span className={styles.caret} />
        </p>
      </div>
    </div>
  );
}

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();
  const logoUrl = useBaseUrl('/img/light-logo.png');

  return (
    <header className={styles.hero}>
      <div className={styles.mesh} aria-hidden="true">
        <span className={styles.blob1} />
        <span className={styles.blob2} />
        <span className={styles.blob3} />
        <span className={styles.blob4} />
      </div>
      <div className={styles.gridLines} aria-hidden="true" />

      <div className={styles.heroInner}>
        <div className={styles.heroCopy}>
          {/* The logo PNG is used as a mask so it takes the site's gradient. */}
          <span
            className={styles.logoMark}
            role="img"
            aria-label="Data on EKS"
            style={{ '--logo-url': `url(${logoUrl})` }}
          />

          <p className={styles.eyebrow}>
            <span className={styles.pulse} />
            Open source · Data + AI agents
          </p>

          <h1 className={styles.title}>
            Data platforms on Amazon EKS,{' '}
            <em className={styles.titleAccent}>now agentic.</em>
          </h1>

          <p className={styles.tagline}>{siteConfig.tagline}</p>
          <p className={styles.lede}>
            The comprehensive set of tools for running data workloads on Amazon EKS,
            plus production-ready AI agents that investigate, diagnose, and optimize them.
            Build, deploy, and scale your data infrastructure with confidence.
          </p>

          <div className={styles.ctaRow}>
            <Link className={styles.primaryButton} to="/docs/getting-started">
              <span>Launch</span>
              <ArrowIcon />
            </Link>
            <Link className={styles.secondaryButton} to="https://awslabs.github.io/ai-on-eks/">
              Explore AI on EKS
            </Link>
          </div>

          <dl className={styles.stats}>
            <div className={styles.stat}>
              <dt className={styles.statLabel}>Ready-to-use Data Stacks</dt>
              <dd className={styles.statNumber}>30+</dd>
            </div>
            <div className={styles.stat}>
              <dt className={styles.statLabel}>GitHub Stars</dt>
              <dd className={styles.statNumber}>800+</dd>
            </div>
            <div className={styles.stat}>
              <dt className={styles.statLabel}>Official Project</dt>
              <dd className={styles.statNumber}>AWS</dd>
            </div>
          </dl>
        </div>

        <DeployTerminal />
      </div>
    </header>
  );
}

function VideosSection() {
  return (
    <section className={styles.videos}>
      <div className={styles.sectionHead}>
        <p className={styles.kicker}>Watch</p>
        <h2 className={styles.sectionTitle}>
          Featured <em>videos</em>
        </h2>
      </div>
      <VideoGrid />
    </section>
  );
}

function ClosingCta() {
  return (
    <section className={styles.closing}>
      <div className={styles.closingCard}>
        <h2 className={styles.closingTitle}>
          Ship your first data stack <em>today.</em>
        </h2>
        <p className={styles.closingText}>
          Terraform and ArgoCD blueprints for Spark, Flink, Kafka, Trino, Airflow and more, plus AI agents for your data.
        </p>
        <div className={styles.ctaRow}>
          <Link className={styles.primaryButton} to="/docs/getting-started">
            <span>Launch</span>
            <ArrowIcon />
          </Link>
          <Link className={styles.secondaryButton} to="https://github.com/awslabs/data-on-eks">
            Star on GitHub
          </Link>
        </div>
      </div>
    </section>
  );
}

export default function Home() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout
      title={`Hello from ${siteConfig.title}`}
      description="Open-source Terraform and ArgoCD blueprints for running scalable data platforms on Amazon EKS.">
      <main className={styles.page}>
        <HomepageHeader />
        <WorkshopBanner />
        <HomepageFeatures />
        <VideosSection />
        <ClosingCta />
      </main>
    </Layout>
  );
}
