import React, { useEffect, useRef } from 'react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  Title,
  Tooltip,
  Legend
} from 'chart.js';
import './BarChart.css';

// Register Chart.js components required for a bar chart
ChartJS.register(
  CategoryScale,
  LinearScale,
  BarElement,
  Title,
  Tooltip,
  Legend
);

/**
 * Reusable Bar Chart component.
 *
 * @param {object} props - The component props.
 * @param {string} props.title - The title of the chart.
 * @param {object} props.data - The data for the chart (labels, datasets).
 * @param {object} [props.options] - Optional Chart.js options to override defaults.
 */
const BarChart = ({ title, data, options, height }) => {
  const chartRef = useRef(null);
  const chartInstance = useRef(null);

  useEffect(() => {
    // Destroy any existing chart instance before creating a new one
    if (chartInstance.current) {
      chartInstance.current.destroy();
    }

    if (chartRef.current) {
      const ctx = chartRef.current.getContext('2d');
      chartInstance.current = new ChartJS(ctx, {
        type: 'bar',
        data: data,
        options: {
          responsive: true,
          maintainAspectRatio: false, // Allows the chart to fill the container height
          plugins: {
            legend: {
              display: data.datasets.length > 1, // Only display legend if there are multiple datasets
              position: 'top',
            },
            title: {
              display: !!title, // Display title only if provided
              text: title,
              font: {
                size: 16,
              },
            },
          },
          scales: {
            y: {
              beginAtZero: true,
              title: {
                display: true,
                text: 'Value', // Default Y-axis title
              },
            },
            x: {
              title: {
                display: true,
                text: 'Category', // Default X-axis title
              },
            },
          },
          ...options, // Merge any provided options last to allow overriding defaults
        },
      });
    }

    // Cleanup function: destroy the chart instance when the component unmounts
    return () => {
      if (chartInstance.current) {
        chartInstance.current.destroy();
      }
    };
  }, [data, title, options]); // Re-run effect if data, title, or options change

  return (
    <div className="bar-chart-container" style={{ height: height || '400px' }}>
      <canvas ref={chartRef}></canvas>
    </div>
  );
};

export default BarChart;
