import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Translate from '@docusaurus/Translate';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import VideoGrid from '@site/src/components/VideoGrid/VideoGrid';
import styles from './index.module.css';

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();

  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container" style={{ textAlign: 'center' }}>
        <img
          src="img/light-logo.png"
          alt="Header image"
          className={styles.logoImage}
        />
        <p
          className='hero__subtitle'
          style={{
            fontSize: 18,
            fontSmooth: 'auto',
            animation: 'float 2s ease-in-out infinite'
          }}>
          {siteConfig.tagline}
        </p>
        <div className={styles.buttons}>
          <Link
            className={clsx("button button--lg", styles.buttonSpinUp)}
            to="/docs/introduction/intro">
            <Translate
              id="homepage.header.dataOnEks"
              description="Button text for Data on EKS">
              Data on EKS
            </Translate>
          </Link>
          <Link
            className={clsx("button button--lg", styles.buttonGenAI)}
            to="https://awslabs.github.io/ai-on-eks/">
            <Translate
              id="homepage.header.aiOnEks"
              description="Button text for AI on EKS">
              AI on EKS
            </Translate>
          </Link>
        </div>
      </div>
    </header>
  );
}

function DataOnEKSHeader() {
  return (
    <div className={styles.dataOnEKSHeader}>
      <h2>
        <Translate
          id="homepage.spotlight"
          description="Title for the spotlight section">
          In the Spotlight 🎥
        </Translate>
      </h2>
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
      <main>
        <div className="container">
          <HomepageFeatures />
          <DataOnEKSHeader />
          <VideoGrid />
        </div>
      </main>
    </Layout>
  );
}
