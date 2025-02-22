-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Change Management System Enhancements

-- Change type enum
CREATE TYPE change_type AS ENUM ('feature', 'bugfix', 'documentation', 'refactor', 'test', 'build', 'other');

-- Change phase enum
CREATE TYPE change_phase AS ENUM ('review', 'verification', 'integration', 'submission');

-- Dependency type enum
CREATE TYPE dependency_type AS ENUM ('required', 'optional', 'related');

-- Add new columns to changes table
ALTER TABLE changes
    ADD COLUMN change_type change_type NOT NULL DEFAULT 'other',
    ADD COLUMN phase change_phase NOT NULL DEFAULT 'review',
    ADD COLUMN patch_set_config JSONB NOT NULL DEFAULT '{
        "autoGenerate": false,
        "triggerPaths": [],
        "excludePaths": [],
        "maxSize": 1000,
        "strategy": "default"
    }',
    ADD COLUMN work_in_progress BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN private BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN topic TEXT,
    ADD COLUMN hashtags TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN reviewers TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN assignee TEXT,
    ADD COLUMN priority INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN submit_strategy TEXT NOT NULL DEFAULT 'merge_if_necessary',
    ADD COLUMN merge_strategy TEXT,
    ADD COLUMN integration_status JSONB;

-- Create change dependencies table
CREATE TABLE change_dependencies (
    dependency_id TEXT PRIMARY KEY,
    change_id TEXT NOT NULL REFERENCES changes(change_id) ON DELETE CASCADE,
    depends_on_id TEXT NOT NULL REFERENCES changes(change_id) ON DELETE CASCADE,
    dependency_type dependency_type NOT NULL,
    required BOOLEAN NOT NULL DEFAULT true,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_dependency_id UNIQUE (dependency_id),
    CONSTRAINT no_self_dependency CHECK (change_id != depends_on_id)
);

-- Create change activities table
CREATE TABLE change_activities (
    activity_id TEXT PRIMARY KEY,
    change_id TEXT NOT NULL REFERENCES changes(change_id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL,
    old_value JSONB,
    new_value JSONB,
    performed_by TEXT NOT NULL,
    details JSONB,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_activity_id UNIQUE (activity_id)
);

-- Indexes for performance
CREATE INDEX idx_changes_change_type ON changes(change_type);
CREATE INDEX idx_changes_phase ON changes(phase);
CREATE INDEX idx_changes_work_in_progress ON changes(work_in_progress) WHERE work_in_progress = true;
CREATE INDEX idx_changes_private ON changes(private) WHERE private = true;
CREATE INDEX idx_changes_topic ON changes(topic) WHERE topic IS NOT NULL;
CREATE INDEX idx_changes_assignee ON changes(assignee) WHERE assignee IS NOT NULL;
CREATE INDEX idx_changes_priority ON changes(priority);

CREATE INDEX idx_change_dependencies_change ON change_dependencies(change_id);
CREATE INDEX idx_change_dependencies_depends_on ON change_dependencies(depends_on_id);
CREATE INDEX idx_change_dependencies_type ON change_dependencies(dependency_type);
CREATE INDEX idx_change_dependencies_required ON change_dependencies(required) WHERE required = true;

CREATE INDEX idx_change_activities_change ON change_activities(change_id);
CREATE INDEX idx_change_activities_type ON change_activities(activity_type);
CREATE INDEX idx_change_activities_performed_by ON change_activities(performed_by);
CREATE INDEX idx_change_activities_timestamp ON change_activities(timestamp);

-- Trigger to track change status updates
CREATE OR REPLACE FUNCTION track_change_status_updates()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO change_activities (
            activity_id,
            change_id,
            activity_type,
            old_value,
            new_value,
            performed_by,
            details
        ) VALUES (
            gen_random_uuid()::text,
            NEW.change_id,
            'status_changed',
            jsonb_build_object('status', OLD.status),
            jsonb_build_object('status', NEW.status),
            CURRENT_USER,
            jsonb_build_object('reason', 'Status update')
        );
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER track_change_status_updates_trigger
    AFTER UPDATE ON changes
    FOR EACH ROW
    EXECUTE FUNCTION track_change_status_updates();

-- Trigger to track phase transitions
CREATE OR REPLACE FUNCTION track_phase_transitions()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.phase IS DISTINCT FROM NEW.phase THEN
        INSERT INTO change_activities (
            activity_id,
            change_id,
            activity_type,
            old_value,
            new_value,
            performed_by,
            details
        ) VALUES (
            gen_random_uuid()::text,
            NEW.change_id,
            'phase_changed',
            jsonb_build_object('phase', OLD.phase),
            jsonb_build_object('phase', NEW.phase),
            CURRENT_USER,
            jsonb_build_object('reason', 'Phase transition')
        );
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER track_phase_transitions_trigger
    AFTER UPDATE ON changes
    FOR EACH ROW
    EXECUTE FUNCTION track_phase_transitions();

-- Trigger to validate dependencies
CREATE OR REPLACE FUNCTION validate_change_dependencies()
RETURNS TRIGGER AS $$
BEGIN
    -- Check for circular dependencies
    WITH RECURSIVE dependency_chain AS (
        -- Base case: direct dependencies
        SELECT change_id, depends_on_id, ARRAY[change_id] as path
        FROM change_dependencies
        WHERE change_id = NEW.change_id

        UNION ALL

        -- Recursive case: follow the chain
        SELECT d.change_id, d.depends_on_id, dc.path || d.change_id
        FROM change_dependencies d
        JOIN dependency_chain dc ON d.change_id = dc.depends_on_id
        WHERE NOT d.depends_on_id = ANY(dc.path)
    )
    SELECT CASE
        WHEN EXISTS (
            SELECT 1 FROM dependency_chain
            WHERE depends_on_id = NEW.change_id
        )
        THEN RAISE EXCEPTION 'Circular dependency detected'
        ELSE NULL
    END;

    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER validate_change_dependencies_trigger
    BEFORE INSERT OR UPDATE ON change_dependencies
    FOR EACH ROW
    EXECUTE FUNCTION validate_change_dependencies();

-- Trigger to update change status when dependencies change
CREATE OR REPLACE FUNCTION update_change_status_on_dependency_change()
RETURNS TRIGGER AS $$
BEGIN
    -- If a required dependency is added, move change to Draft if it was Open
    IF NEW.required AND TG_OP = 'INSERT' THEN
        UPDATE changes
        SET status = 'draft',
            updated_at = CURRENT_TIMESTAMP
        WHERE change_id = NEW.change_id
        AND status = 'open';
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_change_status_on_dependency_change_trigger
    AFTER INSERT ON change_dependencies
    FOR EACH ROW
    EXECUTE FUNCTION update_change_status_on_dependency_change();
