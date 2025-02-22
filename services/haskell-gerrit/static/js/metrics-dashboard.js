/**
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

// Initialize Chart.js instances for all charts
const charts = {};

// Configuration for different chart types
const chartConfigs = {
    activeConnections: {
        type: 'line',
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                y: { beginAtZero: true }
            }
        }
    },
    requestRate: {
        type: 'line',
        options: {
            responsive: true,
            maintainAspectRatio: false
        }
    },
    errorRate: {
        type: 'line',
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                y: {
                    beginAtZero: true,
                    max: 100,
                    ticks: {
                        callback: value => `${value}%`
                    }
                }
            }
        }
    },
    latencyHeatmap: {
        type: 'heatmap',
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'right'
                }
            }
        }
    }
};

// Initialize all charts when the page loads
document.addEventListener('DOMContentLoaded', () => {
    initializeCharts();
    setupEventListeners();
    fetchMetrics();
});

function initializeCharts() {
    const chartElements = document.querySelectorAll('.chart-container');
    chartElements.forEach(element => {
        const chartId = element.parentElement.id;
        const ctx = element.getContext('2d');
        const config = chartConfigs[chartId] || {
            type: 'line',
            options: {
                responsive: true,
                maintainAspectRatio: false
            }
        };

        charts[chartId] = new Chart(ctx, {
            ...config,
            data: {
                labels: [],
                datasets: [{
                    label: element.parentElement.querySelector('h4').textContent,
                    data: [],
                    borderColor: getRandomColor(),
                    fill: false
                }]
            }
        });
    });
}

function setupEventListeners() {
    // Time range selector
    document.querySelector('#timeRange').addEventListener('change', (e) => {
        fetchMetrics(e.target.value);
    });

    // Refresh button
    document.querySelector('#refreshMetrics').addEventListener('click', () => {
        const timeRange = document.querySelector('#timeRange').value;
        fetchMetrics(timeRange);
    });

    // Export buttons
    document.querySelector('#exportCSV').addEventListener('click', exportToCSV);
    document.querySelector('#exportJSON').addEventListener('click', exportToJSON);
    document.querySelector('#exportGrafana').addEventListener('click', openInGrafana);
}

async function fetchMetrics(timeRange = '5m') {
    try {
        const response = await fetch(`/api/metrics?timeRange=${timeRange}`);
        const data = await response.json();
        updateCharts(data);
        updateAlerts(data.alerts);
    } catch (error) {
        console.error('Error fetching metrics:', error);
        showError('Failed to fetch metrics data');
    }
}

function updateCharts(data) {
    Object.entries(data.metrics).forEach(([chartId, chartData]) => {
        if (charts[chartId]) {
            charts[chartId].data.labels = chartData.labels;
            charts[chartId].data.datasets[0].data = chartData.values;
            charts[chartId].update();
        }
    });
}

function updateAlerts(alerts) {
    const alertsContainer = document.querySelector('#activeAlerts');
    alertsContainer.innerHTML = alerts.map(alert => `
    <div class="alert ${alert.severity}">
      <strong>${alert.title}</strong>
      <p>${alert.message}</p>
      <span class="timestamp">${formatTimestamp(alert.timestamp)}</span>
    </div>
  `).join('');
}

function exportToCSV() {
    const timeRange = document.querySelector('#timeRange').value;
    window.location.href = `/api/metrics/export/csv?timeRange=${timeRange}`;
}

function exportToJSON() {
    const timeRange = document.querySelector('#timeRange').value;
    window.location.href = `/api/metrics/export/json?timeRange=${timeRange}`;
}

function openInGrafana() {
    window.open('/grafana/d/gerrit-metrics/gerrit-system-metrics', '_blank');
}

// Utility functions
function getRandomColor() {
    const letters = '0123456789ABCDEF';
    let color = '#';
    for (let i = 0; i < 6; i++) {
        color += letters[Math.floor(Math.random() * 16)];
    }
    return color;
}

function formatTimestamp(timestamp) {
    return new Date(timestamp).toLocaleString();
}

function showError(message) {
    // Add error notification implementation here
    console.error(message);
}

// Set up auto-refresh
setInterval(() => {
    const timeRange = document.querySelector('#timeRange').value;
    fetchMetrics(timeRange);
}, 60000); // Refresh every minute
