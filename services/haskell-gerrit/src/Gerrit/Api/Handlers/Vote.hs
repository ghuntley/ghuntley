{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Vote
    ( -- * Handlers
      handleCreateVote
    , handleUpdateVote
    , handleGetVote
    , handleListVotes
    , handleDeleteVote
    , handleGetVotesByCategory
    , handleGetVotesByUser
    , handleCheckSubmitCriteria
    ) where

import Control.Monad.IO.Class (MonadIO)
import Data.Aeson
import Data.Text (Text)
import Web.Scotty.Trans

import Gerrit.Api.Error
import Gerrit.Models.Vote
import Gerrit.Services.VoteService

-- | Request body for creating a vote
data CreateVoteRequest = CreateVoteRequest
    { createRevisionId :: Text
    , createValue :: VoteValue
    , createCategory :: VoteCategory
    , createMessage :: Maybe Text
    } deriving (Show)

instance FromJSON CreateVoteRequest where
    parseJSON = withObject "CreateVoteRequest" $ \v -> CreateVoteRequest
        <$> v .: "revision_id"
        <*> v .: "value"
        <*> v .: "category"
        <*> v .:? "message"

-- | Request body for updating a vote
data UpdateVoteRequest = UpdateVoteRequest
    { updateValue :: VoteValue
    , updateMessage :: Maybe Text
    } deriving (Show)

instance FromJSON UpdateVoteRequest where
    parseJSON = withObject "UpdateVoteRequest" $ \v -> UpdateVoteRequest
        <$> v .: "value"
        <*> v .:? "message"

-- | Handle creating a new vote
handleCreateVote :: MonadIO m
                => VoteService
                -> ActionT ApiError m ()
handleCreateVote service = do
    userId <- requireUserId
    CreateVoteRequest{..} <- jsonData
    result <- lift $ createVote service
        createRevisionId
        userId
        createValue
        createCategory
        createMessage
    case result of
        Left err -> handleVoteError err
        Right vote -> json vote

-- | Handle updating a vote
handleUpdateVote :: MonadIO m
                => VoteService
                -> Text  -- ^ Vote ID
                -> ActionT ApiError m ()
handleUpdateVote service voteId = do
    UpdateVoteRequest{..} <- jsonData
    result <- lift $ updateVote service voteId updateValue updateMessage
    case result of
        Left err -> handleVoteError err
        Right vote -> json vote

-- | Handle getting a vote
handleGetVote :: MonadIO m
              => VoteService
              -> Text  -- ^ Vote ID
              -> ActionT ApiError m ()
handleGetVote service voteId = do
    result <- lift $ getVote service voteId
    case result of
        Left err -> handleVoteError err
        Right vote -> json vote

-- | Handle listing votes for a revision
handleListVotes :: MonadIO m
                => VoteService
                -> ActionT ApiError m ()
handleListVotes service = do
    revisionId <- param "revision_id"
    result <- lift $ listVotes service revisionId
    case result of
        Left err -> handleVoteError err
        Right votes -> json votes

-- | Handle deleting a vote
handleDeleteVote :: MonadIO m
                => VoteService
                -> Text  -- ^ Vote ID
                -> ActionT ApiError m ()
handleDeleteVote service voteId = do
    result <- lift $ deleteVote service voteId
    case result of
        Left err -> handleVoteError err
        Right _ -> status noContent204

-- | Handle getting votes by category
handleGetVotesByCategory :: MonadIO m
                        => VoteService
                        -> ActionT ApiError m ()
handleGetVotesByCategory service = do
    revisionId <- param "revision_id"
    category <- param "category"
    result <- lift $ getVotesByCategory service revisionId category
    case result of
        Left err -> handleVoteError err
        Right votes -> json votes

-- | Handle getting votes by user
handleGetVotesByUser :: MonadIO m
                     => VoteService
                     -> ActionT ApiError m ()
handleGetVotesByUser service = do
    userId <- param "user_id"
    result <- lift $ getVotesByUser service userId
    case result of
        Left err -> handleVoteError err
        Right votes -> json votes

-- | Handle checking submit criteria
handleCheckSubmitCriteria :: MonadIO m
                         => VoteService
                         -> ActionT ApiError m ()
handleCheckSubmitCriteria service = do
    revisionId <- param "revision_id"
    result <- lift $ checkSubmitCriteria service revisionId
    case result of
        Left err -> handleVoteError err
        Right canSubmit -> json $ object ["can_submit" .= canSubmit]

-- | Helper function to handle vote errors
handleVoteError :: MonadIO m => VoteError -> ActionT ApiError m ()
handleVoteError err = case err of
    VoteNotFound msg -> notFound $ "Vote not found: " <> msg
    RevisionNotFound msg -> notFound $ "Revision not found: " <> msg
    InvalidVote msg -> badRequest $ "Invalid vote: " <> msg
    DatabaseError msg -> internalError $ "Database error: " <> msg
    ValidationError msg -> badRequest $ "Validation error: " <> msg
    PermissionDenied msg -> forbidden $ "Permission denied: " <> msg

-- | Helper function to require a user ID from the request
requireUserId :: MonadIO m => ActionT ApiError m Text
requireUserId = do
    maybeUserId <- header "X-User-Id"
    case maybeUserId of
        Nothing -> unauthorized "User ID not provided"
        Just userId -> return userId
