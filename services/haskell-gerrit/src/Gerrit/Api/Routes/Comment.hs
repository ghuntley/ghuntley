{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.Comment
    ( commentRoutes
    ) where

import Web.Scotty.Trans

import Gerrit.Api.Error (ApiError)
import Gerrit.Api.Handlers.Comment
import Gerrit.Services.CommentService (CommentService)

-- | Comment routes
commentRoutes :: CommentService -> ScottyT ApiError IO ()
commentRoutes service = do
    -- Create comment
    post "/api/comments" $
        handleCreateComment service

    -- Update comment
    put "/api/comments/:comment_id" $ do
        commentId <- param "comment_id"
        handleUpdateComment service commentId

    -- Get comment
    get "/api/comments/:comment_id" $ do
        commentId <- param "comment_id"
        handleGetComment service commentId

    -- List comments for a revision
    get "/api/revisions/:revision_id/comments" $
        handleListComments service

    -- Resolve comment
    post "/api/comments/:comment_id/resolve" $ do
        commentId <- param "comment_id"
        handleResolveComment service commentId

    -- Unresolve comment
    post "/api/comments/:comment_id/unresolve" $ do
        commentId <- param "comment_id"
        handleUnresolveComment service commentId

    -- Delete comment
    delete "/api/comments/:comment_id" $ do
        commentId <- param "comment_id"
        handleDeleteComment service commentId

    -- Get comments for a file
    get "/api/revisions/:revision_id/files/:file_path/comments" $
        handleGetFileComments service

    -- Get comments in a thread
    get "/api/comments/:comment_id/thread" $ do
        commentId <- param "comment_id"
        handleGetThreadComments service commentId
