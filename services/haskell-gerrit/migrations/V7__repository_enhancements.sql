-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Repository Enhancements Schema

-- VCS type enum
CREATE TYPE vcs_type AS ENUM ('git', 'mercurial', 'jj');

-- Repository visibility enum
CREATE TYPE repo_visibility AS ENUM ('public', 'private', 'internal');

-- Mirror type enum
CREATE TYPE mirror_type AS ENUM ('pull', 'push', 'bidirectional');

-- Alter existing repositories table
ALTER TABLE repositories
    ADD COLUMN vcs_type vcs_type NOT NULL DEFAULT 'git',
    ADD COLUMN project_id TEXT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    ADD COLUMN mirror_config JSONB,
    ADD COLUMN branch_protection JSONB NOT NULL DEFAULT '[]',
    ADD COLUMN webhook_secret TEXT,
    ADD COLUMN stats JSONB,
    ADD COLUMN created_by TEXT NOT NULL DEFAULT 'system',
    ADD CONSTRAINT unique_repo_name UNIQUE (project_id, name);

-- Repository mirror logs
CREATE TABLE repository_mirror_logs (
    log_id TEXT PRIMARY KEY,
    repo_id TEXT NOT NULL REFERENCES repositories(repo_id) ON DELETE CASCADE,
    mirror_url TEXT NOT NULL,
    action TEXT NOT NULL,
    status TEXT NOT NULL,
    details JSONB,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Repository activity logs
CREATE TABLE repository_activities (
    activity_id TEXT PRIMARY KEY,
    repo_id TEXT NOT NULL REFERENCES repositories(repo_id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL,
    branch TEXT,
    commit_id TEXT,
    performed_by TEXT NOT NULL,
    details JSONB NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_repo_mirror_logs_repo ON repository_mirror_logs(repo_id);
CREATE INDEX idx_repo_mirror_logs_timestamp ON repository_mirror_logs(timestamp);
CREATE INDEX idx_repo_activities_repo ON repository_activities(repo_id);
CREATE INDEX idx_repo_activities_timestamp ON repository_activities(timestamp);
CREATE INDEX idx_repo_activities_type ON repository_activities(activity_type);
CREATE INDEX idx_repo_activities_branch ON repository_activities(branch) WHERE branch IS NOT NULL;
CREATE INDEX idx_repo_activities_commit ON repository_activities(commit_id) WHERE commit_id IS NOT NULL;

-- Update repository visibility type
ALTER TABLE repositories
    ALTER COLUMN visibility TYPE repo_visibility USING
    CASE visibility
        WHEN 'public' THEN 'public'::repo_visibility
        WHEN 'private' THEN 'private'::repo_visibility
        WHEN 'internal' THEN 'internal'::repo_visibility
    END;

-- Add trigger for repository statistics updates
CREATE OR REPLACE FUNCTION update_repository_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.stats IS DISTINCT FROM NEW.stats) THEN
        NEW.updated_at = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_repository_stats_trigger
    BEFORE INSERT OR UPDATE ON repositories
    FOR EACH ROW
    EXECUTE FUNCTION update_repository_stats();

-- Add trigger for repository activity tracking
CREATE OR REPLACE FUNCTION track_repository_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- Track significant changes
        IF OLD.default_branch IS DISTINCT FROM NEW.default_branch THEN
            INSERT INTO repository_activities (
                activity_id,
                repo_id,
                activity_type,
                branch,
                performed_by,
                details
            ) VALUES (
                gen_random_uuid()::text,
                NEW.repo_id,
                'branch_default_changed',
                NEW.default_branch,
                CURRENT_USER,
                jsonb_build_object(
                    'old_branch', OLD.default_branch,
                    'new_branch', NEW.default_branch
                )
            );
        END IF;

        IF OLD.branch_protection IS DISTINCT FROM NEW.branch_protection THEN
            INSERT INTO repository_activities (
                activity_id,
                repo_id,
                activity_type,
                performed_by,
                details
            ) VALUES (
                gen_random_uuid()::text,
                NEW.repo_id,
                'protection_updated',
                CURRENT_USER,
                jsonb_build_object(
                    'old_protection', OLD.branch_protection,
                    'new_protection', NEW.branch_protection
                )
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER track_repository_activity_trigger
    AFTER UPDATE ON repositories
    FOR EACH ROW
    EXECUTE FUNCTION track_repository_activity();
