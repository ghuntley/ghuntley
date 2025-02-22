/**
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

// Project Statistics and Graphs
$(document).ready(function () {
    // Load Chart.js and additional plugins
    const scripts = [
        'https://cdn.jsdelivr.net/npm/chart.js',
        'https://cdn.jsdelivr.net/npm/chartjs-plugin-zoom',
        'https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns',
        'https://cdn.jsdelivr.net/npm/file-saver',
        'https://cdn.jsdelivr.net/npm/jspdf',
        'https://cdn.jsdelivr.net/npm/jspdf-autotable',
        'https://cdn.jsdelivr.net/npm/xlsx',
        'https://cdn.jsdelivr.net/npm/chartjs-plugin-annotation',
        'https://cdn.jsdelivr.net/npm/chartjs-plugin-datalabels',
        'https://cdn.jsdelivr.net/npm/regression'
    ];

    Promise.all(scripts.map(src => loadScript(src))).then(initializeCharts);
});

function loadScript(src) {
    return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = src;
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
    });
}

function initializeCharts() {
    // Register plugins
    Chart.register(ChartZoomPlugin);
    Chart.register(ChartDataLabels);
    Chart.register(annotationPlugin);

    // Activity Graph with enhanced metrics
    const activityCtx = document.getElementById('activityGraph').getContext('2d');
    const activityChart = new Chart(activityCtx, {
        type: 'line',
        data: {
            labels: activityData.labels,
            datasets: [{
                label: 'Changes',
                data: activityData.changes,
                borderColor: 'rgb(75, 192, 192)',
                tension: 0.1
            }, {
                label: 'Reviews',
                data: activityData.reviews,
                borderColor: 'rgb(153, 102, 255)',
                tension: 0.1
            }, {
                label: 'Code Churn',
                data: activityData.codeChurn,
                borderColor: 'rgb(255, 99, 132)',
                tension: 0.1,
                hidden: true
            }, {
                label: 'Review Time',
                data: activityData.reviewTime,
                borderColor: 'rgb(255, 159, 64)',
                tension: 0.1,
                hidden: true
            }, {
                label: 'Complexity Score',
                data: activityData.complexity,
                borderColor: 'rgb(54, 162, 235)',
                tension: 0.1,
                hidden: true
            }, {
                label: 'Test Coverage',
                data: activityData.coverage,
                borderColor: 'rgb(255, 205, 86)',
                tension: 0.1,
                hidden: true
            }, {
                label: 'Review Depth',
                data: activityData.reviewDepth,
                borderColor: 'rgb(128, 0, 128)',
                tension: 0.1,
                hidden: true
            }, {
                label: 'Bug Rate',
                data: activityData.bugRate,
                borderColor: 'rgb(255, 0, 0)',
                tension: 0.1,
                hidden: true
            }]
        },
        options: {
            responsive: true,
            interaction: {
                mode: 'nearest',
                intersect: false
            },
            plugins: {
                title: {
                    display: true,
                    text: 'Project Activity'
                },
                zoom: {
                    zoom: {
                        wheel: { enabled: true },
                        pinch: { enabled: true },
                        mode: 'x',
                        drag: { enabled: true }
                    },
                    pan: { enabled: true }
                },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            const label = context.dataset.label;
                            const value = context.raw;
                            switch (label) {
                                case 'Code Churn':
                                    return `${label}: ${value} lines`;
                                case 'Review Time':
                                    return `${label}: ${formatDuration(value)}`;
                                case 'Complexity Score':
                                    return `${label}: ${value.toFixed(2)}`;
                                case 'Test Coverage':
                                    return `${label}: ${value}%`;
                                case 'Review Depth':
                                    return `${label}: ${value.toFixed(2)} comments/line`;
                                case 'Bug Rate':
                                    return `${label}: ${value.toFixed(2)}%`;
                                default:
                                    return `${label}: ${value}`;
                            }
                        }
                    }
                },
                annotation: {
                    annotations: {
                        releaseLines: activityData.releases.map(release => ({
                            type: 'line',
                            xMin: release.date,
                            xMax: release.date,
                            borderColor: 'rgba(0, 0, 0, 0.3)',
                            borderWidth: 2,
                            label: {
                                content: `Release ${release.version}`,
                                enabled: true,
                                position: 'top'
                            }
                        }))
                    }
                },
                datalabels: {
                    display: 'auto',
                    align: 'top',
                    formatter: (value, context) => {
                        if (context.datasetIndex === 0 && value > activityData.averageChanges * 2) {
                            return '🔥'; // Highlight high activity
                        }
                        return null;
                    }
                }
            },
            scales: {
                x: {
                    type: 'time',
                    time: {
                        unit: 'day'
                    }
                },
                y: {
                    beginAtZero: true
                }
            }
        }
    });

    // Contributors Graph with detailed metrics
    const contributorsCtx = document.getElementById('contributorsGraph').getContext('2d');
    const contributorsChart = new Chart(contributorsCtx, {
        type: 'bar',
        data: {
            labels: contributorsData.labels,
            datasets: [{
                label: 'Commits',
                data: contributorsData.commits,
                backgroundColor: 'rgba(75, 192, 192, 0.5)',
                borderColor: 'rgb(75, 192, 192)',
                borderWidth: 1
            }, {
                label: 'Reviews',
                data: contributorsData.reviews,
                backgroundColor: 'rgba(153, 102, 255, 0.5)',
                borderColor: 'rgb(153, 102, 255)',
                borderWidth: 1
            }, {
                label: 'Lines Changed',
                data: contributorsData.linesChanged,
                backgroundColor: 'rgba(255, 99, 132, 0.5)',
                borderColor: 'rgb(255, 99, 132)',
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            plugins: {
                title: {
                    display: true,
                    text: 'Contributor Activity'
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    stacked: true
                }
            }
        }
    });

    // Code Quality Metrics
    const qualityCtx = document.getElementById('qualityGraph').getContext('2d');
    const qualityChart = new Chart(qualityCtx, {
        type: 'radar',
        data: {
            labels: ['Code Coverage', 'Review Coverage', 'Documentation', 'Test Quality', 'Code Style'],
            datasets: [{
                label: 'Current',
                data: qualityData.current,
                fill: true,
                backgroundColor: 'rgba(75, 192, 192, 0.2)',
                borderColor: 'rgb(75, 192, 192)',
                pointBackgroundColor: 'rgb(75, 192, 192)',
                pointBorderColor: '#fff',
                pointHoverBackgroundColor: '#fff',
                pointHoverBorderColor: 'rgb(75, 192, 192)'
            }, {
                label: 'Previous',
                data: qualityData.previous,
                fill: true,
                backgroundColor: 'rgba(255, 99, 132, 0.2)',
                borderColor: 'rgb(255, 99, 132)',
                pointBackgroundColor: 'rgb(255, 99, 132)',
                pointBorderColor: '#fff',
                pointHoverBackgroundColor: '#fff',
                pointHoverBorderColor: 'rgb(255, 99, 132)'
            }]
        },
        options: {
            elements: {
                line: { borderWidth: 3 }
            }
        }
    });

    // Velocity Trend Chart (New)
    const velocityCtx = document.getElementById('velocityGraph').getContext('2d');
    const velocityChart = new Chart(velocityCtx, {
        type: 'bubble',
        data: {
            datasets: [{
                label: 'Changes',
                data: activityData.velocity.map(v => ({
                    x: v.date,
                    y: v.changes,
                    r: v.complexity * 5
                })),
                backgroundColor: 'rgba(75, 192, 192, 0.5)'
            }]
        },
        options: {
            responsive: true,
            plugins: {
                title: {
                    display: true,
                    text: 'Development Velocity'
                },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            return `Changes: ${context.raw.y}, Complexity: ${(context.raw.r / 5).toFixed(2)}`;
                        }
                    }
                }
            },
            scales: {
                x: {
                    type: 'time',
                    time: { unit: 'day' }
                },
                y: {
                    beginAtZero: true,
                    title: {
                        display: true,
                        text: 'Number of Changes'
                    }
                }
            }
        }
    });

    // New: Review Impact Chart
    const reviewImpactCtx = document.getElementById('reviewImpactGraph').getContext('2d');
    const reviewImpactChart = new Chart(reviewImpactCtx, {
        type: 'scatter',
        data: {
            datasets: [{
                label: 'Changes',
                data: activityData.reviewImpact.map(r => ({
                    x: r.reviewTime,
                    y: r.defectRate
                })),
                backgroundColor: 'rgba(75, 192, 192, 0.5)'
            }]
        },
        options: {
            responsive: true,
            plugins: {
                title: {
                    display: true,
                    text: 'Review Time vs Defect Rate'
                },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            return `Review Time: ${formatDuration(context.raw.x)}, Defect Rate: ${context.raw.y.toFixed(2)}%`;
                        }
                    }
                }
            },
            scales: {
                x: {
                    title: {
                        display: true,
                        text: 'Review Time'
                    },
                    ticks: {
                        callback: value => formatDuration(value)
                    }
                },
                y: {
                    title: {
                        display: true,
                        text: 'Defect Rate (%)'
                    }
                }
            }
        }
    });

    // Update statistics periodically
    setInterval(updateStatistics, 300000); // Update every 5 minutes
    setupInteractiveFeatures();
    setupExportButtons();
}

function setupInteractiveFeatures() {
    // Time range selector
    $('#timeRange').on('change', function () {
        const range = $(this).val();
        updateTimeRange(range);
    });

    // Metric toggles
    $('.metric-toggle').on('change', function () {
        const metric = $(this).val();
        const chart = Chart.getChart('activityGraph');
        const dataset = chart.data.datasets.find(d => d.label === metric);
        dataset.hidden = !dataset.hidden;
        chart.update();
    });

    // Add trend line toggle
    $('#showTrendline').on('change', function () {
        const chart = Chart.getChart('activityGraph');
        chart.options.plugins.annotation.annotations.trendline.enabled = $(this).is(':checked');
        chart.update();
    });

    // Add comparison mode
    $('#enableComparison').on('change', function () {
        const enabled = $(this).is(':checked');
        if (enabled) {
            loadComparisonData();
        } else {
            removeComparisonData();
        }
    });

    // Add regression analysis
    $('#showRegression').on('change', function () {
        const enabled = $(this).is(':checked');
        const chart = Chart.getChart('reviewImpactGraph');
        if (enabled) {
            const points = chart.data.datasets[0].data.map(d => [d.x, d.y]);
            const result = regression.linear(points);

            chart.data.datasets[1] = {
                label: 'Trend',
                data: result.points.map(p => ({ x: p[0], y: p[1] })),
                type: 'line',
                borderColor: 'rgba(255, 99, 132, 0.8)',
                fill: false
            };
        } else {
            chart.data.datasets = chart.data.datasets.slice(0, 1);
        }
        chart.update();
    });

    // Add heatmap toggle
    $('#showHeatmap').on('change', function () {
        const enabled = $(this).is(':checked');
        updateHeatmap(enabled);
    });

    // Add custom date range picker
    $('#customDateRange').daterangepicker({
        ranges: {
            'Last 7 Days': [moment().subtract(6, 'days'), moment()],
            'Last 30 Days': [moment().subtract(29, 'days'), moment()],
            'This Month': [moment().startOf('month'), moment().endOf('month')],
            'Last Quarter': [moment().subtract(3, 'months'), moment()]
        }
    }, function (start, end) {
        updateDateRange(start, end);
    });
}

function setupExportButtons() {
    $('#exportCSV').click(() => exportData('csv'));
    $('#exportJSON').click(() => exportData('json'));
    $('#exportPDF').click(() => exportData('pdf'));
    $('#exportExcel').click(() => exportData('excel'));
    $('#exportSVG').click(() => exportData('svg'));
}

function exportData(format) {
    const data = {
        activity: activityData,
        contributors: contributorsData,
        quality: qualityData,
        velocity: activityData.velocity,
        summary: {
            totalChanges: $('#totalChanges').text(),
            totalReviews: $('#totalReviews').text(),
            openChanges: $('#openChanges').text(),
            mergedChanges: $('#mergedChanges').text(),
            abandonedChanges: $('#abandonedChanges').text(),
            averageReviewTime: $('#averageReviewTime').text(),
            complexityTrend: $('#complexityTrend').text(),
            testCoverage: $('#testCoverage').text(),
            velocityScore: $('#velocityScore').text(),
            technicalDebt: $('#technicalDebt').text()
        }
    };

    switch (format) {
        case 'csv':
            exportCSV(data);
            break;
        case 'json':
            exportJSON(data);
            break;
        case 'pdf':
            exportPDF(data);
            break;
        case 'excel':
            exportExcel(data);
            break;
        case 'svg':
            exportSVG();
            break;
    }
}

function exportCSV(data) {
    let csv = 'Date,Changes,Reviews,Code Churn,Review Time\n';
    data.activity.labels.forEach((date, i) => {
        csv += `${date},${data.activity.changes[i]},${data.activity.reviews[i]},${data.activity.codeChurn[i]},${data.activity.reviewTime[i]}\n`;
    });
    saveFile(csv, 'project-statistics.csv', 'text/csv');
}

function exportJSON(data) {
    const json = JSON.stringify(data, null, 2);
    saveFile(json, 'project-statistics.json', 'application/json');
}

function exportPDF(data) {
    const doc = new jsPDF();
    const pageWidth = doc.internal.pageSize.width;

    // Title
    doc.setFontSize(20);
    doc.text('Project Statistics Report', pageWidth / 2, 20, { align: 'center' });

    // Summary Statistics
    doc.setFontSize(16);
    doc.text('Summary', 14, 40);

    doc.setFontSize(12);
    doc.autoTable({
        startY: 45,
        head: [['Metric', 'Value']],
        body: [
            ['Total Changes', data.summary.totalChanges],
            ['Open Changes', data.summary.openChanges],
            ['Merged Changes', data.summary.mergedChanges],
            ['Total Reviews', data.summary.totalReviews],
            ['Average Review Time', data.summary.averageReviewTime],
            ['Code Coverage', data.summary.testCoverage],
            ['Technical Debt', data.summary.technicalDebt]
        ]
    });

    // Activity Graph
    doc.addPage();
    doc.setFontSize(16);
    doc.text('Activity Overview', 14, 20);

    const activityChart = Chart.getChart('activityGraph');
    const activityImage = activityChart.toBase64Image();
    doc.addImage(activityImage, 'PNG', 10, 30, 190, 100);

    // Quality Metrics
    doc.addPage();
    doc.text('Quality Metrics', 14, 20);

    const qualityChart = Chart.getChart('qualityGraph');
    const qualityImage = qualityChart.toBase64Image();
    doc.addImage(qualityImage, 'PNG', 10, 30, 190, 100);

    // Contributors
    doc.addPage();
    doc.text('Contributor Analytics', 14, 20);

    doc.autoTable({
        startY: 30,
        head: [['Contributor', 'Commits', 'Reviews', 'Lines Changed', 'Merge Rate']],
        body: data.contributors.map(c => [
            c.name,
            c.commits,
            c.reviews,
            c.linesChanged,
            `${(c.mergeRatio * 100).toFixed(1)}%`
        ])
    });

    // Save the PDF
    doc.save('project-statistics.pdf');
}

function exportExcel(data) {
    const wb = XLSX.utils.book_new();

    // Activity Sheet
    const activityWS = XLSX.utils.json_to_sheet(data.activity.labels.map((date, i) => ({
        Date: date,
        Changes: data.activity.changes[i],
        Reviews: data.activity.reviews[i],
        'Code Churn': data.activity.codeChurn[i],
        'Review Time': data.activity.reviewTime[i],
        Complexity: data.activity.complexity[i],
        Coverage: data.activity.coverage[i]
    })));
    XLSX.utils.book_append_sheet(wb, activityWS, 'Activity');

    // Contributors Sheet
    const contributorsWS = XLSX.utils.json_to_sheet(data.contributors);
    XLSX.utils.book_append_sheet(wb, contributorsWS, 'Contributors');

    // Quality Metrics Sheet
    const qualityWS = XLSX.utils.json_to_sheet([
        data.quality.current,
        data.quality.previous
    ]);
    XLSX.utils.book_append_sheet(wb, qualityWS, 'Quality Metrics');

    XLSX.writeFile(wb, 'project-statistics.xlsx');
}

function exportSVG() {
    const charts = ['activityGraph', 'contributorsGraph', 'qualityGraph', 'velocityGraph'];
    charts.forEach(chartId => {
        const chart = Chart.getChart(chartId);
        if (chart) {
            const url = chart.toBase64Image('image/svg+xml');
            const link = document.createElement('a');
            link.download = `${chartId}.svg`;
            link.href = url;
            link.click();
        }
    });
}

function updateTimeRange(range) {
    const now = new Date();
    let startDate;

    switch (range) {
        case 'week':
            startDate = new Date(now - 7 * 24 * 60 * 60 * 1000);
            break;
        case 'month':
            startDate = new Date(now.setMonth(now.getMonth() - 1));
            break;
        case 'quarter':
            startDate = new Date(now.setMonth(now.getMonth() - 3));
            break;
        case 'year':
            startDate = new Date(now.setFullYear(now.getFullYear() - 1));
            break;
    }

    const charts = ['activityGraph', 'velocityGraph'];
    charts.forEach(chartId => {
        const chart = Chart.getChart(chartId);
        if (chart) {
            chart.options.scales.x.min = startDate;
            chart.options.scales.x.max = now;
            chart.update();
        }
    });
}

// Statistics table updates with enhanced metrics
function updateStatsTable(data) {
    $('#totalChanges').text(data.totalChanges);
    $('#totalReviews').text(data.totalReviews);
    $('#openChanges').text(data.openChanges);
    $('#mergedChanges').text(data.mergedChanges);
    $('#abandonedChanges').text(data.abandonedChanges);
    $('#averageReviewTime').text(formatDuration(data.averageReviewTime));
    $('#codeChurnRate').text(`${data.codeChurnRate} lines/day`);
    $('#reviewThroughput').text(`${data.reviewThroughput} reviews/day`);
    $('#mergeRatio').text(`${(data.mergeRatio * 100).toFixed(1)}%`);
    $('#averageComments').text(data.averageComments.toFixed(1));
}

// Contributor analytics
function updateContributorAnalytics(data) {
    const tbody = $('#contributorStats tbody');
    tbody.empty();

    data.contributors.forEach(contributor => {
        tbody.append(`
            <tr>
                <td>${contributor.name}</td>
                <td>${contributor.commits}</td>
                <td>${contributor.reviews}</td>
                <td>${contributor.linesChanged}</td>
                <td>${formatDuration(contributor.averageReviewTime)}</td>
                <td>${(contributor.mergeRatio * 100).toFixed(1)}%</td>
                <td>${contributor.averageComments.toFixed(1)}</td>
            </tr>
        `);
    });
}

// Utility functions
function formatDuration(minutes) {
    if (minutes < 60) {
        return `${minutes}m`;
    } else if (minutes < 1440) {
        return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
    } else {
        const days = Math.floor(minutes / 1440);
        const hours = Math.floor((minutes % 1440) / 60);
        return `${days}d ${hours}h`;
    }
}

// New: Heatmap visualization
function updateHeatmap(enabled) {
    const chart = Chart.getChart('activityGraph');
    if (enabled) {
        chart.data.datasets.forEach(dataset => {
            if (!dataset.hidden) {
                dataset.backgroundColor = function (context) {
                    const value = context.raw;
                    const max = Math.max(...dataset.data);
                    const alpha = value / max;
                    return `rgba(75, 192, 192, ${alpha})`;
                };
            }
        });
    } else {
        chart.data.datasets.forEach(dataset => {
            dataset.backgroundColor = undefined;
        });
    }
    chart.update();
}

// New: Custom date range update
function updateDateRange(start, end) {
    const charts = ['activityGraph', 'velocityGraph', 'reviewImpactGraph'];
    charts.forEach(chartId => {
        const chart = Chart.getChart(chartId);
        if (chart) {
            chart.options.scales.x.min = start.toDate();
            chart.options.scales.x.max = end.toDate();
            chart.update();
        }
    });
}
