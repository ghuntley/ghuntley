-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}

module Gerrit.Models.MergeQueue
    ( -- * Types
      MergeQueue(..)
    , MergeQueueEntry(..)
    , MergeQueueId
    , MergeEntryId
    , MergePriority(..)
    , MergeStatus(..)
    , MergeConflict(..)
    , VCSType(..)
    , MergeQueuePriority(..)
      -- * Operations
    , createQueue
    , enqueueChange
    , dequeueChange
    , updateEntryStatus
    , getQueueById
    , getQueueEntries
    , getEntryById
    , getEntriesByStatus
    , getEntriesByPriority
    , migrateAll
    , createMergeQueue
    , updateMergeQueue
    , getMergeQueueById
    , listMergeQueues
    , addToMergeQueue
    , removeFromMergeQueue
    , updateEntryPriority
    , getNextMergeEntry
    , listQueueEntries
    , createQueueEntry
    , getQueueEntry
    , updateQueueEntry
    , deleteQueueEntry
    , updateQueueEntryStatus
    , updateQueueEntryAttempts
    , getEntriesForChange
    , cleanupMergedEntries
    , cleanupFailedEntries
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Change (Change)

-- | VCS type
data VCSType
    = Git
    | Mercurial
    | JJ
    deriving (Show, Read, Eq, Generic)
derivePersistField "VCSType"

-- | Merge queue status
data MergeQueueStatus
    = Active
    | Paused
    | Disabled
    deriving (Show, Read, Eq, Generic)
derivePersistField "MergeQueueStatus"

-- | Merge queue priority
data MergeQueuePriority
    = Highest
    | High
    | Normal
    | Low
    | Lowest
    deriving (Show, Read, Eq, Generic, Ord)
derivePersistField "MergeQueuePriority"

-- | Merge priority levels
data MergePriority
    = PriorityLow
    | PriorityNormal
    | PriorityHigh
    | PriorityCritical
    deriving (Show, Read, Eq, Ord, Generic)
derivePersistField "MergePriority"

-- | Merge status
data MergeStatus
    = Queued        -- ^ Change is queued for merging
    | InProgress    -- ^ Currently being merged
    | Merged        -- ^ Successfully merged
    | Failed        -- ^ Failed to merge
    | Conflicted    -- ^ Has conflicts
    | Abandoned     -- ^ Abandoned from queue
    deriving (Show, Read, Eq, Generic)
derivePersistField "MergeStatus"

-- | Merge conflict information
data MergeConflict = MergeConflict
    { conflictFiles :: [Text]      -- ^ Files with conflicts
    , conflictDetails :: Text      -- ^ Detailed conflict information
    , conflictTimestamp :: UTCTime -- ^ When conflict was detected
    } deriving (Show, Read, Eq, Generic)
derivePersistField "MergeConflict"

-- | Define the merge queue entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
MergeQueue
    queueId Text
    projectId Text
    branch Text
    maxConcurrent Int
    retryLimit Int
    created UTCTime
    updated UTCTime
    UniqueQueueId queueId
    deriving Show Eq Generic

MergeQueueEntry
    entryId Text
    queueId Text
    changeId Text
    priority MergePriority
    status MergeStatus
    dependencies [Text]
    retryCount Int default=0
    conflict MergeConflict Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueEntryId entryId
    Foreign MergeQueue queueId References mergeQueues OnDeleteCascade
    Foreign Change changeId References changes OnDeleteCascade
    deriving Show Eq Generic
|]

instance ToJSON (Entity MergeQueueEntry)
instance FromJSON (Entity MergeQueueEntry)
instance ToJSON MergeQueueEntry
instance FromJSON MergeQueueEntry

-- | Create a new merge queue
createQueue :: MonadIO m
            => Text  -- ^ Project ID
            -> Text  -- ^ Branch
            -> Int   -- ^ Max concurrent merges
            -> Int   -- ^ Retry limit
            -> m (Entity MergeQueue)
createQueue projectId' branch' maxConcurrent' retryLimit' = do
    now <- liftIO getCurrentTime
    let queueId' = generateQueueId projectId' branch' now
    let queue = MergeQueue
            { mergeQueueQueueId = queueId'
            , mergeQueueProjectId = projectId'
            , mergeQueueBranch = branch'
            , mergeQueueMaxConcurrent = maxConcurrent'
            , mergeQueueRetryLimit = retryLimit'
            , mergeQueueCreated = now
            , mergeQueueUpdated = now
            }
    runDB $ insertEntity queue

