import React from 'react';
import styles from './WorkshopBanner.module.css';

const workshops = [
  {
    title: 'Analytics on EKS Workshop',
    description: 'Get hands-on with Amazon EKS and learn to run Apache Spark workloads at scale',
    badge: 'Instructor-led Workshop',
    href: 'https://events.eksworkshop.com/workshops/analytics/',
    tone: 'violet',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <path d="M13 2 4.5 13.5H11L10 22l8.5-11.5H12L13 2Z" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
      </svg>
    ),
  },
  {
    title: 'Spark AI Agent Workshop',
    description: 'Building an Intelligent Debugging and Optimization AI Agent for Apache Spark on EKS',
    badge: 'AI Agent Workshop',
    href: 'https://catalog.workshops.aws/generative-ai-on-aws/en-US/040-spark-ai-agents',
    tone: 'lime',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <rect x="4" y="7" width="16" height="13" rx="4" stroke="currentColor" strokeWidth="1.8" />
        <path d="M12 7V3.5M9 13h.01M15 13h.01M9.5 16.5h5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        <circle cx="12" cy="3" r="1.2" fill="currentColor" />
      </svg>
    ),
  },
];

const WorkshopBanner = () => (
  <section className={styles.workshops} aria-labelledby="workshops-heading">
    <div className={styles.inner}>
      <div className={styles.label}>
        <span className={styles.labelLine} />
        <h2 id="workshops-heading" className={styles.labelText}>Featured AWS Workshops</h2>
        <span className={styles.labelLine} />
      </div>

      <div className={styles.cards}>
        {workshops.map((w) => (
          <a
            key={w.title}
            href={w.href}
            target="_blank"
            rel="noopener noreferrer"
            className={`${styles.card} ${styles[w.tone]}`}
          >
            <div className={styles.icon}>{w.icon}</div>
            <div className={styles.content}>
              <span className={styles.badge}>{w.badge}</span>
              <h3 className={styles.title}>{w.title}</h3>
              <span className={styles.description}>{w.description}</span>
            </div>
            <span className={styles.arrow} aria-hidden="true">
              <svg viewBox="0 0 20 20" fill="none">
                <path d="M6 14 14 6M7.5 6H14v6.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          </a>
        ))}
      </div>
    </div>
  </section>
);

export default WorkshopBanner;
