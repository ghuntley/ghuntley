{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.VoteService
    ( -- * Types
      VoteService(..)
    , VoteError(..)
      -- * Operations
    , initVoteService
    , createVote
    , updateVote
    , getVote
    , listVotes
    , deleteVote
    , getVotesByCategory
    , getVotesByUser
    , checkSubmitCriteria
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql

import Gerrit.Models.Vote
import Gerrit.Models.Revision (Revision)
import Gerrit.Services.NotificationService (NotificationService)
import Gerrit.Services.MetricsService (MetricsService)

-- | Vote service errors
data VoteError
    = VoteNotFound Text
    | RevisionNotFound Text
    | InvalidVote Text
    | DatabaseError Text
    | ValidationError Text
    | PermissionDenied Text
    deriving (Show, Eq)

-- | Vote service
data VoteService = VoteService
    { votePool :: ConnectionPool
    , notificationService :: NotificationService
    , metricsService :: MetricsService
    }

-- | Initialize the vote service
initVoteService :: ConnectionPool
                -> NotificationService
                -> MetricsService
                -> VoteService
initVoteService pool notifService metricsService =
    VoteService
        { votePool = pool
        , notificationService = notifService
        , metricsService = metricsService
        }

-- | Create a new vote
createVote :: MonadIO m
           => VoteService
           -> Text  -- ^ Revision ID
           -> Text  -- ^ Voter ID
           -> VoteValue  -- ^ Vote value
           -> VoteCategory  -- ^ Vote category
           -> Maybe Text  -- ^ Optional message
           -> m (Either VoteError (Entity Vote))
createVote VoteService{..} revisionId voterId value category message = do
    -- Validate revision exists
    revisionExists <- runSqlPool (exists [RevisionRevisionId ==. revisionId]) votePool
    if not revisionExists
        then return $ Left $ RevisionNotFound revisionId
        else do
            -- Validate vote
            case validateVote value category message of
                Left err -> return $ Left err
                Right _ -> do
                    -- Create vote
                    result <- createVote votePool revisionId voterId value category message
                    -- Send notification
                    liftIO $ notifyVoteCreated notificationService result
                    -- Record metrics
                    liftIO $ recordVoteMetrics metricsService "create"
                    return $ Right result

-- | Update a vote
updateVote :: MonadIO m
           => VoteService
           -> Text  -- ^ Vote ID
           -> VoteValue  -- ^ New vote value
           -> Maybe Text  -- ^ New message
           -> m (Either VoteError (Entity Vote))
updateVote VoteService{..} voteId newValue newMessage = do
    -- Get existing vote
    maybeVote <- runSqlPool (getBy $ UniqueVoteId voteId) votePool
    case maybeVote of
        Nothing -> return $ Left $ VoteNotFound voteId
        Just vote -> do
            -- Validate new vote value
            case validateVoteValue newValue of
                Left err -> return $ Left err
                Right _ -> do
                    -- Update vote
                    result <- updateVote votePool vote newValue newMessage
                    -- Send notification
                    liftIO $ notifyVoteUpdated notificationService result
                    -- Record metrics
                    liftIO $ recordVoteMetrics metricsService "update"
                    return $ Right result

-- | Get a vote by ID
getVote :: MonadIO m
        => VoteService
        -> Text  -- ^ Vote ID
        -> m (Either VoteError (Entity Vote))
getVote VoteService{..} voteId = do
    maybeVote <- runSqlPool (getBy $ UniqueVoteId voteId) votePool
    return $ case maybeVote of
        Nothing -> Left $ VoteNotFound voteId
        Just vote -> Right vote

-- | List votes for a revision
listVotes :: MonadIO m
          => VoteService
          -> Text  -- ^ Revision ID
          -> m (Either VoteError [Entity Vote])
listVotes VoteService{..} revisionId = do
    -- Validate revision exists
    revisionExists <- runSqlPool (exists [RevisionRevisionId ==. revisionId]) votePool
    if not revisionExists
        then return $ Left $ RevisionNotFound revisionId
        else do
            votes <- getRevisionVotes votePool revisionId
            return $ Right votes

-- | Delete a vote
deleteVote :: MonadIO m
           => VoteService
           -> Text  -- ^ Vote ID
           -> m (Either VoteError ())
deleteVote VoteService{..} voteId = do
    maybeVote <- runSqlPool (getBy $ UniqueVoteId voteId) votePool
    case maybeVote of
        Nothing -> return $ Left $ VoteNotFound voteId
        Just vote -> do
            deleteVote votePool vote
            -- Send notification
            liftIO $ notifyVoteDeleted notificationService vote
            -- Record metrics
            liftIO $ recordVoteMetrics metricsService "delete"
            return $ Right ()

-- | Get votes by category
getVotesByCategory :: MonadIO m
                   => VoteService
                   -> Text  -- ^ Revision ID
                   -> VoteCategory  -- ^ Vote category
                   -> m (Either VoteError [Entity Vote])
getVotesByCategory VoteService{..} revisionId category = do
    -- Validate revision exists
    revisionExists <- runSqlPool (exists [RevisionRevisionId ==. revisionId]) votePool
    if not revisionExists
        then return $ Left $ RevisionNotFound revisionId
        else do
            votes <- runSqlPool (selectList
                [ VoteRevisionId ==. revisionId
                , VoteCategory ==. category
                ] [Asc VoteCreated]) votePool
            return $ Right votes

-- | Get votes by user
getVotesByUser :: MonadIO m
                => VoteService
                -> Text  -- ^ User ID
                -> m (Either VoteError [Entity Vote])
getVotesByUser VoteService{..} userId = do
    votes <- getUserVotes votePool userId
    return $ Right votes

-- | Check if a revision can be submitted based on votes
checkSubmitCriteria :: MonadIO m
                    => VoteService
                    -> Text  -- ^ Revision ID
                    -> m (Either VoteError Bool)
checkSubmitCriteria VoteService{..} revisionId = do
    -- Get all votes for the revision
    votes <- getRevisionVotes votePool revisionId
    let voteMap = groupVotesByCategory votes
    return $ Right $ evaluateSubmitCriteria voteMap

-- Helper functions

-- | Validate a vote
validateVote :: VoteValue -> VoteCategory -> Maybe Text -> Either VoteError ()
validateVote value category message = do
    validateVoteValue value
    validateVoteCategory category
    validateVoteMessage message

-- | Validate vote value
validateVoteValue :: VoteValue -> Either VoteError ()
validateVoteValue _ = Right ()  -- All vote values are valid by construction

-- | Validate vote category
validateVoteCategory :: VoteCategory -> Either VoteError ()
validateVoteCategory (CustomCategory t)
    | Text.null t = Left $ ValidationError "Custom category cannot be empty"
    | Text.length t > 50 = Left $ ValidationError "Custom category too long"
    | otherwise = Right ()
validateVoteCategory _ = Right ()

-- | Validate vote message
validateVoteMessage :: Maybe Text -> Either VoteError ()
validateVoteMessage Nothing = Right ()
validateVoteMessage (Just msg)
    | Text.length msg > 1000 = Left $ ValidationError "Vote message too long"
    | otherwise = Right ()

-- | Group votes by category
groupVotesByCategory :: [Entity Vote] -> Map VoteCategory [Entity Vote]
groupVotesByCategory votes =
    Map.fromListWith (++) [(voteCategory $ entityVal v, [v]) | v <- votes]

-- | Evaluate submit criteria based on votes
evaluateSubmitCriteria :: Map VoteCategory [Entity Vote] -> Bool
evaluateSubmitCriteria voteMap =
    let hasNegativeVotes = any (hasVoteValue [VoteNegativeTwo, VoteNegativeOne]) (Map.elems voteMap)
        hasRequiredApprovals = all hasRequiredApproval requiredCategories
    in not hasNegativeVotes && hasRequiredApprovals
  where
    requiredCategories = [CodeReview, VerifiedBuild]  -- Categories required for submission
    hasVoteValue values = any (\v -> voteValue (entityVal v) `elem` values)
    hasRequiredApproval category =
        case Map.lookup category voteMap of
            Nothing -> False
            Just votes -> any (\v -> voteValue (entityVal v) == VotePositiveTwo) votes

-- | Helper function to notify about vote creation
notifyVoteCreated :: NotificationService -> Entity Vote -> IO ()
notifyVoteCreated = undefined  -- TODO: Implement notification

-- | Helper function to notify about vote updates
notifyVoteUpdated :: NotificationService -> Entity Vote -> IO ()
notifyVoteUpdated = undefined  -- TODO: Implement notification

-- | Helper function to notify about vote deletion
notifyVoteDeleted :: NotificationService -> Entity Vote -> IO ()
notifyVoteDeleted = undefined  -- TODO: Implement notification

-- | Helper function to record vote metrics
recordVoteMetrics :: MetricsService -> Text -> IO ()
recordVoteMetrics = undefined  -- TODO: Implement metrics recording
