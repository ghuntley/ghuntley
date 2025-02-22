-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Enterprise table
CREATE TABLE enterprises (
    enterprise_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    domain TEXT NOT NULL UNIQUE,
    plan TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    max_users INTEGER,
    max_projects INTEGER,
    max_storage INTEGER,
    branding JSONB,
    settings JSONB NOT NULL DEFAULT '{}',
    metadata JSONB,
    trial_ends_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_enterprises_domain ON enterprises(domain);
CREATE INDEX idx_enterprises_plan ON enterprises(plan);
CREATE INDEX idx_enterprises_status ON enterprises(status);

-- Enterprise billing table
CREATE TABLE enterprise_billing (
    billing_id TEXT PRIMARY KEY,
    enterprise_id TEXT NOT NULL REFERENCES enterprises(enterprise_id) ON DELETE CASCADE,
    plan_id TEXT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency TEXT NOT NULL,
    billing_cycle TEXT NOT NULL,
    next_billing_date TIMESTAMP WITH TIME ZONE NOT NULL,
    payment_method JSONB,
    billing_address JSONB,
    tax_info JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_enterprise_billing_enterprise ON enterprise_billing(enterprise_id);
CREATE INDEX idx_enterprise_billing_next_billing ON enterprise_billing(next_billing_date);

-- Enterprise usage metrics
CREATE TABLE enterprise_metrics (
    metric_id TEXT PRIMARY KEY,
    enterprise_id TEXT NOT NULL REFERENCES enterprises(enterprise_id) ON DELETE CASCADE,
    metric_type TEXT NOT NULL,
    value INTEGER NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_enterprise_metrics_enterprise ON enterprise_metrics(enterprise_id);
CREATE INDEX idx_enterprise_metrics_type ON enterprise_metrics(metric_type);
CREATE INDEX idx_enterprise_metrics_timestamp ON enterprise_metrics(timestamp);

-- Enterprise audit log
CREATE TABLE enterprise_audit_logs (
    log_id TEXT PRIMARY KEY,
    enterprise_id TEXT NOT NULL REFERENCES enterprises(enterprise_id) ON DELETE CASCADE,
    action TEXT NOT NULL,
    actor_id TEXT NOT NULL,
    details JSONB NOT NULL,
    ip_address TEXT,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_enterprise_audit_enterprise ON enterprise_audit_logs(enterprise_id);
CREATE INDEX idx_enterprise_audit_action ON enterprise_audit_logs(action);
CREATE INDEX idx_enterprise_audit_actor ON enterprise_audit_logs(actor_id);
CREATE INDEX idx_enterprise_audit_created ON enterprise_audit_logs(created_at);

-- Enterprise feature flags
CREATE TABLE enterprise_features (
    feature_id TEXT PRIMARY KEY,
    enterprise_id TEXT NOT NULL REFERENCES enterprises(enterprise_id) ON DELETE CASCADE,
    feature_name TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    configuration JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (enterprise_id, feature_name)
);

CREATE INDEX idx_enterprise_features_enterprise ON enterprise_features(enterprise_id);
CREATE INDEX idx_enterprise_features_name ON enterprise_features(feature_name);

-- Enterprise API keys
CREATE TABLE enterprise_api_keys (
    key_id TEXT PRIMARY KEY,
    enterprise_id TEXT NOT NULL REFERENCES enterprises(enterprise_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    key_hash TEXT NOT NULL,
    scopes TEXT[] NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE,
    last_used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_enterprise_api_keys_enterprise ON enterprise_api_keys(enterprise_id);
CREATE INDEX idx_enterprise_api_keys_expires ON enterprise_api_keys(expires_at);

-- Enterprise webhooks
CREATE TABLE enterprise_webhooks (
    webhook_id TEXT PRIMARY KEY,
    enterprise_id TEXT NOT NULL REFERENCES enterprises(enterprise_id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    events TEXT[] NOT NULL,
    secret_hash TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    ssl_verify BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_enterprise_webhooks_enterprise ON enterprise_webhooks(enterprise_id);
CREATE INDEX idx_enterprise_webhooks_active ON enterprise_webhooks(active);

-- Enterprise integrations
CREATE TABLE enterprise_integrations (
    integration_id TEXT PRIMARY KEY,
    enterprise_id TEXT NOT NULL REFERENCES enterprises(enterprise_id) ON DELETE CASCADE,
    integration_type TEXT NOT NULL,
    configuration JSONB NOT NULL,
    credentials JSONB,
    active BOOLEAN NOT NULL DEFAULT true,
    health_status TEXT,
    last_sync_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_enterprise_integrations_enterprise ON enterprise_integrations(enterprise_id);
CREATE INDEX idx_enterprise_integrations_type ON enterprise_integrations(integration_type);
CREATE INDEX idx_enterprise_integrations_active ON enterprise_integrations(active);

-- Add enterprise_id foreign key to existing tables
ALTER TABLE organizations
ADD COLUMN enterprise_id TEXT REFERENCES enterprises(enterprise_id) ON DELETE SET NULL;

CREATE INDEX idx_organizations_enterprise ON organizations(enterprise_id);

-- Add enterprise-related columns to users table
ALTER TABLE users
ADD COLUMN enterprise_role TEXT,
ADD COLUMN enterprise_id TEXT REFERENCES enterprises(enterprise_id) ON DELETE SET NULL;

CREATE INDEX idx_users_enterprise ON users(enterprise_id);
CREATE INDEX idx_users_enterprise_role ON users(enterprise_role);
