{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.MergeQueue
    ( -- * Queue Operations
      handleCreateQueue
    , handleGetQueue
    , handleListQueues
      -- * Entry Operations
    , handleEnqueueChange
    , handleDequeueChange
    , handleUpdateEntryStatus
    , handleGetQueueEntry
    , handleListQueueEntries
      -- * Queue Processing
    , handleProcessQueue
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (getCurrentTime)
import Network.HTTP.Types.Status
import Web.Scotty.Trans

import Gerrit.Api.Types
import Gerrit.Models.Change
import Gerrit.Models.MergeQueue
import Gerrit.Services.MergeQueueService
import qualified Gerrit.Services.MergeQueueService as MergeQueue
import Gerrit.Api.Utils (requireUserId, jsonError)

-- | Request body for creating a queue
data CreateQueueRequest = CreateQueueRequest
    { cqrProjectId :: Text
    , cqrBranch :: Text
    , cqrMaxConcurrent :: Int
    , cqrRetryLimit :: Int
    } deriving (Show, Eq)

instance FromJSON CreateQueueRequest where
    parseJSON = withObject "CreateQueueRequest" $ \v -> CreateQueueRequest
        <$> v .: "project_id"
        <*> v .: "branch"
        <*> v .: "max_concurrent"
        <*> v .: "retry_limit"

-- | Request body for enqueueing a change
data EnqueueChangeRequest = EnqueueChangeRequest
    { ecrChangeId :: Text
    , ecrPriority :: MergePriority
    , ecrDependencies :: [Text]
    , ecrMetadata :: Maybe Value
    } deriving (Show, Eq)

instance FromJSON EnqueueChangeRequest where
    parseJSON = withObject "EnqueueChangeRequest" $ \v -> EnqueueChangeRequest
        <$> v .: "change_id"
        <*> v .: "priority"
        <*> v .:? "dependencies" .!= []
        <*> v .:? "metadata"

-- | Request body for updating entry status
data UpdateEntryStatusRequest = UpdateEntryStatusRequest
    { uesrStatus :: MergeStatus
    , uesrConflict :: Maybe MergeConflict
    } deriving (Show, Eq)

instance FromJSON UpdateEntryStatusRequest where
    parseJSON = withObject "UpdateEntryStatusRequest" $ \v -> UpdateEntryStatusRequest
        <$> v .: "status"
        <*> v .:? "conflict"

-- | Handle merge queue errors
handleMergeQueueError :: MonadIO m => MergeQueueError -> ActionT m ()
handleMergeQueueError err = case err of
    QueueNotFound qId -> jsonError status404 $ "Queue not found: " <> qId
    EntryNotFound eId -> jsonError status404 $ "Queue entry not found: " <> eId
    ChangeNotFound cId -> jsonError status404 $ "Change not found: " <> cId
    DependencyError msg -> jsonError status400 $ "Dependency error: " <> msg
    ConflictError msg -> jsonError status409 $ "Conflict error: " <> msg
    ValidationError msg -> jsonError status400 $ "Validation error: " <> msg
    DatabaseError msg -> jsonError status500 $ "Database error: " <> msg
    VCSError msg -> jsonError status500 $ "VCS error: " <> msg

-- | Create a new merge queue
handleCreateQueue :: MonadIO m => MergeQueueService -> ActionT m ()
handleCreateQueue service = do
    userId <- requireUserId
    req <- jsonData
    result <- lift $ createMergeQueue service
        (cqrProjectId req)
        (cqrBranch req)
        (cqrMaxConcurrent req)
        (cqrRetryLimit req)
    case result of
        Left err -> handleMergeQueueError err
        Right queue -> json queue

-- | Get a queue by ID
handleGetQueue :: MonadIO m => MergeQueueService -> ActionT m ()
handleGetQueue service = do
    userId <- requireUserId
    queueId <- param "queue_id"
    result <- lift $ getQueue service queueId
    case result of
        Left err -> handleMergeQueueError err
        Right queue -> json queue

-- | List all queues
handleListQueues :: MonadIO m => MergeQueueService -> ActionT m ()
handleListQueues service = do
    userId <- requireUserId
    queues <- lift $ listQueues service
    json queues

-- | Enqueue a change
handleEnqueueChange :: MonadIO m => MergeQueueService -> ActionT m ()
handleEnqueueChange service = do
    userId <- requireUserId
    queueId <- param "queue_id"
    req <- jsonData
    result <- lift $ enqueueChange service
        queueId
        (ecrChangeId req)
        (ecrPriority req)
        (ecrDependencies req)
        (ecrMetadata req)
    case result of
        Left err -> handleMergeQueueError err
        Right entry -> json entry

-- | Dequeue a change
handleDequeueChange :: MonadIO m => MergeQueueService -> ActionT m ()
handleDequeueChange service = do
    userId <- requireUserId
    entryId <- param "entry_id"
    result <- lift $ dequeueChange service entryId
    case result of
        Left err -> handleMergeQueueError err
        Right _ -> status status204

-- | Update entry status
handleUpdateEntryStatus :: MonadIO m => MergeQueueService -> ActionT m ()
handleUpdateEntryStatus service = do
    userId <- requireUserId
    entryId <- param "entry_id"
    req <- jsonData
    result <- lift $ updateEntryStatus service
        entryId
        (uesrStatus req)
        (uesrConflict req)
    case result of
        Left err -> handleMergeQueueError err
        Right entry -> json entry

-- | Get a queue entry
handleGetQueueEntry :: MonadIO m => MergeQueueService -> ActionT m ()
handleGetQueueEntry service = do
    userId <- requireUserId
    entryId <- param "entry_id"
    result <- lift $ getQueueEntry service entryId
    case result of
        Left err -> handleMergeQueueError err
        Right entry -> json entry

-- | List entries in a queue
handleListQueueEntries :: MonadIO m => MergeQueueService -> ActionT m ()
handleListQueueEntries service = do
    userId <- requireUserId
    queueId <- param "queue_id"
    entries <- lift $ listQueueEntries service queueId
    json entries

-- | Process a queue
handleProcessQueue :: MonadIO m => MergeQueueService -> ActionT m ()
handleProcessQueue service = do
    userId <- requireUserId
    queueId <- param "queue_id"
    result <- lift $ processQueue service queueId
    case result of
        Left err -> handleMergeQueueError err
        Right _ -> status status202
