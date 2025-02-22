-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Code Browser Schema

-- View context type enum
CREATE TYPE view_context_type AS ENUM ('change', 'branch', 'commit');

-- File views table
CREATE TABLE file_views (
    view_id TEXT PRIMARY KEY,
    context_type view_context_type NOT NULL,
    context_data JSONB NOT NULL,  -- Stores the specific context data (change/revision IDs, branch info, etc.)
    file_path TEXT NOT NULL,
    content TEXT NOT NULL,
    syntax_config JSONB NOT NULL,
    highlights JSONB NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    content_tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
);

-- File history table
CREATE TABLE file_history (
    history_id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,
    commit_id TEXT NOT NULL,
    author_id TEXT NOT NULL,
    message TEXT NOT NULL,
    diff TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

-- Blame information table
CREATE TABLE blame_info (
    blame_id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,
    line_number INTEGER NOT NULL,
    commit_id TEXT NOT NULL,
    author_id TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    content TEXT NOT NULL,
    metadata JSONB,
    CONSTRAINT unique_blame_line UNIQUE (file_path, line_number)
);

-- Syntax highlighting cache table
CREATE TABLE syntax_cache (
    cache_id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,
    language TEXT NOT NULL,
    content TEXT NOT NULL,
    highlighted_content TEXT NOT NULL,
    ranges JSONB NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_file_views_context_type ON file_views(context_type);
CREATE INDEX idx_file_views_file_path ON file_views(file_path);
CREATE INDEX idx_file_views_created ON file_views(created_at);

CREATE INDEX idx_file_history_file_path ON file_history(file_path);
CREATE INDEX idx_file_history_commit ON file_history(commit_id);
CREATE INDEX idx_file_history_author ON file_history(author_id);
CREATE INDEX idx_file_history_timestamp ON file_history(timestamp);

CREATE INDEX idx_blame_info_file_path ON blame_info(file_path);
CREATE INDEX idx_blame_info_commit ON blame_info(commit_id);
CREATE INDEX idx_blame_info_author ON blame_info(author_id);
CREATE INDEX idx_blame_info_timestamp ON blame_info(timestamp);

CREATE INDEX idx_syntax_cache_file_path ON syntax_cache(file_path);
CREATE INDEX idx_syntax_cache_language ON syntax_cache(language);
CREATE INDEX idx_syntax_cache_timestamp ON syntax_cache(timestamp);

-- Full text search index
CREATE INDEX idx_file_views_content_tsv ON file_views USING gin(content_tsv);

-- Function to clean up old syntax cache entries
CREATE OR REPLACE FUNCTION cleanup_old_syntax_cache()
RETURNS TRIGGER AS $$
BEGIN
    -- Delete cache entries older than 7 days
    DELETE FROM syntax_cache
    WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '7 days';
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER cleanup_old_syntax_cache_trigger
    AFTER INSERT ON syntax_cache
    EXECUTE FUNCTION cleanup_old_syntax_cache();

-- Function to track file view access
CREATE OR REPLACE FUNCTION track_file_view_access()
RETURNS TRIGGER AS $$
BEGIN
    -- Update metadata with access information
    NEW.metadata = jsonb_set(
        COALESCE(NEW.metadata, '{}'::jsonb),
        '{access_history}',
        COALESCE(
            NEW.metadata->'access_history',
            '[]'::jsonb
        ) || jsonb_build_object(
            'timestamp', CURRENT_TIMESTAMP,
            'user_id', CURRENT_USER
        )
    );
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER track_file_view_access_trigger
    BEFORE INSERT OR UPDATE ON file_views
    FOR EACH ROW
    EXECUTE FUNCTION track_file_view_access();

-- Function to get file history
CREATE OR REPLACE FUNCTION get_file_history(
    p_file_path TEXT,
    p_start_date TIMESTAMP WITH TIME ZONE,
    p_end_date TIMESTAMP WITH TIME ZONE
) RETURNS TABLE (
    history_id TEXT,
    commit_id TEXT,
    author_id TEXT,
    message TEXT,
    diff TEXT,
    timestamp TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        fh.history_id,
        fh.commit_id,
        fh.author_id,
        fh.message,
        fh.diff,
        fh.timestamp
    FROM file_history fh
    WHERE fh.file_path = p_file_path
    AND fh.timestamp BETWEEN p_start_date AND p_end_date
    ORDER BY fh.timestamp DESC;
END;
$$ language 'plpgsql';

-- Function to get file blame
CREATE OR REPLACE FUNCTION get_file_blame(
    p_file_path TEXT
) RETURNS TABLE (
    line_number INTEGER,
    commit_id TEXT,
    author_id TEXT,
    content TEXT,
    timestamp TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        bi.line_number,
        bi.commit_id,
        bi.author_id,
        bi.content,
        bi.timestamp
    FROM blame_info bi
    WHERE bi.file_path = p_file_path
    ORDER BY bi.line_number;
END;
$$ language 'plpgsql';
