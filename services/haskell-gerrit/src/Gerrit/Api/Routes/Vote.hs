{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.Vote
    ( voteRoutes
    ) where

import Web.Scotty.Trans

import Gerrit.Api.Error
import Gerrit.Api.Handlers.Vote
import Gerrit.Services.VoteService

-- | Define routes for vote operations
voteRoutes :: MonadIO m => VoteService -> ScottyT ApiError m ()
voteRoutes service = do
    -- Create a new vote
    post "/votes" $
        handleCreateVote service

    -- Update a vote
    put "/votes/:vote_id" $ do
        voteId <- param "vote_id"
        handleUpdateVote service voteId

    -- Get a vote by ID
    get "/votes/:vote_id" $ do
        voteId <- param "vote_id"
        handleGetVote service voteId

    -- List votes for a revision
    get "/revisions/:revision_id/votes" $
        handleListVotes service

    -- Delete a vote
    delete "/votes/:vote_id" $ do
        voteId <- param "vote_id"
        handleDeleteVote service voteId

    -- Get votes by category for a revision
    get "/revisions/:revision_id/votes/category/:category" $
        handleGetVotesByCategory service

    -- Get votes by user
    get "/users/:user_id/votes" $
        handleGetVotesByUser service

    -- Check submit criteria for a revision
    get "/revisions/:revision_id/submit-criteria" $
        handleCheckSubmitCriteria service
