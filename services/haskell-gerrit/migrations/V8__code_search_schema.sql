-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Code Search Schema

-- Index status enum
CREATE TYPE index_status AS ENUM ('pending', 'indexing', 'completed', 'failed');

-- Search result type enum
CREATE TYPE search_result_type AS ENUM ('file', 'symbol', 'commit', 'path');

-- Code search indices
CREATE TABLE code_search_indices (
    index_id TEXT PRIMARY KEY,
    repo_id TEXT NOT NULL REFERENCES repositories(repo_id) ON DELETE CASCADE,
    branch TEXT NOT NULL,
    commit_id TEXT NOT NULL,
    status index_status NOT NULL DEFAULT 'pending',
    config JSONB NOT NULL,
    last_indexed TIMESTAMP WITH TIME ZONE,
    next_index_time TIMESTAMP WITH TIME ZONE,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_repo_branch UNIQUE (repo_id, branch)
);

-- Search results
CREATE TABLE search_results (
    result_id TEXT PRIMARY KEY,
    index_id TEXT NOT NULL REFERENCES code_search_indices(index_id) ON DELETE CASCADE,
    result_type search_result_type NOT NULL,
    file_path TEXT NOT NULL,
    line_number INTEGER,
    column_number INTEGER,
    match_text TEXT NOT NULL,
    context TEXT NOT NULL,
    symbol_name TEXT,
    commit_id TEXT,
    score DOUBLE PRECISION NOT NULL,
    metadata JSONB,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Search queries
CREATE TABLE search_queries (
    query_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    query TEXT NOT NULL,
    filters JSONB,
    result_count INTEGER NOT NULL,
    execution_time DOUBLE PRECISION NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexing jobs
CREATE TABLE indexing_jobs (
    job_id TEXT PRIMARY KEY,
    index_id TEXT NOT NULL REFERENCES code_search_indices(index_id) ON DELETE CASCADE,
    status index_status NOT NULL DEFAULT 'pending',
    progress DOUBLE PRECISION NOT NULL DEFAULT 0,
    total_files INTEGER NOT NULL DEFAULT 0,
    processed_files INTEGER NOT NULL DEFAULT 0,
    error_count INTEGER NOT NULL DEFAULT 0,
    errors JSONB,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMP WITH TIME ZONE,
    metadata JSONB
);

-- Indexes for performance
CREATE INDEX idx_code_search_indices_repo ON code_search_indices(repo_id);
CREATE INDEX idx_code_search_indices_status ON code_search_indices(status);
CREATE INDEX idx_code_search_indices_next_index ON code_search_indices(next_index_time)
    WHERE next_index_time IS NOT NULL;

CREATE INDEX idx_search_results_index ON search_results(index_id);
CREATE INDEX idx_search_results_type ON search_results(result_type);
CREATE INDEX idx_search_results_path ON search_results(file_path);
CREATE INDEX idx_search_results_symbol ON search_results(symbol_name)
    WHERE symbol_name IS NOT NULL;
CREATE INDEX idx_search_results_commit ON search_results(commit_id)
    WHERE commit_id IS NOT NULL;
CREATE INDEX idx_search_results_score ON search_results(score DESC);

CREATE INDEX idx_search_queries_user ON search_queries(user_id);
CREATE INDEX idx_search_queries_timestamp ON search_queries(timestamp DESC);

CREATE INDEX idx_indexing_jobs_index ON indexing_jobs(index_id);
CREATE INDEX idx_indexing_jobs_status ON indexing_jobs(status);
CREATE INDEX idx_indexing_jobs_start_time ON indexing_jobs(start_time DESC);

-- Full text search indexes
ALTER TABLE search_results ADD COLUMN text_search_vector tsvector
    GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(symbol_name, '')), 'A') ||
        setweight(to_tsvector('english', file_path), 'B') ||
        setweight(to_tsvector('english', match_text), 'C') ||
        setweight(to_tsvector('english', context), 'D')
    ) STORED;

CREATE INDEX idx_search_results_fts ON search_results USING gin(text_search_vector);

-- Triggers for timestamp updates
CREATE OR REPLACE FUNCTION update_code_search_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_code_search_timestamp_trigger
    BEFORE UPDATE ON code_search_indices
    FOR EACH ROW
    EXECUTE FUNCTION update_code_search_timestamp();

-- Trigger for updating search statistics
CREATE OR REPLACE FUNCTION update_search_statistics()
RETURNS TRIGGER AS $$
BEGIN
    -- Update repository search statistics
    IF TG_OP = 'INSERT' THEN
        UPDATE repositories
        SET metadata = jsonb_set(
            coalesce(metadata, '{}'::jsonb),
            '{search_stats}',
            coalesce(metadata->'search_stats', '{}'::jsonb) || jsonb_build_object(
                'last_indexed', CURRENT_TIMESTAMP,
                'total_results', coalesce((metadata->'search_stats'->>'total_results')::int, 0) + 1
            )
        )
        WHERE repo_id = (
            SELECT repo_id
            FROM code_search_indices
            WHERE index_id = NEW.index_id
        );
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_search_statistics_trigger
    AFTER INSERT ON search_results
    FOR EACH ROW
    EXECUTE FUNCTION update_search_statistics();
