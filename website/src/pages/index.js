import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import VideoGrid from '@site/src/components/VideoGrid/VideoGrid';
import styles from './index.module.css';

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();

  return (
    <header className={clsx('hero', styles.heroBanner)}>
      <div className={styles.heroContainer}>
        {/* Main Logo Section */}
        <div className={styles.logoSection}>
          <img
            src="img/light-logo.png"
            alt="Data on EKS"
            className={styles.logoImage}
          />
        </div>

        {/* Hero Content */}
        <div className={styles.heroContent}>
          <p className={styles.heroSubtitle}>
            {siteConfig.tagline}
          </p>
          <p className={styles.heroDescription}>
            The comprehensive set of tools for running data workloads on Amazon EKS.
            <br />
            Build, deploy, and scale your data infrastructure with confidence.
          </p>
        </div>

        {/* CTA Buttons */}
        <div className={styles.ctaSection}>
          <Link
            className={clsx(styles.primaryButton)}
            to="/docs/blueprints/data-analytics">
            <span>Get Started</span>
            <svg className={styles.buttonIcon} width="20" height="20" viewBox="0 0 20 20" fill="none">
              <path d="M10.75 8.75L14.25 12.25L10.75 15.75" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
              <path d="M19.25 12.25H5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
            </svg>
          </Link>
          <Link
            className={clsx(styles.secondaryButton)}
            to="https://awslabs.github.io/ai-on-eks/">
            Explore AI on EKS
          </Link>
        </div>

        {/* Trust Indicators */}
        <div className={styles.trustIndicators}>
          <div className={styles.trustItem}>
            <span className={styles.trustNumber}>30+</span>
            <span className={styles.trustLabel}>Ready-to-use Blueprints</span>
          </div>
          <div className={styles.trustItem}>
            <span className={styles.trustNumber}>700+</span>
            <span className={styles.trustLabel}>GitHub Stars</span>
          </div>
          <div className={styles.trustItem}>
            <span className={styles.trustNumber}>AWS</span>
            <span className={styles.trustLabel}>Official Project</span>
          </div>
        </div>
      </div>

      {/* Background Elements */}
      <div className={styles.backgroundElements}>
        <div className={styles.bgCircle1}></div>
        <div className={styles.bgCircle2}></div>
        <div className={styles.bgCircle3}></div>
      </div>
    </header>
  );
}

function DataOnEKSHeader() {
  return (
    <div className={styles.dataOnEKSHeader}>
      <h2 className={styles.spotlightTitle}>Featured Videos</h2>
    </div>
  );
}

export default function Home() {
  const { siteConfig } = useDocusaurusContext();
  return (
    <Layout
      title={`Hello from ${siteConfig.title}`}
      description="Description will go into a meta tag in <head />">
      <HomepageHeader />
      <HomepageFeatures />
      <DataOnEKSHeader />
      <VideoGrid />
      <main>
        <div className="container">
        </div>
      </main>
    </Layout>
  );
}
