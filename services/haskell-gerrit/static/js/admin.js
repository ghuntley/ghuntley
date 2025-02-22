/**
 * Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

// Admin Dashboard JavaScript

// System Health
function updateSystemHealth() {
    fetch('/api/admin/system/health')
        .then(response => response.json())
        .then(data => {
            // Update health status indicators
            document.querySelector('.health-status').innerHTML = renderHealthStatus(data);
        });
}

function renderHealthStatus(health) {
    return `
        <div class="status-item">
            <span class="label">Overall Status:</span>
            <span class="value ${health.status === 'healthy' ? 'status-ok' : 'status-error'}">
                ${health.status}
            </span>
        </div>
        ${health.checks.map(check => `
            <div class="check-item">
                <span class="label">${check.name}:</span>
                <span class="value ${check.status ? 'status-ok' : 'status-error'}">
                    ${check.status ? 'OK' : 'Error'}
                </span>
            </div>
        `).join('')}
    `;
}

// System Metrics
function updateSystemMetrics() {
    fetch('/api/admin/system/metrics')
        .then(response => response.json())
        .then(data => {
            // Update metric gauges
            updateGauge('cpu-usage', data.cpuUsage);
            updateGauge('memory-usage', data.memoryUsage);
            updateGauge('disk-usage', data.diskUsage);
            updateNetworkStats(data.networkStats);
        });
}

function updateGauge(id, value) {
    const gauge = document.querySelector(`#${id} .gauge-fill`);
    gauge.style.width = `${value}%`;
}

function updateNetworkStats(stats) {
    const container = document.querySelector('.network-stats');
    container.innerHTML = stats.map(stat => `
        <div class="stat-item">
            <span class="label">${stat.name}:</span>
            <span class="value">${formatBytes(stat.value)}</span>
        </div>
    `).join('');
}

// User Management
function createUser() {
    const userData = {
        // Get form data
    };

    fetch('/api/admin/users', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(userData)
    })
        .then(response => response.json())
        .then(() => {
            refreshUsers();
        });
}

function editUser(userId) {
    // Show edit user modal
}

function deleteUser(userId) {
    if (confirm('Are you sure you want to delete this user?')) {
        fetch(`/api/admin/users/${userId}`, {
            method: 'DELETE'
        })
            .then(() => {
                refreshUsers();
            });
    }
}

function refreshUsers() {
    fetch('/api/admin/users')
        .then(response => response.json())
        .then(data => {
            // Update user list
            document.querySelector('.user-list tbody').innerHTML = renderUsers(data);
        });
}

// Resource Management
function clearCache() {
    fetch('/api/admin/resources/cache/clear', {
        method: 'POST'
    })
        .then(() => {
            updateResourceUsage();
        });
}

function runCleanup() {
    fetch('/api/admin/resources/cleanup', {
        method: 'POST'
    })
        .then(() => {
            updateResourceUsage();
        });
}

function updateResourceUsage() {
    fetch('/api/admin/resources/usage')
        .then(response => response.json())
        .then(data => {
            // Update resource usage displays
            updateStorageUsage(data.storage);
            updateDatabaseUsage(data.database);
            updateCacheUsage(data.cache);
            updateJobsList(data.jobs);
        });
}

// Security Management
function editPolicy(policyType) {
    // Show policy editor modal
}

function createApiKey() {
    // Show create API key modal
}

function revokeKey(keyId) {
    if (confirm('Are you sure you want to revoke this API key?')) {
        fetch(`/api/admin/security/api-keys/${keyId}`, {
            method: 'DELETE'
        })
            .then(() => {
                refreshApiKeys();
            });
    }
}

function editRateLimits() {
    // Show rate limits editor modal
}

function editAllowlist() {
    // Show IP allowlist editor modal
}

// Enterprise Management
function saveEnterpriseSettings() {
    const settings = {
        // Get form data
    };

    fetch('/api/admin/enterprises/settings', {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(settings)
    });
}

function updateLicense() {
    // Show license update modal
}

function editQuotas() {
    // Show quota editor modal
}

function updateAnalytics() {
    const range = document.querySelector('.date-range select').value;
    fetch(`/api/admin/enterprises/analytics?range=${range}`)
        .then(response => response.json())
        .then(data => {
            renderCharts(data);
        });
}

function generateReport(type) {
    fetch(`/api/admin/enterprises/reports/${type}`, {
        method: 'POST'
    })
        .then(response => response.json())
        .then(data => {
            // Handle report generation
        });
}

// Configuration Management
function toggleFeature(featureName) {
    const isEnabled = document.querySelector(`#feature-${featureName}`).checked;
    fetch('/api/admin/config/features', {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            name: featureName,
            enabled: isEnabled
        })
    });
}

function updateEnvVar(name) {
    const value = document.querySelector(`#env-${name}`).value;
    fetch('/api/admin/config/env', {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            name,
            value
        })
    });
}

function editService(serviceName) {
    // Show service config editor modal
    const modal = new bootstrap.Modal(document.getElementById('serviceConfigModal'));
    fetch(`/api/admin/config/services/${serviceName}`)
        .then(response => response.json())
        .then(data => {
            document.querySelector('#serviceConfigEditor').value = JSON.stringify(data.config, null, 2);
            document.querySelector('#serviceConfigForm').dataset.serviceName = serviceName;
            modal.show();
        });
}

function saveServiceConfig() {
    const serviceName = document.querySelector('#serviceConfigForm').dataset.serviceName;
    const config = JSON.parse(document.querySelector('#serviceConfigEditor').value);

    fetch(`/api/admin/config/services/${serviceName}`, {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ config })
    })
        .then(() => {
            const modal = bootstrap.Modal.getInstance(document.getElementById('serviceConfigModal'));
            modal.hide();
            refreshServiceConfigs();
        });
}

function editTemplate(templateName) {
    // Show email template editor modal
    const modal = new bootstrap.Modal(document.getElementById('templateEditorModal'));
    fetch(`/api/admin/config/email-templates/${templateName}`)
        .then(response => response.json())
        .then(data => {
            document.querySelector('#templateSubject').value = data.subject;
            document.querySelector('#templateBody').value = data.body;
            document.querySelector('#templateForm').dataset.templateName = templateName;
            modal.show();
        });
}

function saveTemplate() {
    const templateName = document.querySelector('#templateForm').dataset.templateName;
    const subject = document.querySelector('#templateSubject').value;
    const body = document.querySelector('#templateBody').value;

    fetch(`/api/admin/config/email-templates/${templateName}`, {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ subject, body })
    })
        .then(() => {
            const modal = bootstrap.Modal.getInstance(document.getElementById('templateEditorModal'));
            modal.hide();
            refreshEmailTemplates();
        });
}

function toggleWebhook(webhookUrl) {
    const isActive = document.querySelector(`[data-webhook="${webhookUrl}"]`).checked;
    fetch(`/api/admin/config/webhooks/${encodeURIComponent(webhookUrl)}`, {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ isActive })
    });
}

function editWebhook(webhookUrl) {
    // Show webhook editor modal
    const modal = new bootstrap.Modal(document.getElementById('webhookEditorModal'));
    fetch(`/api/admin/config/webhooks/${encodeURIComponent(webhookUrl)}`)
        .then(response => response.json())
        .then(data => {
            document.querySelector('#webhookUrl').value = data.webhookUrl;
            document.querySelector('#webhookEvents').value = data.events.join('\n');
            document.querySelector('#webhookHeaders').value = JSON.stringify(data.headers, null, 2);
            document.querySelector('#webhookForm').dataset.webhookUrl = webhookUrl;
            modal.show();
        });
}

function saveWebhook() {
    const webhookUrl = document.querySelector('#webhookForm').dataset.webhookUrl;
    const url = document.querySelector('#webhookUrl').value;
    const events = document.querySelector('#webhookEvents').value.split('\n').filter(e => e.trim());
    const headers = JSON.parse(document.querySelector('#webhookHeaders').value);

    fetch(`/api/admin/config/webhooks/${encodeURIComponent(webhookUrl)}`, {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ webhookUrl: url, events, headers })
    })
        .then(() => {
            const modal = bootstrap.Modal.getInstance(document.getElementById('webhookEditorModal'));
            modal.hide();
            refreshWebhooks();
        });
}

function deleteWebhook(webhookUrl) {
    if (confirm('Are you sure you want to delete this webhook?')) {
        fetch(`/api/admin/config/webhooks/${encodeURIComponent(webhookUrl)}`, {
            method: 'DELETE'
        })
            .then(() => {
                refreshWebhooks();
            });
    }
}

function exportConfig() {
    fetch('/api/admin/config')
        .then(response => response.json())
        .then(data => {
            const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'gerrit-config.json';
            a.click();
            window.URL.revokeObjectURL(url);
        });
}

function importConfig() {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'application/json';
    input.onchange = (e) => {
        const file = e.target.files[0];
        const reader = new FileReader();
        reader.onload = (event) => {
            const config = JSON.parse(event.target.result);
            if (confirm('Are you sure you want to import this configuration? This will overwrite your current settings.')) {
                fetch('/api/admin/config', {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(config)
                })
                    .then(() => {
                        window.location.reload();
                    });
            }
        };
        reader.readAsText(file);
    };
    input.click();
}

function resetConfig() {
    if (confirm('Are you sure you want to reset all configuration to default values? This cannot be undone.')) {
        fetch('/api/admin/config/reset', {
            method: 'POST'
        })
            .then(() => {
                window.location.reload();
            });
    }
}

function refreshServiceConfigs() {
    fetch('/api/admin/config/services')
        .then(response => response.json())
        .then(data => {
            // Update service list
            const serviceList = document.querySelector('.service-list');
            if (serviceList) {
                serviceList.innerHTML = data.map(service => `
                    <div class="service-item">
                        <div class="service-header">
                            <span class="name">${service.serviceName}</span>
                            <span class="version">v${service.version}</span>
                            <button class="btn btn-sm btn-primary" onclick="editService('${service.serviceName}')">
                                Edit
                            </button>
                        </div>
                        <div class="service-type">Type: ${service.serviceType}</div>
                        <div class="service-config">
                            <pre>${JSON.stringify(service.config, null, 2)}</pre>
                        </div>
                    </div>
                `).join('');
            }
        });
}

function refreshEmailTemplates() {
    fetch('/api/admin/config/email-templates')
        .then(response => response.json())
        .then(data => {
            // Update template list
            const templateList = document.querySelector('.template-list');
            if (templateList) {
                templateList.innerHTML = data.map(template => `
                    <div class="template-item">
                        <div class="template-header">
                            <span class="name">${template.templateName}</span>
                            <button class="btn btn-sm btn-primary" onclick="editTemplate('${template.templateName}')">
                                Edit
                            </button>
                        </div>
                        <div class="template-subject">Subject: ${template.subject}</div>
                        <div class="template-variables">
                            <h4>Variables:</h4>
                            <div class="variable-list">
                                ${template.variables.map(v => `
                                    <span class="badge bg-secondary">${v}</span>
                                `).join('')}
                            </div>
                        </div>
                    </div>
                `).join('');
            }
        });
}

function refreshWebhooks() {
    fetch('/api/admin/config/webhooks')
        .then(response => response.json())
        .then(data => {
            const webhookList = document.querySelector('.webhook-list');
            if (webhookList) {
                webhookList.innerHTML = `
                    <button class="btn btn-primary mb-3" onclick="showNewWebhookModal()">
                        <i class="fas fa-plus"></i> Create Webhook
                    </button>
                    ${data.map(webhook => `
                        <div class="webhook-item">
                            <div class="webhook-header">
                                <span class="name">${webhook.webhookUrl}</span>
                                <div class="form-check form-switch">
                                    <input class="form-check-input" type="checkbox"
                                        ${webhook.isActive ? 'checked' : ''}
                                        data-webhook="${webhook.webhookUrl}"
                                        onchange="toggleWebhook('${webhook.webhookUrl}')">
                                </div>
                            </div>
                            <div class="webhook-events">
                                <h4>Events:</h4>
                                <div class="event-list">
                                    ${webhook.events.map(e => `
                                        <span class="badge bg-primary">${e}</span>
                                    `).join('')}
                                </div>
                            </div>
                            <div class="webhook-headers">
                                <h4>Headers:</h4>
                                <div class="header-list">
                                    ${Object.entries(webhook.headers).map(([key, value]) => `
                                        <div class="header-item">
                                            <span class="key">${key}:</span>
                                            <span class="value">${value}</span>
                                        </div>
                                    `).join('')}
                                </div>
                            </div>
                            <div class="webhook-actions">
                                <button class="btn btn-sm btn-info" onclick="testWebhook('${webhook.webhookUrl}')">
                                    <i class="fas fa-play"></i> Test
                                </button>
                                <button class="btn btn-sm btn-primary" onclick="editWebhook('${webhook.webhookUrl}')">
                                    <i class="fas fa-edit"></i> Edit
                                </button>
                                <button class="btn btn-sm btn-danger" onclick="deleteWebhook('${webhook.webhookUrl}')">
                                    <i class="fas fa-trash"></i> Delete
                                </button>
                            </div>
                        </div>
                    `).join('')}
                `;
            }
        });
}

// Maintenance Tools
function runDatabaseMaintenance() {
    fetch('/api/admin/maintenance/database', {
        method: 'POST'
    })
        .then(() => {
            updateMaintenanceStatus();
        });
}

function clearAllCaches() {
    fetch('/api/admin/maintenance/cache', {
        method: 'POST'
    })
        .then(() => {
            updateMaintenanceStatus();
        });
}

function cleanupStorage() {
    fetch('/api/admin/maintenance/storage', {
        method: 'POST'
    })
        .then(() => {
            updateMaintenanceStatus();
        });
}

function rotateLogs() {
    fetch('/api/admin/maintenance/logs', {
        method: 'POST'
    })
        .then(() => {
            updateMaintenanceStatus();
        });
}

function rebuildSearchIndex() {
    fetch('/api/admin/maintenance/index', {
        method: 'POST'
    })
        .then(() => {
            updateMaintenanceStatus();
        });
}

function migrateData() {
    fetch('/api/admin/maintenance/migrate', {
        method: 'POST'
    })
        .then(() => {
            updateMaintenanceStatus();
        });
}

// Utility Functions
function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatTime(timestamp) {
    return new Date(timestamp).toLocaleString();
}

function formatDuration(ms) {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    return hours > 0 ? `${hours}h ${minutes % 60}m` : `${minutes}m ${seconds % 60}s`;
}

// Initialize Dashboard
document.addEventListener('DOMContentLoaded', () => {
    // Initial updates
    updateSystemHealth();
    updateSystemMetrics();
    updateResourceUsage();
    refreshUsers();
    updateAnalytics();

    // Set up periodic updates
    setInterval(updateSystemHealth, 60000); // Every minute
    setInterval(updateSystemMetrics, 30000); // Every 30 seconds
    setInterval(updateResourceUsage, 60000); // Every minute

    // Set up event listeners
    setupEventListeners();
});

function setupEventListeners() {
    // Add event listeners for interactive elements
    document.querySelectorAll('.feature-toggle').forEach(toggle => {
        toggle.addEventListener('change', (e) => {
            toggleFeature(e.target.dataset.feature);
        });
    });

    document.querySelectorAll('.env-input').forEach(input => {
        input.addEventListener('change', (e) => {
            updateEnvVar(e.target.dataset.name);
        });
    });

    // Configuration Management event listeners
    document.querySelectorAll('.feature-toggle').forEach(toggle => {
        toggle.addEventListener('change', (e) => {
            toggleFeature(e.target.dataset.feature);
        });
    });

    document.querySelectorAll('.env-input').forEach(input => {
        input.addEventListener('change', (e) => {
            updateEnvVar(e.target.dataset.name);
        });
    });

    // Service Config Modal
    const serviceConfigForm = document.querySelector('#serviceConfigForm');
    if (serviceConfigForm) {
        serviceConfigForm.addEventListener('submit', (e) => {
            e.preventDefault();
            saveServiceConfig();
        });
    }

    // Email Template Modal
    const templateForm = document.querySelector('#templateForm');
    if (templateForm) {
        templateForm.addEventListener('submit', (e) => {
            e.preventDefault();
            saveTemplate();
        });
    }

    // Webhook Modal
    const webhookForm = document.querySelector('#webhookForm');
    if (webhookForm) {
        webhookForm.addEventListener('submit', (e) => {
            e.preventDefault();
            saveWebhook();
        });
    }

    // Webhook Management
    const webhookNewForm = document.querySelector('#webhookNewForm');
    if (webhookNewForm) {
        webhookNewForm.addEventListener('submit', createWebhook);
    }

    // Add "Create Webhook" button to webhook list
    const webhookList = document.querySelector('.webhook-list');
    if (webhookList) {
        const createButton = document.createElement('button');
        createButton.className = 'btn btn-primary mb-3';
        createButton.innerHTML = '<i class="fas fa-plus"></i> Create Webhook';
        createButton.onclick = showNewWebhookModal;
        webhookList.insertBefore(createButton, webhookList.firstChild);
    }
}

// Initialize Configuration Management
document.addEventListener('DOMContentLoaded', () => {
    // ... existing code ...

    // Initial configuration updates
    refreshServiceConfigs();
    refreshEmailTemplates();
    refreshWebhooks();
});

// Webhook Management
function showNewWebhookModal() {
    const modal = new bootstrap.Modal(document.getElementById('webhookNewModal'));
    modal.show();
}

function addHeader() {
    const headerEditor = document.querySelector('.header-editor');
    const newRow = document.createElement('div');
    newRow.className = 'header-row';
    newRow.innerHTML = `
        <input type="text" class="form-control header-key" placeholder="Header Name">
        <input type="text" class="form-control header-value" placeholder="Header Value">
        <button type="button" class="btn btn-outline-danger" onclick="removeHeader(this)">
            <i class="fas fa-times"></i>
        </button>
    `;
    headerEditor.appendChild(newRow);
}

function removeHeader(button) {
    const row = button.closest('.header-row');
    row.remove();
}

function generateSecret() {
    const length = 32;
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
    let secret = '';
    for (let i = 0; i < length; i++) {
        secret += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    document.querySelector('#webhookSecret').value = secret;
}

function getSelectedEvents() {
    const events = [];
    document.querySelectorAll('.event-options input[type="checkbox"]:checked').forEach(checkbox => {
        events.push(checkbox.id.replace('event', '').replace(/([A-Z])/g, '.$1').toLowerCase());
    });
    return events;
}

function getHeadersFromEditor() {
    const headers = {};
    document.querySelectorAll('.header-row').forEach(row => {
        const key = row.querySelector('.header-key').value.trim();
        const value = row.querySelector('.header-value').value.trim();
        if (key && value) {
            headers[key] = value;
        }
    });
    return headers;
}

function validateWebhookUrl(url) {
    if (!url) return false;
    try {
        const parsed = new URL(url);
        return parsed.protocol === 'https:' || parsed.hostname === 'localhost';
    } catch (e) {
        return false;
    }
}

function createWebhook(e) {
    e.preventDefault();

    const url = document.querySelector('#newWebhookUrl').value;
    if (!validateWebhookUrl(url)) {
        alert('Invalid webhook URL. Must be HTTPS or localhost.');
        return;
    }

    const events = getSelectedEvents();
    if (events.length === 0) {
        alert('Please select at least one event type.');
        return;
    }

    const webhook = {
        webhookUrl: url,
        events: events,
        headers: getHeadersFromEditor(),
        isActive: true,
        security: {
            verifySSL: document.querySelector('#webhookSecureSSL').checked,
            retryEnabled: document.querySelector('#webhookRetryEnabled').checked,
            secret: document.querySelector('#webhookSecret').value || null
        },
        config: {
            timeout: parseInt(document.querySelector('#webhookTimeout').value, 10),
            maxRetries: parseInt(document.querySelector('#webhookMaxRetries').value, 10)
        }
    };

    fetch('/api/admin/config/webhooks', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(webhook)
    })
        .then(response => response.json())
        .then(() => {
            const modal = bootstrap.Modal.getInstance(document.getElementById('webhookNewModal'));
            modal.hide();
            refreshWebhooks();
        })
        .catch(error => {
            alert('Failed to create webhook: ' + error.message);
        });
}

function testWebhook(webhookUrl) {
    fetch(`/api/admin/config/webhooks/${encodeURIComponent(webhookUrl)}/test`, {
        method: 'POST'
    })
        .then(response => response.json())
        .then(result => {
            if (result.success) {
                alert('Webhook test successful! Response: ' + result.response);
            } else {
                alert('Webhook test failed: ' + result.error);
            }
        })
        .catch(error => {
            alert('Failed to test webhook: ' + error.message);
        });
}
