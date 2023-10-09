import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import styles from './index.module.css';

function HomepageHeader() {
  const { siteConfig } = useDocusaurusContext();

  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container" style={{ textAlign: 'center' }}>
        <img
          src="img/light-logo.png"
          alt="Header image"
          className={styles.logoImage} // Add this line
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
            className="button button--secondary button--lg button-3d button-sparkles"
            style={{ padding: '0.5rem 1.5rem', fontSize: '1.0rem' }}
            to="/docs/introduction/intro">
            Let's Spin Up
          </Link>
        </div>
      </div>
    </header>
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
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
