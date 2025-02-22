-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Project Templates Schema

CREATE TYPE template_visibility AS ENUM ('global', 'enterprise', 'organization');

CREATE TABLE project_templates (
    template_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    visibility template_visibility NOT NULL,
    enterprise_id TEXT REFERENCES enterprises(enterprise_id) ON DELETE CASCADE,
    organization_id TEXT REFERENCES organizations(organization_id) ON DELETE CASCADE,
    config JSONB NOT NULL DEFAULT '{}',
    parent_template_id TEXT REFERENCES project_templates(template_id) ON DELETE SET NULL,
    is_default BOOLEAN NOT NULL DEFAULT false,
    metadata JSONB,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_template_name UNIQUE (name, visibility, enterprise_id, organization_id),
    CONSTRAINT valid_template_scope CHECK (
        (visibility = 'global' AND enterprise_id IS NULL AND organization_id IS NULL) OR
        (visibility = 'enterprise' AND enterprise_id IS NOT NULL AND organization_id IS NULL) OR
        (visibility = 'organization' AND organization_id IS NOT NULL)
    )
);

-- Indexes for performance
CREATE INDEX idx_project_templates_visibility ON project_templates(visibility);
CREATE INDEX idx_project_templates_enterprise ON project_templates(enterprise_id) WHERE enterprise_id IS NOT NULL;
CREATE INDEX idx_project_templates_organization ON project_templates(organization_id) WHERE organization_id IS NOT NULL;
CREATE INDEX idx_project_templates_parent ON project_templates(parent_template_id) WHERE parent_template_id IS NOT NULL;
CREATE INDEX idx_project_templates_default ON project_templates(is_default) WHERE is_default = true;

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_project_template_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_project_template_timestamp
    BEFORE UPDATE ON project_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_project_template_timestamp();

-- Default global templates
INSERT INTO project_templates (
    template_id,
    name,
    description,
    visibility,
    config,
    is_default,
    created_by
) VALUES (
    'default-empty',
    'Empty Project',
    'A basic empty project template with minimal configuration',
    'global',
    '{
        "branchProtectionRules": {
            "main": {
                "requirePullRequest": true,
                "requiredReviewers": 1
            }
        },
        "submissionRules": {
            "requireCodeReview": true,
            "requireBuildSuccess": true
        },
        "reviewLabels": {
            "Code-Review": {"values": [-2, -1, 0, 1, 2], "copyScore": true},
            "Verified": {"values": [-1, 0, 1], "copyScore": false}
        },
        "webhookConfigs": {},
        "cicdConfig": {"enabled": false},
        "accessControl": {
            "admins": {"permissions": ["read", "write", "admin"]},
            "developers": {"permissions": ["read", "write"]},
            "viewers": {"permissions": ["read"]}
        }
    }',
    true,
    'system'
), (
    'default-ci',
    'CI/CD Project',
    'Project template with CI/CD configuration pre-configured',
    'global',
    '{
        "branchProtectionRules": {
            "main": {
                "requirePullRequest": true,
                "requiredReviewers": 1,
                "requireBuildSuccess": true
            }
        },
        "submissionRules": {
            "requireCodeReview": true,
            "requireBuildSuccess": true,
            "requireTests": true
        },
        "reviewLabels": {
            "Code-Review": {"values": [-2, -1, 0, 1, 2], "copyScore": true},
            "Verified": {"values": [-1, 0, 1], "copyScore": false}
        },
        "webhookConfigs": {
            "ci": {
                "url": "{{CI_WEBHOOK_URL}}",
                "events": ["change.created", "change.updated", "change.merged"]
            }
        },
        "cicdConfig": {
            "enabled": true,
            "provider": "jenkins",
            "buildOnCreate": true,
            "buildOnUpdate": true
        },
        "accessControl": {
            "admins": {"permissions": ["read", "write", "admin"]},
            "developers": {"permissions": ["read", "write"]},
            "viewers": {"permissions": ["read"]}
        }
    }',
    true,
    'system'
);
