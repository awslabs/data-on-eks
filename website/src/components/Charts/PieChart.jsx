import React, { useEffect, useRef } from 'react';
import {
  Chart as ChartJS,
  ArcElement,
  Title,
  Tooltip,
  Legend,
  DoughnutController,
  PieController
} from 'chart.js';
import './PieChart.css';

// Register Chart.js components required for a pie/doughnut chart
ChartJS.register(
  ArcElement,
  Title,
  Tooltip,
  Legend,
  DoughnutController,
  PieController
);

/**
 * Reusable Pie/Doughnut Chart component.
 *
 * @param {object} props - The component props.
 * @param {string} props.title - The title of the chart.
 * @param {object} props.data - The data for the chart (labels, datasets).
 * @param {string} [props.type='pie'] - The type of chart ('pie' or 'doughnut').
 * @param {object} [props.options] - Optional Chart.js options to override defaults.
 */
const PieChart = ({ title, data, type = 'pie', options }) => {
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
        type: type, // 'pie' or 'doughnut'
        data: data,
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              position: 'bottom',
            },
            title: {
              display: !!title,
              text: title,
              font: {
                size: 16,
              },
            },
          },
          ...options,
        },
      });
    }

    // Cleanup function: destroy the chart instance when the component unmounts
    return () => {
      if (chartInstance.current) {
        chartInstance.current.destroy();
      }
    };
  }, [data, title, type, options]);

  return (
    <div className="pie-chart-container">
      <canvas ref={chartRef}></canvas>
    </div>
  );
};

export default PieChart;
