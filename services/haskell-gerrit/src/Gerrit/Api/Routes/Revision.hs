{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.Revision
    ( revisionRoutes
    ) where

import Web.Scotty.Trans

import Gerrit.Api.Error (ApiError)
import Gerrit.Api.Handlers.Revision
import Gerrit.Services.RevisionService (RevisionService)

-- | Revision routes
revisionRoutes :: RevisionService -> ScottyT ApiError IO ()
revisionRoutes service = do
    -- Create revision
    post "/api/revisions" $
        handleCreateRevision service

    -- Update revision
    put "/api/revisions/:revision_id" $ do
        revisionId <- param "revision_id"
        handleUpdateRevision service revisionId

    -- Get revision
    get "/api/revisions/:revision_id" $ do
        revisionId <- param "revision_id"
        handleGetRevision service revisionId

    -- List revisions for a change
    get "/api/revisions" $
        handleListRevisions service

    -- Get latest revision for a change
    get "/api/revisions/latest" $
        handleGetLatestRevision service

    -- Delete revision
    delete "/api/revisions/:revision_id" $ do
        revisionId <- param "revision_id"
        handleDeleteRevision service revisionId

    -- Analyze revision changes
    get "/api/revisions/:revision_id/analysis" $ do
        revisionId <- param "revision_id"
        handleAnalyzeRevision service revisionId

    -- Get revision statistics
    get "/api/revisions/:revision_id/stats" $ do
        revisionId <- param "revision_id"
        handleGetRevisionStats service revisionId

    -- Get revision diff
    get "/api/revisions/:revision_id/diff" $ do
        revisionId <- param "revision_id"
        handleGetRevisionDiff service revisionId
