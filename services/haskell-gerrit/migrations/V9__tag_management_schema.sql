-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Tag Management Schema

-- Tag type enum
CREATE TYPE tag_type AS ENUM ('lightweight', 'annotated');

-- Tag verification status enum
CREATE TYPE tag_verification AS ENUM ('unverified', 'verified_good', 'verified_bad', 'verification_error');

-- Tags table
CREATE TABLE tags (
    tag_id TEXT PRIMARY KEY,
    repo_id TEXT NOT NULL REFERENCES repositories(repo_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    tag_type tag_type NOT NULL,
    target_commit TEXT NOT NULL,
    message TEXT,
    tagger TEXT NOT NULL,
    signature TEXT,
    verification tag_verification NOT NULL DEFAULT 'unverified',
    signing_config JSONB,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_repo_tag UNIQUE (repo_id, name)
);

-- Tag releases table
CREATE TABLE tag_releases (
    release_id TEXT PRIMARY KEY,
    tag_id TEXT NOT NULL REFERENCES tags(tag_id) ON DELETE CASCADE,
    version TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    release_notes TEXT,
    assets JSONB,
    is_prerelease BOOLEAN NOT NULL DEFAULT false,
    is_draft BOOLEAN NOT NULL DEFAULT false,
    published_by TEXT NOT NULL,
    published_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB,
    CONSTRAINT unique_tag_release UNIQUE (tag_id)
);

-- Tag protection rules
CREATE TABLE tag_protection (
    protection_id TEXT PRIMARY KEY,
    repo_id TEXT NOT NULL REFERENCES repositories(repo_id) ON DELETE CASCADE,
    pattern TEXT NOT NULL,
    allow_creation BOOLEAN NOT NULL DEFAULT true,
    allow_deletion BOOLEAN NOT NULL DEFAULT false,
    require_signing BOOLEAN NOT NULL DEFAULT false,
    allowed_signers TEXT[] NOT NULL DEFAULT '{}',
    protected_branches TEXT[] NOT NULL DEFAULT '{}',
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Tag activity logs
CREATE TABLE tag_activities (
    activity_id TEXT PRIMARY KEY,
    tag_id TEXT NOT NULL REFERENCES tags(tag_id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL,
    performed_by TEXT NOT NULL,
    details JSONB NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_tags_repo ON tags(repo_id);
CREATE INDEX idx_tags_type ON tags(tag_type);
CREATE INDEX idx_tags_verification ON tags(verification);
CREATE INDEX idx_tags_target_commit ON tags(target_commit);

CREATE INDEX idx_tag_releases_version ON tag_releases(version);
CREATE INDEX idx_tag_releases_published_at ON tag_releases(published_at DESC);
CREATE INDEX idx_tag_releases_prerelease ON tag_releases(is_prerelease)
    WHERE is_prerelease = true;
CREATE INDEX idx_tag_releases_draft ON tag_releases(is_draft)
    WHERE is_draft = true;

CREATE INDEX idx_tag_protection_repo ON tag_protection(repo_id);
CREATE INDEX idx_tag_protection_pattern ON tag_protection(pattern);

CREATE INDEX idx_tag_activities_tag ON tag_activities(tag_id);
CREATE INDEX idx_tag_activities_type ON tag_activities(activity_type);
CREATE INDEX idx_tag_activities_timestamp ON tag_activities(timestamp DESC);

-- Triggers for timestamp updates
CREATE OR REPLACE FUNCTION update_tag_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_tag_timestamp_trigger
    BEFORE UPDATE ON tags
    FOR EACH ROW
    EXECUTE FUNCTION update_tag_timestamp();

CREATE TRIGGER update_tag_protection_timestamp_trigger
    BEFORE UPDATE ON tag_protection
    FOR EACH ROW
    EXECUTE FUNCTION update_tag_timestamp();

-- Trigger for tag activity tracking
CREATE OR REPLACE FUNCTION track_tag_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO tag_activities (
            activity_id,
            tag_id,
            activity_type,
            performed_by,
            details
        ) VALUES (
            gen_random_uuid()::text,
            NEW.tag_id,
            'create',
            NEW.tagger,
            jsonb_build_object(
                'name', NEW.name,
                'type', NEW.tag_type,
                'target_commit', NEW.target_commit,
                'message', NEW.message
            )
        );
    ELSIF TG_OP = 'UPDATE' THEN
        -- Track significant changes
        IF OLD.target_commit IS DISTINCT FROM NEW.target_commit THEN
            INSERT INTO tag_activities (
                activity_id,
                tag_id,
                activity_type,
                performed_by,
                details
            ) VALUES (
                gen_random_uuid()::text,
                NEW.tag_id,
                'update',
                CURRENT_USER,
                jsonb_build_object(
                    'old_target', OLD.target_commit,
                    'new_target', NEW.target_commit
                )
            );
        END IF;

        IF OLD.signature IS DISTINCT FROM NEW.signature THEN
            INSERT INTO tag_activities (
                activity_id,
                tag_id,
                activity_type,
                performed_by,
                details
            ) VALUES (
                gen_random_uuid()::text,
                NEW.tag_id,
                'sign',
                CURRENT_USER,
                jsonb_build_object(
                    'verification', NEW.verification
                )
            );
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO tag_activities (
            activity_id,
            tag_id,
            activity_type,
            performed_by,
            details
        ) VALUES (
            gen_random_uuid()::text,
            OLD.tag_id,
            'delete',
            CURRENT_USER,
            jsonb_build_object(
                'name', OLD.name,
                'type', OLD.tag_type,
                'target_commit', OLD.target_commit
            )
        );
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER track_tag_activity_trigger
    AFTER INSERT OR UPDATE OR DELETE ON tags
    FOR EACH ROW
    EXECUTE FUNCTION track_tag_activity();
