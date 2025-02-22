{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.CodeBrowser
    ( codeBrowserRoutes
    ) where

import Web.Scotty.Trans

import Gerrit.Api.Error (ApiError)
import Gerrit.Api.Handlers.CodeBrowser
import Gerrit.Services.CodeBrowserService (CodeBrowserService)

-- | Code browser routes
codeBrowserRoutes :: CodeBrowserService -> ScottyT ApiError IO ()
codeBrowserRoutes service = do
    -- File viewing
    get "/api/v1/browse/:repo_id/files" $
        handleListFiles service

    get "/api/v1/browse/:repo_id/files/:file_path" $
        handleGetFile service

    get "/api/v1/browse/:repo_id/files/:file_path/raw" $
        handleGetRawFile service

    -- File history
    get "/api/v1/browse/:repo_id/files/:file_path/history" $
        handleGetFileHistory service

    get "/api/v1/browse/:repo_id/files/:file_path/blame" $
        handleGetBlameInfo service

    -- Syntax highlighting
    get "/api/v1/browse/:repo_id/files/:file_path/highlight" $
        handleGetHighlightedFile service

    post "/api/v1/browse/:repo_id/files/:file_path/highlight" $
        handleUpdateHighlighting service

    -- Search
    get "/api/v1/browse/:repo_id/search" $
        handleSearchFiles service

    -- Context-specific views
    get "/api/v1/browse/changes/:change_id/files" $
        handleListChangeFiles service

    get "/api/v1/browse/changes/:change_id/files/:file_path" $
        handleGetChangeFile service

    get "/api/v1/browse/commits/:commit_id/files" $
        handleListCommitFiles service

    get "/api/v1/browse/commits/:commit_id/files/:file_path" $
        handleGetCommitFile service

    -- Diff views
    get "/api/v1/browse/changes/:change_id/files/:file_path/diff" $
        handleGetChangeDiff service

    get "/api/v1/browse/commits/:commit_id/files/:file_path/diff" $
        handleGetCommitDiff service

    -- File operations
    post "/api/v1/browse/:repo_id/files/:file_path/comments" $
        handleAddFileComment service

    get "/api/v1/browse/:repo_id/files/:file_path/comments" $
        handleGetFileComments service

    -- Syntax configuration
    get "/api/v1/browse/syntax/languages" $
        handleListLanguages service

    get "/api/v1/browse/syntax/themes" $
        handleListThemes service

    post "/api/v1/browse/syntax/custom-rules" $
        handleAddCustomSyntaxRules service
