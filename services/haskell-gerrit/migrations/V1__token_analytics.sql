-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Token usage tracking
CREATE TABLE token_usage (
    id SERIAL PRIMARY KEY,
    token_value TEXT NOT NULL,
    endpoint TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    user_agent TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'success',
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    response_time INTEGER,  -- in milliseconds
    FOREIGN KEY (token_value) REFERENCES auth_tokens(token_value)
);

CREATE INDEX idx_token_usage_token ON token_usage(token_value);
CREATE INDEX idx_token_usage_timestamp ON token_usage(timestamp);
CREATE INDEX idx_token_usage_status ON token_usage(status);

-- Token scope usage tracking
CREATE TABLE token_usage_scopes (
    id SERIAL PRIMARY KEY,
    token_value TEXT NOT NULL,
    scope TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_used TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    FOREIGN KEY (token_value) REFERENCES auth_tokens(token_value)
);

CREATE INDEX idx_token_scopes_token ON token_usage_scopes(token_value);
CREATE INDEX idx_token_scopes_last_used ON token_usage_scopes(last_used);

-- Security events tracking
CREATE TABLE security_events (
    id SERIAL PRIMARY KEY,
    token_value TEXT NOT NULL,
    event_type TEXT NOT NULL,
    severity TEXT NOT NULL,
    details JSONB NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    FOREIGN KEY (token_value) REFERENCES auth_tokens(token_value)
);

CREATE INDEX idx_security_events_token ON security_events(token_value);
CREATE INDEX idx_security_events_timestamp ON security_events(timestamp);
CREATE INDEX idx_security_events_type ON security_events(event_type);

-- Token rotation history
CREATE TABLE token_rotations (
    id SERIAL PRIMARY KEY,
    old_token_value TEXT NOT NULL,
    new_token_value TEXT NOT NULL,
    rotation_type TEXT NOT NULL,
    reason TEXT,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    FOREIGN KEY (old_token_value) REFERENCES auth_tokens(token_value),
    FOREIGN KEY (new_token_value) REFERENCES auth_tokens(token_value)
);

CREATE INDEX idx_token_rotations_old ON token_rotations(old_token_value);
CREATE INDEX idx_token_rotations_new ON token_rotations(new_token_value);

-- Token health metrics
CREATE TABLE token_health_metrics (
    id SERIAL PRIMARY KEY,
    token_value TEXT NOT NULL,
    overall_score DOUBLE PRECISION NOT NULL,
    rotation_score DOUBLE PRECISION NOT NULL,
    scope_score DOUBLE PRECISION NOT NULL,
    error_rate DOUBLE PRECISION NOT NULL,
    security_score DOUBLE PRECISION NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    FOREIGN KEY (token_value) REFERENCES auth_tokens(token_value)
);

CREATE INDEX idx_token_health_token ON token_health_metrics(token_value);
CREATE INDEX idx_token_health_timestamp ON token_health_metrics(timestamp);

-- Add new columns to auth_tokens table
ALTER TABLE auth_tokens
ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active',
ADD COLUMN IF NOT EXISTS rotated_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS rotation_count INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS device_info JSONB,
ADD COLUMN IF NOT EXISTS security_settings JSONB;
