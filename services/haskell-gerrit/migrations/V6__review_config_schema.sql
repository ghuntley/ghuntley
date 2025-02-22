-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Review Configuration Schema

-- Review scope type
CREATE TYPE review_scope_type AS ENUM ('project', 'organization', 'enterprise', 'global');

-- Review configuration table
CREATE TABLE review_configs (
    config_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    scope_type review_scope_type NOT NULL,
    scope_id TEXT,  -- NULL for global scope
    labels JSONB NOT NULL DEFAULT '[]',
    submit_requirements JSONB NOT NULL DEFAULT '[]',
    auto_submit_config JSONB,
    ci_requirements JSONB,
    reviewer_suggestions JSONB,
    is_default BOOLEAN NOT NULL DEFAULT false,
    metadata JSONB,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_config_name UNIQUE (name, scope_type, scope_id),
    CONSTRAINT valid_scope CHECK (
        (scope_type = 'global' AND scope_id IS NULL) OR
        (scope_type != 'global' AND scope_id IS NOT NULL)
    )
);

-- Review configuration history table
CREATE TABLE review_config_history (
    history_id TEXT PRIMARY KEY,
    config_id TEXT NOT NULL REFERENCES review_configs(config_id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    old_value JSONB,
    new_value JSONB NOT NULL,
    reason TEXT,
    changed_by TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_review_configs_scope ON review_configs(scope_type, scope_id);
CREATE INDEX idx_review_configs_default ON review_configs(is_default) WHERE is_default = true;
CREATE INDEX idx_review_config_history_config ON review_config_history(config_id);
CREATE INDEX idx_review_config_history_timestamp ON review_config_history(timestamp);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_review_config_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_review_config_timestamp
    BEFORE UPDATE ON review_configs
    FOR EACH ROW
    EXECUTE FUNCTION update_review_config_timestamp();

-- Default global review configuration
INSERT INTO review_configs (
    config_id,
    name,
    description,
    scope_type,
    labels,
    submit_requirements,
    auto_submit_config,
    ci_requirements,
    reviewer_suggestions,
    is_default,
    created_by
) VALUES (
    'default-review-config',
    'Default Review Configuration',
    'Global default review configuration with standard labels and requirements',
    'global',
    '[
        {
            "labelName": "Code-Review",
            "description": "Code review approval",
            "values": [
                [-2, "Do not submit"],
                [-1, "I would prefer that you did not submit this"],
                [0, "No score"],
                [1, "Looks good to me, but someone else must approve"],
                [2, "Looks good to me, approved"]
            ],
            "copyScore": true,
            "defaultValue": 0
        },
        {
            "labelName": "Verified",
            "description": "Verified by CI/CD",
            "values": [
                [-1, "Failed"],
                [0, "No score"],
                [1, "Verified"]
            ],
            "copyScore": false,
            "defaultValue": 0,
            "function": "ci_verification"
        }
    ]',
    '[
        {
            "labelName": "Code-Review",
            "minValue": 2,
            "maxValue": 2
        },
        {
            "labelName": "Verified",
            "minValue": 1,
            "maxValue": 1
        }
    ]',
    '{
        "enabled": true,
        "requireAllSubmitRequirements": true,
        "allowSubmitWithWarnings": false,
        "autoSubmitOnAllApprovals": false
    }',
    '{
        "required": true,
        "requiredJobs": ["build", "test"],
        "optionalJobs": ["lint", "security-scan"],
        "timeout": 3600,
        "retryCount": 3
    }',
    '{
        "enabled": true,
        "suggestByFileOwnership": true,
        "suggestByHistory": true,
        "minReviewers": 1,
        "maxReviewers": 3,
        "excludeOwner": true
    }',
    true,
    'system'
);
