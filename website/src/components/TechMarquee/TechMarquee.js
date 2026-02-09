import React from 'react';
import Link from '@docusaurus/Link';
import styles from './TechMarquee.module.css';

// Organized by Data Stack categories - matching the actual project structure
const technologies = [
  // PROCESSING
  {
    name: "Apache Spark",
    category: "Processing",
    gradient: "linear-gradient(135deg, #E25A1C 0%, #FFB84D 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="12" cy="12" r="3" fill="currentColor"/>
        <path d="M12 2L15 7L12 12L9 7L12 2Z" fill="currentColor" opacity="0.7"/>
        <path d="M12 22L15 17L12 12L9 17L12 22Z" fill="currentColor" opacity="0.7"/>
        <path d="M2 12L7 15L12 12L7 9L2 12Z" fill="currentColor" opacity="0.7"/>
        <path d="M22 12L17 15L12 12L17 9L22 12Z" fill="currentColor" opacity="0.7"/>
      </svg>
    )
  },
  {
    name: "Spark Operator",
    category: "Processing",
    gradient: "linear-gradient(135deg, #FCD34D 0%, #F59E0B 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="12" cy="12" r="2" fill="currentColor"/>
        <path d="M12 2L15 7L12 12L9 7L12 2Z" fill="currentColor" opacity="0.5"/>
        <path d="M12 22L15 17L12 12L9 17L12 22Z" fill="currentColor" opacity="0.5"/>
        <rect x="10" y="10" width="4" height="4" fill="currentColor"/>
      </svg>
    )
  },
  {
    name: "Amazon EMR on EKS",
    category: "Processing",
    gradient: "linear-gradient(135deg, #FF9900 0%, #FFBB00 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 2L2 7V17L12 22L22 17V7L12 2Z" stroke="currentColor" strokeWidth="2" fill="none"/>
        <path d="M12 12L2 7M12 12L22 7M12 12V22" stroke="currentColor" strokeWidth="2"/>
      </svg>
    )
  },
  {
    name: "Ray Data",
    category: "Processing",
    gradient: "linear-gradient(135deg, #2563EB 0%, #60A5FA 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="12" cy="12" r="2" fill="currentColor"/>
        <line x1="12" y1="12" x2="19" y2="5" stroke="currentColor" strokeWidth="2"/>
        <line x1="12" y1="12" x2="19" y2="19" stroke="currentColor" strokeWidth="2"/>
        <line x1="12" y1="12" x2="5" y2="12" stroke="currentColor" strokeWidth="2"/>
        <circle cx="19" cy="5" r="2" fill="currentColor"/>
        <circle cx="19" cy="19" r="2" fill="currentColor"/>
        <circle cx="5" cy="12" r="2" fill="currentColor"/>
      </svg>
    )
  },

  // STREAMING
  {
    name: "Apache Kafka",
    category: "Streaming",
    gradient: "linear-gradient(135deg, #231F20 0%, #666666 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="12" cy="12" r="8" stroke="currentColor" strokeWidth="2" fill="none"/>
        <circle cx="12" cy="12" r="4" fill="currentColor"/>
        <path d="M12 4V8M12 16V20M4 12H8M16 12H20" stroke="currentColor" strokeWidth="2"/>
      </svg>
    )
  },
  {
    name: "Apache Flink",
    category: "Streaming",
    gradient: "linear-gradient(135deg, #E6526F 0%, #FF8A9B 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M4 6L12 2L20 6V12L12 16L4 12V6Z" stroke="currentColor" strokeWidth="2" fill="none"/>
        <path d="M4 12L12 16L20 12L12 8L4 12Z" fill="currentColor" opacity="0.6"/>
        <path d="M12 16V22" stroke="currentColor" strokeWidth="2"/>
      </svg>
    )
  },
  {
    name: "Flink Operator",
    category: "Streaming",
    gradient: "linear-gradient(135deg, #F472B6 0%, #DB2777 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M4 8L12 4L20 8V14L12 18L4 14V8Z" stroke="currentColor" strokeWidth="1.5" fill="none"/>
        <rect x="10" y="10" width="4" height="4" fill="currentColor"/>
      </svg>
    )
  },

  // ORCHESTRATION
  {
    name: "Apache Airflow",
    category: "Orchestration",
    gradient: "linear-gradient(135deg, #017CEE 0%, #00C7D4 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M4 12H10M14 12H20M10 6H14M10 18H14" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
        <circle cx="10" cy="12" r="2" fill="currentColor"/>
        <circle cx="14" cy="12" r="2" fill="currentColor"/>
        <circle cx="10" cy="6" r="1.5" fill="currentColor"/>
        <circle cx="14" cy="6" r="1.5" fill="currentColor"/>
        <circle cx="10" cy="18" r="1.5" fill="currentColor"/>
        <circle cx="14" cy="18" r="1.5" fill="currentColor"/>
      </svg>
    )
  },
  {
    name: "Argo Workflows",
    category: "Orchestration",
    gradient: "linear-gradient(135deg, #EA580C 0%, #FDBA74 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 2L22 12L12 22L2 12L12 2Z" stroke="currentColor" strokeWidth="2" fill="none"/>
        <path d="M12 8L16 12L12 16L8 12L12 8Z" fill="currentColor"/>
      </svg>
    )
  },
  {
    name: "Amazon MWAA",
    category: "Orchestration",
    gradient: "linear-gradient(135deg, #FF9900 0%, #FF6B00 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M4 12H8M16 12H20M8 6H16M8 18H16" stroke="currentColor" strokeWidth="2"/>
        <circle cx="8" cy="12" r="2.5" fill="currentColor"/>
        <circle cx="16" cy="12" r="2.5" fill="currentColor"/>
      </svg>
    )
  },
  {
    name: "Kubeflow",
    category: "Orchestration",
    gradient: "linear-gradient(135deg, #326CE5 0%, #00BCD4 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 2L2 8V16L12 22L22 16V8L12 2Z" stroke="currentColor" strokeWidth="2" fill="none"/>
        <circle cx="12" cy="12" r="3" fill="currentColor"/>
      </svg>
    )
  },

  // DATABASES
  {
    name: "PostgreSQL",
    category: "Databases",
    gradient: "linear-gradient(135deg, #336791 0%, #5DA8DC 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 2C8 2 4 4 4 7V17C4 20 8 22 12 22C16 22 20 20 20 17V7C20 4 16 2 12 2Z" stroke="currentColor" strokeWidth="2" fill="none"/>
        <ellipse cx="12" cy="7" rx="8" ry="3" fill="currentColor" opacity="0.6"/>
      </svg>
    )
  },
  {
    name: "ClickHouse",
    category: "Databases",
    gradient: "linear-gradient(135deg, #FFCC01 0%, #F0A000 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M3 3H21V21H3V3Z" stroke="currentColor" strokeWidth="2" fill="none"/>
        <path d="M3 9H21M3 15H21M9 3V21M15 3V21" stroke="currentColor" strokeWidth="1.5"/>
      </svg>
    )
  },
  {
    name: "Apache Pinot",
    category: "Databases",
    gradient: "linear-gradient(135deg, #D9232E 0%, #F57C00 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="2" fill="none"/>
        <path d="M12 3V12L18 16" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
      </svg>
    )
  },

  // QUERY ENGINES
  {
    name: "Trino",
    category: "Query Engines",
    gradient: "linear-gradient(135deg, #DD00A1 0%, #F06292 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="4" y="4" width="16" height="16" rx="2" stroke="currentColor" strokeWidth="2" fill="none"/>
        <path d="M4 10H20M10 4V20" stroke="currentColor" strokeWidth="2"/>
        <circle cx="7" cy="7" r="1.5" fill="currentColor"/>
        <circle cx="13" cy="7" r="1.5" fill="currentColor"/>
        <circle cx="7" cy="13" r="1.5" fill="currentColor"/>
        <circle cx="13" cy="13" r="1.5" fill="currentColor"/>
      </svg>
    )
  },
  {
    name: "Presto",
    category: "Query Engines",
    gradient: "linear-gradient(135deg, #5890FF 0%, #8AB4F8 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M2 12L12 2L22 12L12 22L2 12Z" stroke="currentColor" strokeWidth="2" fill="none"/>
        <path d="M12 8L16 12L12 16L8 12L12 8Z" fill="currentColor"/>
      </svg>
    )
  },

  // BI & VISUALIZATION
  {
    name: "Apache Superset",
    category: "BI & Visualization",
    gradient: "linear-gradient(135deg, #20A7C9 0%, #63D9EA 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="3" y="14" width="4" height="7" fill="currentColor" opacity="0.6"/>
        <rect x="10" y="8" width="4" height="13" fill="currentColor" opacity="0.8"/>
        <rect x="17" y="3" width="4" height="18" fill="currentColor"/>
      </svg>
    )
  },
  {
    name: "Grafana",
    category: "BI & Visualization",
    gradient: "linear-gradient(135deg, #F46800 0%, #FFA500 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M3 12L7 8L11 14L15 6L19 10L21 8" stroke="currentColor" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
        <circle cx="7" cy="8" r="2" fill="currentColor"/>
        <circle cx="11" cy="14" r="2" fill="currentColor"/>
        <circle cx="15" cy="6" r="2" fill="currentColor"/>
      </svg>
    )
  },

  // NOTEBOOKS & AI
  {
    name: "JupyterHub",
    category: "Notebooks & AI",
    gradient: "linear-gradient(135deg, #F37726 0%, #FFA500 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="12" cy="7" r="4" fill="currentColor" opacity="0.6"/>
        <circle cx="7" cy="17" r="3" fill="currentColor" opacity="0.8"/>
        <circle cx="17" cy="17" r="3" fill="currentColor"/>
      </svg>
    )
  },
  {
    name: "Milvus",
    category: "Notebooks & AI",
    gradient: "linear-gradient(135deg, #00BFFF 0%, #1E90FF 100%)",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="4" y="4" width="16" height="16" rx="3" stroke="currentColor" strokeWidth="2" fill="none"/>
        <circle cx="12" cy="12" r="4" fill="currentColor" opacity="0.6"/>
        <path d="M12 4V8M12 16V20M4 12H8M16 12H20" stroke="currentColor" strokeWidth="2"/>
      </svg>
    )
  }
];

export default function TechMarquee() {
  return (
    <div className={styles.techShowcase}>
      <div className={styles.showcaseHeader}>
        <h2 className={styles.showcaseTitle}>Powered by Open Source & AWS</h2>
        <p className={styles.showcaseSubtitle}>
          Production-ready data stacks on Amazon EKS
        </p>
      </div>

      <div className={styles.techGrid}>
        {technologies.map((tech, index) => (
          <div key={index} className={styles.techCard}>
            <div className={styles.iconWrapper} style={{ background: tech.gradient }}>
              {tech.icon}
            </div>
            <div className={styles.techInfo}>
              <h3 className={styles.techName}>{tech.name}</h3>
              <span className={styles.techCategory}>{tech.category}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
