-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- CI/CD Integration Schema

-- CI provider type enum
CREATE TYPE ci_provider AS ENUM ('jenkins', 'github_actions', 'gitlab_ci', 'custom');

-- Build status enum
CREATE TYPE build_status AS ENUM ('queued', 'running', 'success', 'failure', 'error', 'cancelled', 'skipped');

-- CI configurations table
CREATE TABLE ci_configs (
    config_id TEXT PRIMARY KEY,
    repo_id TEXT NOT NULL REFERENCES repositories(repo_id) ON DELETE CASCADE,
    enabled BOOLEAN NOT NULL DEFAULT true,
    configuration JSONB NOT NULL,
    webhook_url TEXT,
    webhook_secret TEXT,
    metadata JSONB,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_repo_config UNIQUE (repo_id)
);

-- Builds table
CREATE TABLE builds (
    build_id TEXT PRIMARY KEY,
    config_id TEXT NOT NULL REFERENCES ci_configs(config_id) ON DELETE CASCADE,
    change_id TEXT,  -- Optional reference to a change
    provider ci_provider NOT NULL,
    status build_status NOT NULL DEFAULT 'queued',
    start_time TIMESTAMP WITH TIME ZONE,
    end_time TIMESTAMP WITH TIME ZONE,
    duration INTEGER,  -- Duration in seconds
    logs TEXT,
    artifacts JSONB,
    environment JSONB,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_duration CHECK (
        (duration IS NULL) OR
        (duration >= 0 AND start_time IS NOT NULL AND end_time IS NOT NULL)
    )
);

-- Build steps table
CREATE TABLE build_steps (
    step_id TEXT PRIMARY KEY,
    build_id TEXT NOT NULL REFERENCES builds(build_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status build_status NOT NULL DEFAULT 'queued',
    start_time TIMESTAMP WITH TIME ZONE,
    end_time TIMESTAMP WITH TIME ZONE,
    duration INTEGER,  -- Duration in seconds
    logs TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_step_duration CHECK (
        (duration IS NULL) OR
        (duration >= 0 AND start_time IS NOT NULL AND end_time IS NOT NULL)
    )
);

-- Build artifacts table
CREATE TABLE build_artifacts (
    artifact_id TEXT PRIMARY KEY,
    build_id TEXT NOT NULL REFERENCES builds(build_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    path TEXT NOT NULL,
    size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_artifact_size CHECK (size >= 0)
);

-- Indexes for performance
CREATE INDEX idx_ci_configs_repo ON ci_configs(repo_id);
CREATE INDEX idx_ci_configs_enabled ON ci_configs(enabled) WHERE enabled = true;

CREATE INDEX idx_builds_config ON builds(config_id);
CREATE INDEX idx_builds_change ON builds(change_id) WHERE change_id IS NOT NULL;
CREATE INDEX idx_builds_provider ON builds(provider);
CREATE INDEX idx_builds_status ON builds(status);
CREATE INDEX idx_builds_start_time ON builds(start_time) WHERE start_time IS NOT NULL;
CREATE INDEX idx_builds_end_time ON builds(end_time) WHERE end_time IS NOT NULL;

CREATE INDEX idx_build_steps_build ON build_steps(build_id);
CREATE INDEX idx_build_steps_status ON build_steps(status);
CREATE INDEX idx_build_steps_start_time ON build_steps(start_time) WHERE start_time IS NOT NULL;

CREATE INDEX idx_build_artifacts_build ON build_artifacts(build_id);
CREATE INDEX idx_build_artifacts_name ON build_artifacts(name);

-- Trigger to update updated_at timestamp for ci_configs
CREATE OR REPLACE FUNCTION update_ci_config_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_ci_config_timestamp_trigger
    BEFORE UPDATE ON ci_configs
    FOR EACH ROW
    EXECUTE FUNCTION update_ci_config_timestamp();

-- Trigger to update updated_at timestamp for builds
CREATE OR REPLACE FUNCTION update_build_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    IF NEW.end_time IS NOT NULL AND OLD.end_time IS NULL THEN
        NEW.duration = EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time))::INTEGER;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_build_timestamp_trigger
    BEFORE UPDATE ON builds
    FOR EACH ROW
    EXECUTE FUNCTION update_build_timestamp();

-- Trigger to update build step duration
CREATE OR REPLACE FUNCTION update_build_step_duration()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.end_time IS NOT NULL AND OLD.end_time IS NULL THEN
        NEW.duration = EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time))::INTEGER;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_build_step_duration_trigger
    BEFORE UPDATE ON build_steps
    FOR EACH ROW
    EXECUTE FUNCTION update_build_step_duration();

-- Trigger to update build status based on steps
CREATE OR REPLACE FUNCTION update_build_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Update build status when a step status changes
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        -- If any step fails, mark build as failed
        IF NEW.status = 'failure' OR NEW.status = 'error' THEN
            UPDATE builds
            SET status = NEW.status,
                updated_at = CURRENT_TIMESTAMP
            WHERE build_id = NEW.build_id;
        -- If all steps are success, mark build as success
        ELSIF NOT EXISTS (
            SELECT 1 FROM build_steps
            WHERE build_id = NEW.build_id
            AND status NOT IN ('success', 'skipped')
        ) THEN
            UPDATE builds
            SET status = 'success',
                updated_at = CURRENT_TIMESTAMP
            WHERE build_id = NEW.build_id;
        -- If any step is running, mark build as running
        ELSIF EXISTS (
            SELECT 1 FROM build_steps
            WHERE build_id = NEW.build_id
            AND status = 'running'
        ) THEN
            UPDATE builds
            SET status = 'running',
                updated_at = CURRENT_TIMESTAMP
            WHERE build_id = NEW.build_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_build_status_trigger
    AFTER INSERT OR UPDATE ON build_steps
    FOR EACH ROW
    EXECUTE FUNCTION update_build_status();
