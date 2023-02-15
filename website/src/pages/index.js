import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import styles from './index.module.css';

//TODO - fix code to get the correct theme to show the light-logo.png or dark-logo.png
function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  // const currentTheme = document.documentElement.getAttribute('data-theme');

  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container" style={{textAlign: 'center'}}>
        <img src="img/light-logo.png" alt="Header image" style={{width: '45%'}}/>
        {/*<img src={currentTheme === 'dark' ? 'img/dark-logo.png' : 'img/light-logo.png'} alt="Header image" style={{width: '45%'}}/>*/}
          {/*<main className={styles.main}>*/}
        {/*<h1 className="hero__title">{siteConfig.title}</h1>*/}
          {/*</main>*/}
          <p className='hero__subtitle' style={{fontSize: 18, fontSmooth: "auto", animation: "float 2s ease-in-out infinite"}}>{siteConfig.tagline}</p>
        <div className={styles.buttons}>
          <Link
            className="button button--secondary button--lg button-3d button-sparkles"
            style={{padding: '0.5rem 1.5rem', fontSize: '0.9rem'}}
            to="/docs/intro">
            Let's Spin Up
          </Link>
        </div>
      </div>
    </header>
  );
}

export default function Home() {
  const {siteConfig} = useDocusaurusContext();
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
