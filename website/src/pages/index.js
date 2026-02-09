import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Translate, {translate} from '@docusaurus/Translate';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import VideoGrid from '@site/src/components/VideoGrid/VideoGrid';
import WorkshopBanner from '@site/src/components/WorkshopBanner/WorkshopBanner';
import styles from './index.module.css';


function HomepageHeader() {
 const { siteConfig, i18n } = useDocusaurusContext();
 const aiOnEksUrl = i18n.currentLocale === 'ko'
   ? 'https://atom-oh.github.io/ai-on-eks/ko'
   : 'https://atom-oh.github.io/ai-on-eks/';

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
           <Translate id="homepage.tagline">{siteConfig.tagline}</Translate>
         </p>
         <p className={styles.heroDescription}>
           <Translate id="homepage.description">The comprehensive set of tools for running data workloads on Amazon EKS.</Translate>
           <br />
           <Translate id="homepage.description2">Build, deploy, and scale your data infrastructure with confidence.</Translate>
         </p>
       </div>


       {/* CTA Buttons */}
       <div className={styles.ctaSection}>
         <Link
           className={clsx(styles.primaryButton)}
           to="/docs/getting-started">
           <span><Translate id="homepage.cta.launch">Launch</Translate></span>
           <svg className={styles.buttonIcon} width="20" height="20" viewBox="0 0 20 20" fill="none">
             <path d="M10.75 8.75L14.25 12.25L10.75 15.75" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
             <path d="M19.25 12.25H5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
           </svg>
         </Link>
         <Link
           className={clsx(styles.secondaryButton)}
           to={aiOnEksUrl}>
           <Translate id="homepage.cta.explore">Explore AI on EKS</Translate>
         </Link>
       </div>


       {/* Trust Indicators */}
       <div className={styles.trustIndicators}>
         <div className={styles.trustItem}>
           <span className={styles.trustNumber}>30+</span>
           <span className={styles.trustLabel}><Translate id="homepage.trust.datastacks">Ready-to-use Data Stacks</Translate></span>
         </div>
         <div className={styles.trustItem}>
           <span className={styles.trustNumber}>800+</span>
           <span className={styles.trustLabel}><Translate id="homepage.trust.stars">GitHub Stars</Translate></span>
         </div>
         <div className={styles.trustItem}>
           <span className={styles.trustNumber}>AWS</span>
           <span className={styles.trustLabel}><Translate id="homepage.trust.official">Official Project</Translate></span>
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
     <h2 className={styles.spotlightTitle}><Translate id="homepage.videos.title">Featured Videos</Translate></h2>
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
     <WorkshopBanner />
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