-- | Enqueue a change for merging
enqueueChange :: MonadIO m
              => Text  -- ^ Queue ID
              -> Text  -- ^ Change ID
              -> MergePriority  -- ^ Priority
              -> [Text]  -- ^ Dependencies
              -> Maybe Value  -- ^ Additional metadata
              -> m (Entity MergeQueueEntry)
enqueueChange queueId' changeId' priority' deps metadata = do
    now <- liftIO getCurrentTime
    let entryId' = generateEntryId queueId' changeId' now
    let entry = MergeQueueEntry
            { mergeQueueEntryEntryId = entryId'
            , mergeQueueEntryQueueId = queueId'
            , mergeQueueEntryChangeId = changeId'
            , mergeQueueEntryPriority = priority'
            , mergeQueueEntryStatus = Queued
            , mergeQueueEntryDependencies = deps
            , mergeQueueEntryRetryCount = 0
            , mergeQueueEntryConflict = Nothing
            , mergeQueueEntryMetadata = metadata
            , mergeQueueEntryCreated = now
            , mergeQueueEntryUpdated = now
            }
    runDB $ insertEntity entry

-- | Dequeue a change
dequeueChange :: MonadIO m
              => Text  -- ^ Entry ID
              -> m ()
dequeueChange entryId' =
    runDB $ delete $ toSqlKey $ read $ Text.unpack entryId'

-- | Update entry status
updateEntryStatus :: MonadIO m
                  => Text  -- ^ Entry ID
                  -> MergeStatus  -- ^ New status
                  -> Maybe MergeConflict  -- ^ Conflict info if any
                  -> m (Maybe (Entity MergeQueueEntry))
updateEntryStatus entryId' status' conflict' = do
    now <- liftIO getCurrentTime
    runDB $ do
        mEntry <- getBy $ UniqueEntryId entryId'
        case mEntry of
            Nothing -> return Nothing
            Just (Entity key entry) -> do
                let updatedEntry = entry
                        { mergeQueueEntryStatus = status'
                        , mergeQueueEntryConflict = conflict'
                        , mergeQueueEntryUpdated = now
                        }
                replace key updatedEntry
                return $ Just $ Entity key updatedEntry

-- | Get queue by ID
getQueueById :: MonadIO m
             => Text  -- ^ Queue ID
             -> m (Maybe (Entity MergeQueue))
getQueueById queueId' =
    runDB $ getBy $ UniqueQueueId queueId'

-- | Get all entries in a queue
getQueueEntries :: MonadIO m
                => Text  -- ^ Queue ID
                -> m [Entity MergeQueueEntry]
