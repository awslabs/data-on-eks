import React from 'react';
import styles from './WorkshopBanner.module.css';


const WorkshopBanner = () => {
 return (
   <div className={styles.workshopBanner}>
     {/* Moving Stars Background */}
     <div className={styles.starsContainer}>
       <div className={styles.star}></div>
       <div className={styles.star}></div>
       <div className={styles.star}></div>
       <div className={styles.star}></div>
       <div className={styles.star}></div>
       <div className={styles.star}></div>
       <div className={styles.star}></div>
       <div className={styles.star}></div>
       <div className={styles.star}></div>
       <div className={styles.star}></div>
     </div>


     <div className={styles.bannerContent}>
       <div className={styles.bannerTitle}>
         <span className={styles.titleIcon}>✨</span>
         Featured AWS Workshops
         <span className={styles.titleIcon}>✨</span>
       </div>

       <div className={styles.workshopCards}>
         <a
           href="https://events.eksworkshop.com/workshops/analytics/"
           target="_blank"
           rel="noopener noreferrer"
           className={styles.workshopCard}
         >
           <div className={styles.cardIcon}>⚡</div>
           <div className={styles.cardContent}>
             <h3 className={styles.cardTitle}>Analytics on EKS Workshop</h3>
             <p className={styles.cardDescription}>
               Get hands-on with Amazon EKS and learn to run Apache Spark workloads at scale
             </p>
             <div className={styles.cardBadge}>Instructor-led  Workshop</div>
           </div>
           <div className={styles.cardArrow}>→</div>
         </a>


         <a
           href="https://catalog.workshops.aws/generative-ai-on-aws/en-US/090-spark-ai-agents"
           target="_blank"
           rel="noopener noreferrer"
           className={styles.workshopCard}
         >
           <div className={styles.cardIcon}>🤖</div>
           <div className={styles.cardContent}>
             <h3 className={styles.cardTitle}>Spark AI Agent Workshop</h3>
             <p className={styles.cardDescription}>
               Building an Intelligent Debugging and Optimization AI Agent for Apache Spark on EKS
             </p>
             <div className={styles.cardBadge}>AI Agent Workshop</div>
           </div>
           <div className={styles.cardArrow}>→</div>
         </a>
       </div>
     </div>
   </div>
 );
};


export default WorkshopBanner;
