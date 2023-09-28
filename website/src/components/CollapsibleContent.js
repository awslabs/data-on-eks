import React, { useState } from 'react';
import PropTypes from 'prop-types';
import clsx from 'clsx';
import styles from './CollapsibleContent.module.css';

function CollapsibleContent({ children, header }) {
  const [isExpanded, setIsExpanded] = useState(false);

  const toggleExpansion = () => {
    setIsExpanded(!isExpanded);
  };

  return (
    <div className={styles.collapsibleContent}>
      <div className={clsx(styles.header, { [styles.expanded]: isExpanded })} onClick={toggleExpansion}>
        {header}
        <span className={clsx(styles.icon, { [styles.expanded]: isExpanded })}>
          {isExpanded ? '👇' : '👈'}
        </span>
      </div>
      {isExpanded && <div className={styles.content}>{children}</div>}
    </div>
  );
}

CollapsibleContent.propTypes = {
  children: PropTypes.node.isRequired,
  header: PropTypes.node.isRequired,
};

export default CollapsibleContent;