getQueueEntries queueId' =
    runDB $ selectList [MergeQueueEntryQueueId ==. queueId'] [Asc MergeQueueEntryCreated]

-- | Get entry by ID
getEntryById :: MonadIO m
             => Text  -- ^ Entry ID
             -> m (Maybe (Entity MergeQueueEntry))
getEntryById entryId' =
    runDB $ getBy $ UniqueEntryId entryId'

-- | Get entries by status
getEntriesByStatus :: MonadIO m
                   => Text  -- ^ Queue ID
                   -> MergeStatus  -- ^ Status
                   -> m [Entity MergeQueueEntry]
getEntriesByStatus queueId' status' =
    runDB $ selectList
        [ MergeQueueEntryQueueId ==. queueId'
        , MergeQueueEntryStatus ==. status'
        ] [Asc MergeQueueEntryCreated]

-- | Get entries by priority
getEntriesByPriority :: MonadIO m
                     => Text  -- ^ Queue ID
                     -> MergePriority  -- ^ Priority
                     -> m [Entity MergeQueueEntry]
getEntriesByPriority queueId' priority' =
    runDB $ selectList
        [ MergeQueueEntryQueueId ==. queueId'
        , MergeQueueEntryPriority ==. priority'
        ] [Asc MergeQueueEntryCreated]

-- Helper functions for generating IDs
generateQueueId :: Text -> Text -> UTCTime -> Text
generateQueueId projectId branch timestamp =
    "mq_" <> Text.filter isAllowed projectId <> "_" <> Text.filter isAllowed branch <>
    "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateEntryId :: Text -> Text -> UTCTime -> Text
generateEntryId queueId changeId timestamp =
    "mqe_" <> Text.filter isAllowed queueId <> "_" <> Text.filter isAllowed changeId <>
    "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show

-- | Create merge queue
createMergeQueue :: MonadIO m
                 => Text  -- ^ Name
                 -> Text  -- ^ Description
                 -> VCSType  -- ^ VCS type
                 -> Int   -- ^ Max retries
                 -> Int   -- ^ Concurrent merges
                 -> Maybe Value  -- ^ Validation hooks
                 -> Maybe Value  -- ^ Initial metrics
                 -> Maybe Value  -- ^ Additional metadata
                 -> m (Entity MergeQueue)
createMergeQueue name description vcsType maxRetries concurrentMerges hooks metrics metadata = do
    now <- liftIO getCurrentTime
    let queueId = generateQueueId name now
    let queue = MergeQueue
            { mergeQueueQueueId = queueId
            , mergeQueueName = name
            , mergeQueueDescription = description
            , mergeQueueVcsType = vcsType
            , mergeQueueStatus = Active
            , mergeQueueMaxRetries = maxRetries
            , mergeQueueConcurrentMerges = concurrentMerges
            , mergeQueueValidationHooks = hooks
            , mergeQueueMetrics = metrics
            , mergeQueueMetadata = metadata
            , mergeQueueCreated = now
            , mergeQueueUpdated = now
            }
    runDB $ insertEntity queue

-- | Update merge queue
updateMergeQueue :: MonadIO m
                 => Entity MergeQueue
                 -> Text  -- ^ Name
                 -> Text  -- ^ Description
                 -> VCSType  -- ^ VCS type
                 -> MergeQueueStatus  -- ^ Status
                 -> Int   -- ^ Max retries
                 -> Int   -- ^ Concurrent merges
                 -> Maybe Value  -- ^ Validation hooks
                 -> Maybe Value  -- ^ Metrics
                 -> Maybe Value  -- ^ Additional metadata
                 -> m (Entity MergeQueue)
updateMergeQueue (Entity key queue) name description vcsType status maxRetries concurrentMerges hooks metrics metadata = do
    now <- liftIO getCurrentTime
    let updatedQueue = queue
            { mergeQueueName = name
            , mergeQueueDescription = description
            , mergeQueueVcsType = vcsType
            , mergeQueueStatus = status
            , mergeQueueMaxRetries = maxRetries
            , mergeQueueConcurrentMerges = concurrentMerges
            , mergeQueueValidationHooks = hooks
            , mergeQueueMetrics = metrics
            , mergeQueueMetadata = metadata
            , mergeQueueUpdated = now
            }
    runDB $ replace key updatedQueue
    return $ Entity key updatedQueue

-- | Get merge queue by ID
getMergeQueueById :: MonadIO m
                  => Text  -- ^ Queue ID
                  -> m (Maybe (Entity MergeQueue))
getMergeQueueById queueId =
    runDB $ getBy $ UniqueMergeQueueId queueId

-- | List merge queues
listMergeQueues :: MonadIO m
                => Maybe VCSType  -- ^ Filter by VCS type
                -> Maybe MergeQueueStatus  -- ^ Filter by status
                -> Int   -- ^ Offset
                -> Int   -- ^ Limit
                -> m [Entity MergeQueue]
listMergeQueues mVcsType mStatus offset limit = do
    let filters = concat
            [ maybe [] (\t -> [MergeQueueVcsType ==. t]) mVcsType
            , maybe [] (\s -> [MergeQueueStatus ==. s]) mStatus
            ]
    runDB $ selectList filters [Asc MergeQueueName, OffsetBy offset, LimitTo limit]

-- | Add entry to merge queue
addToMergeQueue :: MonadIO m
                => Text  -- ^ Queue ID
                -> Text  -- ^ Change ID
                -> MergeQueuePriority  -- ^ Priority
                -> [Text]  -- ^ Dependencies
                -> Maybe Value  -- ^ Additional metadata
                -> m (Entity MergeQueueEntry)
addToMergeQueue queueId changeId priority deps metadata = do
    now <- liftIO getCurrentTime
    let entryId = generateEntryId queueId changeId now
    let entry = MergeQueueEntry
            { mergeQueueEntryEntryId = entryId
            , mergeQueueEntryQueueId = queueId
            , mergeQueueEntryChangeId = changeId
            , mergeQueueEntryPriority = priority
            , mergeQueueEntryDependencies = deps
            , mergeQueueEntryRetryCount = 0
            , mergeQueueEntryLastError = Nothing
            , mergeQueueEntryValidationStatus = Nothing
            , mergeQueueEntryMetadata = metadata
            , mergeQueueEntryCreated = now
            , mergeQueueEntryUpdated = now
            }
    runDB $ insertEntity entry

-- | Remove entry from merge queue
removeFromMergeQueue :: MonadIO m
                    => Entity MergeQueueEntry
                    -> m ()
removeFromMergeQueue (Entity key _) =
    runDB $ delete key

-- | Update entry priority
updateEntryPriority :: MonadIO m
                    => Entity MergeQueueEntry
                    -> MergeQueuePriority  -- ^ New priority
                    -> m (Entity MergeQueueEntry)
updateEntryPriority (Entity key entry) priority = do
    now <- liftIO getCurrentTime
    let updatedEntry = entry
            { mergeQueueEntryPriority = priority
            , mergeQueueEntryUpdated = now
            }
    runDB $ replace key updatedEntry
    return $ Entity key updatedEntry

-- | Get next entry to merge
getNextMergeEntry :: MonadIO m
                  => Text  -- ^ Queue ID
                  -> m (Maybe (Entity MergeQueueEntry))
getNextMergeEntry queueId =
    runDB $ selectFirst
        [ MergeQueueEntryQueueId ==. queueId
        , MergeQueueEntryRetryCount <. maxRetries
        ]
        [Asc MergeQueueEntryPriority, Asc MergeQueueEntryCreated]
  where
    maxRetries = 3  -- TODO: Make this configurable

-- | List queue entries
listQueueEntries :: MonadIO m
                 => Text  -- ^ Queue ID
                 -> Maybe MergeQueuePriority  -- ^ Filter by priority
                 -> Int   -- ^ Offset
                 -> Int   -- ^ Limit
                 -> m [Entity MergeQueueEntry]
listQueueEntries queueId mPriority offset limit = do
    let filters = MergeQueueEntryQueueId ==. queueId :
                 maybe [] (\p -> [MergeQueueEntryPriority ==. p]) mPriority
    runDB $ selectList filters [Asc MergeQueueEntryPriority, Asc MergeQueueEntryCreated, OffsetBy offset, LimitTo limit]

-- | Create a new queue entry
createQueueEntry :: MonadIO m
                => MergeQueueEntry
                -> SqlPersistT m (Entity MergeQueueEntry)
createQueueEntry entry = do
    entryId <- insert entry
    return $ Entity entryId entry

-- | Get a queue entry by ID
getQueueEntry :: MonadIO m
              => Text  -- ^ Entry ID
              -> SqlPersistT m (Maybe (Entity MergeQueueEntry))
getQueueEntry entryId =
    getBy $ UniqueMergeQueueEntryId entryId

-- | Update a queue entry
updateQueueEntry :: MonadIO m
                => MergeQueueEntry
                -> SqlPersistT m ()
updateQueueEntry entry =
    replace (MergeQueueEntryKey $ mergeQueueEntryEntryId entry) entry

-- | Delete a queue entry
deleteQueueEntry :: MonadIO m
                => Text  -- ^ Entry ID
                -> SqlPersistT m ()
deleteQueueEntry entryId =
    delete $ MergeQueueEntryKey entryId

-- | Update queue entry status
updateQueueEntryStatus :: MonadIO m
                      => MergeQueueEntry
                      -> MergeQueueStatus
                      -> SqlPersistT m ()
updateQueueEntryStatus entry newStatus = do
    now <- liftIO getCurrentTime
    let updated = entry
            { mergeQueueEntryStatus = newStatus
            , mergeQueueEntryUpdated = now
            }
    updateQueueEntry updated

-- | Update queue entry attempts
updateQueueEntryAttempts :: MonadIO m
                        => MergeQueueEntry
                        -> Int
                        -> SqlPersistT m ()
updateQueueEntryAttempts entry attempts = do
    now <- liftIO getCurrentTime
    let updated = entry
            { mergeQueueEntryAttempts = attempts
            , mergeQueueEntryUpdated = now
            }
    updateQueueEntry updated

-- | Get entries for a change
getEntriesForChange :: MonadIO m
                    => Text  -- ^ Change ID
                    -> SqlPersistT m [Entity MergeQueueEntry]
getEntriesForChange changeId =
    selectList [MergeQueueEntryChangeId ==. changeId] []

-- | Clean up merged entries
cleanupMergedEntries :: MonadIO m
                     => UTCTime  -- ^ Cutoff time
                     -> SqlPersistT m ()
cleanupMergedEntries cutoff =
    deleteWhere
        [ MergeQueueEntryStatus ==. Merged
        , MergeQueueEntryUpdated <=. cutoff
        ]

-- | Clean up failed entries
cleanupFailedEntries :: MonadIO m
                     => UTCTime  -- ^ Cutoff time
                     -> SqlPersistT m ()
cleanupFailedEntries cutoff =
    deleteWhere
        [ MergeQueueEntryStatus ==. Failed ""
        , MergeQueueEntryUpdated <=. cutoff
        ]
