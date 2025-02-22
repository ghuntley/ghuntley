{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.MergeQueueService
    ( -- * Types
      MergeQueueService(..)
    , MergeQueueError(..)
    , MergePriority(..)
    , MergeQueueStatus(..)
      -- * Service Creation
    , initMergeQueueService
      -- * Core Operations
    , createMergeQueue
    , enqueueChange
    , dequeueChange
    , processQueue
    , updateEntryStatus
      -- * Query Operations
    , getQueue
    , getQueueEntry
    , listQueues
    , listQueueEntries
      -- * Validation
    , validateMerge
    , checkDependencies
    , checkConflicts
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (ReaderT)
import Data.Aeson (Value)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (getCurrentTime)
import Database.Persist.Sql (ConnectionPool)

import Gerrit.Models.MergeQueue
import Gerrit.Models.Change (Change)
import Gerrit.Services.NotificationService (NotificationService)
import Gerrit.Services.MetricsService (MetricsService)
import Gerrit.Services.VCSService (VCSService)

-- | MergeQueue service errors
data MergeQueueError
    = QueueNotFound Text
    | EntryNotFound Text
    | ChangeNotFound Text
    | DependencyError Text
    | ConflictError Text
    | ValidationError Text
    | DatabaseError Text
    | VCSError Text
    deriving (Show, Eq)

-- | Merge priority levels
data MergePriority
    = Critical  -- ^ Highest priority, process immediately
    | High     -- ^ High priority, process next
    | Normal   -- ^ Normal priority
    | Low      -- ^ Low priority, process last
    deriving (Show, Read, Eq, Ord)

-- | Merge queue status
data MergeQueueStatus
    = Queued      -- ^ Change is queued for merging
    | Processing  -- ^ Change is being processed
    | Merged      -- ^ Change has been merged
    | Failed Text -- ^ Change failed to merge with reason
    | Conflicted  -- ^ Change has conflicts
    deriving (Show, Read, Eq)

-- | MergeQueue service
data MergeQueueService = MergeQueueService
    { mqsConnPool :: ConnectionPool
    , mqsNotificationService :: NotificationService
    , mqsMetricsService :: MetricsService
    , mqsVCSService :: VCSService
    }

-- | Initialize the merge queue service
initMergeQueueService :: ConnectionPool
                     -> NotificationService
                     -> MetricsService
                     -> VCSService
                     -> MergeQueueService
initMergeQueueService pool notifService metricsService vcsService =
    MergeQueueService
        { mqsConnPool = pool
        , mqsNotificationService = notifService
        , mqsMetricsService = metricsService
        , mqsVCSService = vcsService
        }

-- | Create a new merge queue
createMergeQueue :: MonadIO m
                => MergeQueueService
                -> Text  -- ^ Project ID
                -> Text  -- ^ Branch
                -> Int   -- ^ Max concurrent merges
                -> Int   -- ^ Retry limit
                -> m (Either MergeQueueError (Entity MergeQueue))
createMergeQueue MergeQueueService{..} projectId branch maxConcurrent retryLimit = do
    result <- runDB mqsConnPool $ createQueue projectId branch maxConcurrent retryLimit
    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right queue -> do
            -- Record metrics
            recordQueueCreation mqsMetricsService queue
            return $ Right queue

-- | Enqueue a change for merging
enqueueChange :: MonadIO m
              => MergeQueueService
              -> Text  -- ^ Queue ID
              -> Text  -- ^ Change ID
              -> MergePriority  -- ^ Priority
              -> [Text]  -- ^ Dependencies
              -> Maybe Value  -- ^ Additional metadata
              -> m (Either MergeQueueError (Entity MergeQueueEntry))
enqueueChange MergeQueueService{..} queueId changeId priority deps metadata = do
    -- Validate dependencies
    depCheck <- checkDependencies mqsVCSService deps
    case depCheck of
        Left err -> return $ Left err
        Right _ -> do
            -- Check for conflicts
            conflictCheck <- checkConflicts mqsVCSService changeId deps
            case conflictCheck of
                Left err -> return $ Left err
                Right _ -> do
                    -- Enqueue the change
                    result <- runDB mqsConnPool $ enqueueChange queueId changeId priority deps metadata
                    case result of
                        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
                        Right entry -> do
                            -- Send notifications
                            notifyChangeEnqueued mqsNotificationService entry
                            -- Record metrics
                            recordChangeEnqueued mqsMetricsService entry
                            return $ Right entry

-- | Dequeue a change
dequeueChange :: MonadIO m
              => MergeQueueService
              -> Text  -- ^ Entry ID
              -> m (Either MergeQueueError ())
dequeueChange MergeQueueService{..} entryId = do
    -- Get entry first to ensure it exists
    entry <- runDB mqsConnPool $ getEntryById entryId
    case entry of
        Nothing -> return $ Left $ EntryNotFound entryId
        Just e -> do
            -- Dequeue the change
            runDB mqsConnPool $ dequeueChange entryId
            -- Send notifications
            notifyChangeDequeued mqsNotificationService e
            -- Record metrics
            recordChangeDequeued mqsMetricsService e
            return $ Right ()

-- | Process the merge queue
processQueue :: MonadIO m
             => MergeQueueService
             -> Text  -- ^ Queue ID
             -> m (Either MergeQueueError ())
processQueue MergeQueueService{..} queueId = do
    -- Get queue configuration
    queue <- runDB mqsConnPool $ getQueueById queueId
    case queue of
        Nothing -> return $ Left $ QueueNotFound queueId
        Just (Entity _ q) -> do
            -- Get queued entries ordered by priority
            entries <- runDB mqsConnPool $ getEntriesByStatus queueId Queued
            -- Process entries up to max concurrent limit
            let toProcess = take (mergeQueueMaxConcurrent q) entries
            mapM_ (processEntry mqsVCSService) toProcess
            return $ Right ()

-- | Update entry status
updateEntryStatus :: MonadIO m
                  => MergeQueueService
                  -> Text  -- ^ Entry ID
                  -> MergeStatus  -- ^ New status
                  -> Maybe MergeConflict  -- ^ Conflict info if any
                  -> m (Either MergeQueueError (Entity MergeQueueEntry))
updateEntryStatus MergeQueueService{..} entryId status conflict = do
    result <- runDB mqsConnPool $ updateEntryStatus entryId status conflict
    case result of
        Nothing -> return $ Left $ EntryNotFound entryId
        Just entry -> do
            -- Send notifications
            notifyStatusUpdated mqsNotificationService entry status
            -- Record metrics
            recordStatusUpdated mqsMetricsService entry status
            return $ Right entry

-- | Get a queue by ID
getQueue :: MonadIO m
         => MergeQueueService
         -> Text  -- ^ Queue ID
         -> m (Either MergeQueueError (Entity MergeQueue))
getQueue MergeQueueService{..} queueId = do
    result <- runDB mqsConnPool $ getQueueById queueId
    case result of
        Nothing -> return $ Left $ QueueNotFound queueId
        Just queue -> return $ Right queue

-- | Get a queue entry by ID
getQueueEntry :: MonadIO m
              => MergeQueueService
              -> Text  -- ^ Entry ID
              -> m (Either MergeQueueError (Entity MergeQueueEntry))
getQueueEntry MergeQueueService{..} entryId = do
    result <- runDB mqsConnPool $ getEntryById entryId
    case result of
        Nothing -> return $ Left $ EntryNotFound entryId
        Just entry -> return $ Right entry

-- | List all queues
listQueues :: MonadIO m
           => MergeQueueService
           -> m [Entity MergeQueue]
listQueues MergeQueueService{..} =
    runDB mqsConnPool $ selectList [] [Asc MergeQueueCreated]

-- | List entries in a queue
listQueueEntries :: MonadIO m
                 => MergeQueueService
                 -> Text  -- ^ Queue ID
                 -> m [Entity MergeQueueEntry]
listQueueEntries MergeQueueService{..} queueId =
    runDB mqsConnPool $ getQueueEntries queueId

-- | Validate a merge
validateMerge :: MonadIO m
              => MergeQueueService
              -> Text  -- ^ Change ID
              -> [Text]  -- ^ Dependencies
              -> m (Either MergeQueueError ())
validateMerge MergeQueueService{..} changeId deps = do
    -- Check dependencies
    depCheck <- checkDependencies mqsVCSService deps
    case depCheck of
        Left err -> return $ Left err
        Right _ -> do
            -- Check for conflicts
            conflictCheck <- checkConflicts mqsVCSService changeId deps
            case conflictCheck of
                Left err -> return $ Left err
                Right _ -> return $ Right ()

-- | Check dependencies
checkDependencies :: MonadIO m
                  => VCSService
                  -> [Text]  -- ^ Dependencies
                  -> m (Either MergeQueueError ())
checkDependencies vcsService deps = do
    -- TODO: Implement dependency checking using VCS service
    return $ Right ()

-- | Check for conflicts
checkConflicts :: MonadIO m
               => VCSService
               -> Text  -- ^ Change ID
               -> [Text]  -- ^ Dependencies
               -> m (Either MergeQueueError ())
checkConflicts vcsService changeId deps = do
    -- TODO: Implement conflict checking using VCS service
    return $ Right ()

-- | Process a single entry
processEntry :: MonadIO m
             => VCSService
             -> Entity MergeQueueEntry
             -> m ()
processEntry vcsService entry = do
    -- TODO: Implement entry processing using VCS service
    return ()

-- | Helper functions for notifications
notifyChangeEnqueued :: MonadIO m
                     => NotificationService
                     -> Entity MergeQueueEntry
                     -> m ()
notifyChangeEnqueued notifService entry = do
    -- TODO: Implement notification
    return ()

notifyChangeDequeued :: MonadIO m
                     => NotificationService
                     -> Entity MergeQueueEntry
                     -> m ()
notifyChangeDequeued notifService entry = do
    -- TODO: Implement notification
    return ()

notifyStatusUpdated :: MonadIO m
                    => NotificationService
                    -> Entity MergeQueueEntry
                    -> MergeStatus
                    -> m ()
notifyStatusUpdated notifService entry status = do
    -- TODO: Implement notification
    return ()

-- | Helper functions for metrics
recordQueueCreation :: MonadIO m
                    => MetricsService
                    -> Entity MergeQueue
                    -> m ()
recordQueueCreation metricsService queue = do
    -- TODO: Implement metrics recording
    return ()

recordChangeEnqueued :: MonadIO m
                     => MetricsService
                     -> Entity MergeQueueEntry
                     -> m ()
recordChangeEnqueued metricsService entry = do
    -- TODO: Implement metrics recording
    return ()

recordChangeDequeued :: MonadIO m
                     => MetricsService
                     -> Entity MergeQueueEntry
                     -> m ()
recordChangeDequeued metricsService entry = do
    -- TODO: Implement metrics recording
    return ()

recordStatusUpdated :: MonadIO m
                    => MetricsService
                    -> Entity MergeQueueEntry
                    -> MergeStatus
                    -> m ()
recordStatusUpdated metricsService entry status = do
    -- TODO: Implement metrics recording
    return ()
