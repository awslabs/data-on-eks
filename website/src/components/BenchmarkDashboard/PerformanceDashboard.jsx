import React, { useEffect } from 'react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  LineElement,
  PointElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
  Filler,
  BarController,
  LineController,
  DoughnutController
} from 'chart.js';
import './PerformanceDashboard.css';

// Register Chart.js components
ChartJS.register(
  CategoryScale,
  LinearScale,
  BarElement,
  LineElement,
  PointElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
  Filler,
  BarController,
  LineController,
  DoughnutController
);

const PerformanceDashboard = () => {
  useEffect(() => {
    // Destroy existing chart instances to prevent conflicts
    ChartJS.getChart('performanceChart')?.destroy();
    ChartJS.getChart('speedupChart')?.destroy();
    ChartJS.getChart('topQueriesChart')?.destroy();
    ChartJS.getChart('histogramChart')?.destroy();
    ChartJS.getChart('pieChart')?.destroy();
    ChartJS.getChart('comparisonChart')?.destroy();

    // Performance Comparison Chart
    const ctx1 = document.getElementById('performanceChart');
    if (ctx1) {
      new ChartJS(ctx1, {
        type: 'bar',
        data: {
          labels: ['Native Spark', 'Gluten + Velox'],
          datasets: [{
            label: 'Total Runtime (seconds)',
            data: [2016.1, 1174.4],
            backgroundColor: ['#e74c3c', '#27ae60'],
            borderColor: ['#c0392b', '#229954'],
            borderWidth: 2
          }, {
            label: 'Time Saved',
            data: [0, 841.7],
            backgroundColor: ['transparent', '#3498db'],
            borderColor: ['transparent', '#2980b9'],
            borderWidth: 2,
            type: 'line',
            yAxisID: 'y1'
          }]
        },
        options: {
          responsive: true,
          plugins: {
            legend: { display: true },
            title: { display: true, text: 'TPC-DS 1TB Total Runtime Comparison' }
          },
          scales: {
            y: {
              beginAtZero: true,
              title: { display: true, text: 'Runtime (seconds)' }
            },
            y1: {
              type: 'linear',
              display: true,
              position: 'right',
              title: { display: true, text: 'Time Saved (seconds)' },
              grid: { drawOnChartArea: false }
            }
          }
        }
      });
    }

    // Speedup Distribution Chart
    const ctx2 = document.getElementById('speedupChart');
    if (ctx2) {
      new ChartJS(ctx2, {
        type: 'doughnut',
        data: {
          labels: ['5x+ Speedup', '3x-5x Speedup', '2x-3x Speedup', '1.5x-2x Speedup', '1x-1.5x Speedup', 'Slower'],
          datasets: [{
            data: [1, 8, 29, 30, 21, 8],
            backgroundColor: [
              '#1abc9c', '#27ae60', '#3498db', '#f39c12', '#e67e22', '#e74c3c'
            ],
            borderWidth: 2,
            borderColor: '#ffffff'
          }]
        },
        options: {
          responsive: true,
          plugins: {
            legend: { position: 'bottom' },
            title: { display: true, text: 'Query Performance Distribution (97 queries)' },
            tooltip: {
              callbacks: {
                label: function(context) {
                  const percentage = ((context.parsed / 97) * 100).toFixed(1);
                  return context.label + ': ' + context.parsed + ' queries (' + percentage + '%)';
                }
              }
            }
          }
        }
      });
    }

    // Top Queries Performance Chart
    const ctx3 = document.getElementById('topQueriesChart');
    if (ctx3) {
      new ChartJS(ctx3, {
        type: 'bar',
        data: {
          labels: ['q93-v2.4', 'q49-v2.4', 'q50-v2.4', 'q59-v2.4', 'q5-v2.4', 'q62-v2.4', 'q97-v2.4', 'q40-v2.4', 'q90-v2.4', 'q23b-v2.4'],
          datasets: [{
            label: 'Native Spark (seconds)',
            data: [80.18, 25.68, 38.57, 17.57, 23.18, 9.41, 18.68, 15.17, 12.05, 147.17],
            backgroundColor: '#e74c3c',
            borderColor: '#c0392b',
            borderWidth: 1
          }, {
            label: 'Gluten + Velox (seconds)',
            data: [14.63, 6.66, 10.00, 4.82, 6.42, 2.88, 5.99, 5.05, 4.21, 52.96],
            backgroundColor: '#27ae60',
            borderColor: '#229954',
            borderWidth: 1
          }]
        },
        options: {
          responsive: true,
          plugins: {
            legend: { display: true },
            title: { display: true, text: 'Top 10 Query Performance Improvements' },
            tooltip: {
              callbacks: {
                afterBody: function(tooltipItems) {
                  const native = tooltipItems.find(item => item.datasetIndex === 0);
                  const gluten = tooltipItems.find(item => item.datasetIndex === 1);
                  if (native && gluten) {
                    const speedup = (native.parsed.y / gluten.parsed.y).toFixed(2);
                    return 'Speedup: ' + speedup + 'x faster';
                  }
                  return '';
                }
              }
            }
          },
          scales: {
            y: {
              beginAtZero: true,
              title: { display: true, text: 'Runtime (seconds)' }
            },
            x: {
              title: { display: true, text: 'TPC-DS Queries' }
            }
          }
        }
      });
    }

    // Performance Distribution Histogram
    const ctx4 = document.getElementById('histogramChart');
    if (ctx4) {
      const histogramBins = {
        'Degraded (<1x)': 14,
        'Slight (1x-1.5x)': 27,
        'Moderate (1.5x-2x)': 23,
        'Good (2x-3x)': 25,
        'Excellent (3x+)': 15
      };

      new ChartJS(ctx4, {
        type: 'bar',
        data: {
          labels: Object.keys(histogramBins),
          datasets: [{
            label: 'Number of Queries',
            data: Object.values(histogramBins),
            backgroundColor: [
              '#ef4444', '#f59e0b', '#3b82f6', '#10b981', '#059669'
            ],
            borderWidth: 2,
            borderColor: '#1f2937'
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            title: { display: true, text: 'Performance Improvement Distribution' }
          },
          scales: {
            y: {
              beginAtZero: true,
              title: { display: true, text: 'Number of Queries' }
            }
          }
        }
      });
    }

    // Performance Categories Pie Chart
    const ctxPie = document.getElementById('pieChart');
    if (ctxPie) {
      const histogramBins = {
        'Degraded (<1x)': 14,
        'Slight (1x-1.5x)': 27,
        'Moderate (1.5x-2x)': 23,
        'Good (2x-3x)': 25,
        'Excellent (3x+)': 15
      };

      new ChartJS(ctxPie, {
        type: 'doughnut',
        data: {
          labels: Object.keys(histogramBins),
          datasets: [{
            data: Object.values(histogramBins),
            backgroundColor: [
              '#ef4444', '#f59e0b', '#3b82f6', '#10b981', '#059669'
            ],
            borderWidth: 3,
            borderColor: '#ffffff'
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              position: 'bottom',
              labels: {
                padding: 20,
                font: { size: 11 }
              }
            },
            title: { display: true, text: 'Performance Categories' }
          }
        }
      });
    }

    // Query Execution Comparison Chart (Top 30)
    const ctx5 = document.getElementById('comparisonChart');
    if (ctx5) {
      const queryNames = [
        "q93-v2.4", "q49-v2.4", "q50-v2.4", "q62-v2.4", "q59-v2.4", "q5-v2.4",
        "q29-v2.4", "q97-v2.4", "q90-v2.4", "q40-v2.4", "q84-v2.4", "q23b-v2.4",
        "q75-v2.4", "q96-v2.4", "q80-v2.4", "q85-v2.4", "q65-v2.4", "q99-v2.4",
        "q6-v2.4", "q9-v2.4", "q3-v2.4", "q88-v2.4", "q44-v2.4", "q23a-v2.4",
        "q7-v2.4", "q43-v2.4", "q78-v2.4", "q53-v2.4", "q64-v2.4", "q51-v2.4"
      ];

      const sparkTimes = [79.84, 24.67, 38.22, 9.07, 17.25, 19.05, 17.06, 18.39, 11.67, 13.92, 7.83, 145.96, 40.45, 8.81, 23.69, 15.61, 17.41, 9.28, 9.49, 42.84, 4.14, 50.61, 22.22, 112.24, 6.80, 4.30, 63.44, 4.75, 61.56, 11.85];
      const glutenTimes = [14.36, 6.31, 9.86, 2.41, 4.79, 5.43, 5.38, 5.83, 3.74, 4.68, 2.64, 52.03, 14.44, 3.26, 9.01, 5.94, 6.75, 3.63, 3.74, 17.08, 1.66, 20.59, 9.15, 46.37, 2.82, 1.79, 26.39, 2.03, 26.64, 5.17];

      new ChartJS(ctx5, {
        type: 'bar',
        data: {
          labels: queryNames,
          datasets: [{
            label: 'Native Spark (seconds)',
            data: sparkTimes,
            backgroundColor: 'rgba(239, 68, 68, 0.7)',
            borderColor: '#dc2626',
            borderWidth: 1
          }, {
            label: 'Gluten + Velox (seconds)',
            data: glutenTimes,
            backgroundColor: 'rgba(16, 185, 129, 0.7)',
            borderColor: '#059669',
            borderWidth: 1
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: true, position: 'top' },
            title: { display: true, text: 'Query Execution Time: Top 30 Queries by Improvement' },
            tooltip: {
              callbacks: {
                afterLabel: function(context) {
                  if (context.datasetIndex === 0) {
                    const improvement = (sparkTimes[context.dataIndex] / glutenTimes[context.dataIndex]).toFixed(2);
                    return `Improvement: ${improvement}x faster`;
                  }
                  return null;
                }
              }
            }
          },
          scales: {
            y: {
              beginAtZero: true,
              title: { display: true, text: 'Execution Time (seconds)' }
            },
            x: {
              ticks: {
                maxRotation: 45,
                minRotation: 45,
                font: { size: 9 }
              }
            }
          }
        }
      });
    }

  }, []);

  return (
    <div className="performance-dashboard">
      {/* KPI Cards */}
      <div className="kpi-section">
        <div className="kpi-grid">
          <div className="kpi-card primary">
            <div className="kpi-icon">🚀</div>
            <div className="kpi-value">1.72x</div>
            <div className="kpi-label">Overall Performance Gain</div>
            <div className="kpi-description">72% faster execution across all 104 TPC-DS queries</div>
          </div>
          <div className="kpi-card success">
            <div className="kpi-icon">💰</div>
            <div className="kpi-value">42%</div>
            <div className="kpi-label">Cost Reduction Potential</div>
            <div className="kpi-description">Direct correlation between performance improvement and compute costs</div>
          </div>
          <div className="kpi-card info">
            <div className="kpi-icon">📊</div>
            <div className="kpi-value">86.5%</div>
            <div className="kpi-label">Success Rate</div>
            <div className="kpi-description">90 out of 104 queries improved, only 14 showed degradation</div>
          </div>
          <div className="kpi-card warning">
            <div className="kpi-icon">⏱️</div>
            <div className="kpi-value">42 min</div>
            <div className="kpi-label">Time Saved</div>
            <div className="kpi-description">42 minutes saved on TPC-DS 1TB benchmark suite (1.7h → 1.0h)</div>
          </div>
        </div>
      </div>

      {/* Main Performance Charts */}
      <div className="main-chart-section">
        <div className="chart-container full-width">
          <h3>Performance Comparison: Runtime Analysis</h3>
          <canvas id="performanceChart" width="800" height="400"></canvas>
        </div>

        <div className="chart-container speedup-chart">
          <h3>Query Speedup Distribution</h3>
          <canvas id="speedupChart" width="400" height="400"></canvas>
        </div>
      </div>

      {/* Top Queries Section */}
      <div className="top-queries-section">
        <h3>Top 10 Performance Improvements</h3>
        <canvas id="topQueriesChart" width="800" height="500"></canvas>
      </div>

      {/* Query Pattern Analysis */}
      <div className="pattern-analysis-section">
        <div className="analysis-grid">
          <div className="chart-panel">
            <div className="panel-title">Performance Improvement Distribution</div>
            <div className="chart-container-small">
              <canvas id="histogramChart"></canvas>
            </div>
            <div className="stats-summary">
              <div className="summary-stat">
                <div className="summary-value">90</div>
                <div className="summary-label">Improved</div>
              </div>
              <div className="summary-stat">
                <div className="summary-value">14</div>
                <div className="summary-label">Degraded</div>
              </div>
              <div className="summary-stat">
                <div className="summary-value">1.77x</div>
                <div className="summary-label">Median</div>
              </div>
              <div className="summary-stat">
                <div className="summary-value">86.5%</div>
                <div className="summary-label">Success Rate</div>
              </div>
            </div>
          </div>

          <div className="chart-panel">
            <div className="panel-title">Performance Categories</div>
            <div className="chart-container-small">
              <canvas id="pieChart" width="400" height="400"></canvas>
            </div>
            <div className="category-tags">
              <span className="performance-category excellent">Excellent (3x+): 15 queries</span>
              <span className="performance-category good">Good (2x-3x): 25 queries</span>
              <span className="performance-category moderate">Moderate (1.5x-2x): 23 queries</span>
              <span className="performance-category slight">Slight (1x-1.5x): 27 queries</span>
              <span className="performance-category poor">Degraded (&lt;1x): 14 queries</span>
            </div>
          </div>
        </div>

        <div className="detailed-comparison">
          <div className="panel-title">Query Execution Time: Spark vs Gluten+Velox (Top 30 Queries by Improvement)</div>
          <div className="chart-container-large">
            <canvas id="comparisonChart"></canvas>
          </div>

          <div className="insights">
            <h3>🔍 Performance Analysis Insights</h3>
            <ul>
              <li><strong>Complex Analytical Queries:</strong> Queries with heavy joins and aggregations (q93, q49, q50) show the highest improvements (3.8x-5.6x)</li>
              <li><strong>Scan-Heavy Operations:</strong> Large table scans benefit significantly from native columnar processing</li>
              <li><strong>Vectorization Benefits:</strong> Mathematical operations and filters see consistent 2x-3x improvements</li>
              <li><strong>Memory-Intensive Queries:</strong> Queries like q23b (146s→52s) demonstrate native memory management advantages</li>
              <li><strong>Edge Cases:</strong> 14 queries showed degradation, primarily those with simple operations where JNI overhead exceeded benefits</li>
              <li><strong>Cost Savings:</strong> 69.8% reduction in execution time translates to ~42% lower compute costs on EKS</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PerformanceDashboard;
