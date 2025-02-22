-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.VCS.MergeQueue
    ( GitMergeQueue(..)
    , HgMergeQueue(..)
    , JJMergeQueue(..)
    , ProcessorConfig(..)
    , QueueItem(..)
    , QueueStatus(..)
    , QueueMetrics(..)
    , startQueueProcessor
    , stopQueueProcessor
    , enqueueChange
    , dequeueChange
    , getQueueStatus
    , collectQueueMetrics
    ) where

import Control.Monad (forever, void, when, forM_)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Exception (throwIO)
import Control.Concurrent (threadDelay)
import Control.Concurrent.STM
import Control.Concurrent.Async (async, cancel)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime, NominalDiffTime)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import System.Timeout (timeout)
import System.FilePath ((</>))
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive)

import Gerrit.VCS.Types
import Gerrit.VCS.Git (Git(..))
import Gerrit.VCS.Mercurial (Mercurial(..))
import Gerrit.VCS.JJ (JJ(..))
import Gerrit.VCS.Webhook
    ( WebhookSystem(..)
    , WebhookEvent(..)
    )
import Gerrit.Models.Stack
import Gerrit.Models.AuditLog

-- | Git merge queue implementation
data GitMergeQueue = GitMergeQueue
    { gmqConfig :: QueueConfig
    , gmqRepo :: Repository
    , gmqGit :: Git
    , gmqStorage :: QueueStorage
    , gmqNotifier :: NotificationSystem
    , gmqWebhooks :: WebhookSystem
    , gmqQueue :: TQueue QueueItem
    , gmqStatus :: TVar QueueStatus
    , gmqProcessor :: TVar (Maybe ThreadId)
    , gmqAuditLogger :: AuditLoggerConfig
    }

instance MergeQueue GitMergeQueue where
    enqueue repo source target = do
        now <- liftIO getCurrentTime
        let entryId = EntryId $ T.pack $ show now
        let entry = MergeEntry
                { meId = entryId
                , meRepository = repo
                , meSource = source
                , meTarget = target
                , mePriority = Normal
                , meStatus = Queued
                , meValidation = []
                , meDependencies = []
                , meCreated = now
                , meUpdated = now
                }

        -- Log enqueue operation
        logOperation (gmqAuditLogger queue)
            "system"
            "system"
            MergeOperation
            (RepoResource $ repoPath repo)
            (object
                [ "action" .= ("enqueue" :: Text)
                , "entry_id" .= entryId
                , "source" .= source
                , "target" .= target
                ])
            (systemContext "enqueue")

        storeEntry (gmqStorage queue) entry
        deliverEvent (gmqWebhooks queue) EntryCreated $ object
            [ "entry_id" .= entryId
            , "repository" .= repo
            , "source" .= source
            , "target" .= target
            ]
        pure entryId

    dequeue entryId = do
        -- Log dequeue operation
        logOperation (gmqAuditLogger queue)
            "system"
            "system"
            MergeOperation
            (RepoResource "queue")
            (object
                [ "action" .= ("dequeue" :: Text)
                , "entry_id" .= entryId
                ])
            (systemContext "dequeue")

        deleteEntry (gmqStorage queue) entryId
        deliverEvent (gmqWebhooks queue) EntryDeleted $ object
            [ "entry_id" .= entryId
            ]

    getEntry entryId = do
        -- Log entry lookup
        logOperation (gmqAuditLogger queue)
            "system"
            "system"
            ResourceRead
            (RepoResource "queue")
            (object
                [ "action" .= ("get_entry" :: Text)
                , "entry_id" .= entryId
                ])
            (systemContext "get-entry")

        loadEntry (gmqStorage queue) entryId

    listEntries repo = do
        -- Log entries listing
        logOperation (gmqAuditLogger queue)
            "system"
            "system"
            ResourceRead
            (RepoResource $ repoPath repo)
            (object [ "action" .= ("list_entries" :: Text) ])
            (systemContext "list-entries")

        listAllEntries (gmqStorage queue) repo

    updateStatus entryId status = do
        -- Log status update
        logOperation (gmqAuditLogger queue)
            "system"
            "system"
            MergeOperation
            (RepoResource "queue")
            (object
                [ "action" .= ("update_status" :: Text)
                , "entry_id" .= entryId
                , "status" .= status
                ])
            (systemContext "update-status")

        updateEntryStatus (gmqStorage queue) entryId status
        deliverEvent (gmqWebhooks queue) StatusChanged $ object
            [ "entry_id" .= entryId
            , "status" .= status
            ]

    getStatus entryId = do
        mEntry <- loadEntry (gmqStorage queue) entryId
        pure $ maybe Queued meStatus mEntry

    runValidation entryId = do
        mEntry <- loadEntry (gmqStorage queue) entryId
        case mEntry of
            Just entry -> do
                -- Log validation start
                logOperation (gmqAuditLogger queue)
                    "system"
                    "system"
                    ReviewActivity
                    (ReviewResource $ "merge/" <> unEntryId entryId)
                    (object [ "action" .= ("validation_start" :: Text) ])
                    (systemContext "validation")

                -- Run validations
                results <- runValidations entry

                -- Log validation results
                logOperation (gmqAuditLogger queue)
                    "system"
                    "system"
                    ReviewActivity
                    (ReviewResource $ "merge/" <> unEntryId entryId)
                    (object
                        [ "action" .= ("validation_complete" :: Text)
                        , "results" .= results
                        ])
                    (systemContext "validation")

                -- Update validation status
                updateEntryValidation (gmqStorage queue) entryId results
                deliverEvent (gmqWebhooks queue) ValidationUpdated $ object
                    [ "entry_id" .= entryId
                    , "results" .= results
                    ]
                pure $ if all isSuccess results
                    then ValidationSuccess
                    else ValidationFailure "Validation failed"
            Nothing -> pure $ ValidationFailure "Entry not found"

    processMerge entryId = do
        mEntry <- loadEntry (gmqStorage queue) entryId
        case mEntry of
            Just entry -> do
                -- Log merge start
                logOperation (gmqAuditLogger queue)
                    "system"
                    "system"
                    MergeOperation
                    (RepoResource $ repoPath $ meRepository entry)
                    (object
                        [ "action" .= ("merge_start" :: Text)
                        , "source" .= meSource entry
                        , "target" .= meTarget entry
                        ])
                    (systemContext "merge")

                -- Create temporary branch for merge
                let tempBranch = "merge-" <> unEntryId (meId entry)
                void $ createBranch (gmqGit queue) (meRepository entry) tempBranch
                void $ checkout (gmqGit queue) (meRepository entry) (Branch tempBranch)

                -- Try merge
                result <- try $ merge (gmqGit queue) (meRepository entry) (meSource entry)

                case result of
                    Right _ -> do
                        -- Fast-forward target branch
                        void $ checkout (gmqGit queue) (meRepository entry) (meTarget entry)
                        void $ merge (gmqGit queue) (meRepository entry) (Branch tempBranch)

                        -- Log merge success
                        logOperation (gmqAuditLogger queue)
                            "system"
                            "system"
                            MergeOperation
                            (RepoResource $ repoPath $ meRepository entry)
                            (object
                                [ "action" .= ("merge_success" :: Text)
                                , "source" .= meSource entry
                                , "target" .= meTarget entry
                                ])
                            (systemContext "merge")

                        -- Cleanup
                        void $ deleteBranch (gmqGit queue) (meRepository entry) tempBranch
                        pure MergeSuccess

                    Left err -> do
                        -- Log merge failure
                        logOperation (gmqAuditLogger queue)
                            "system"
                            "system"
                            MergeOperation
                            (RepoResource $ repoPath $ meRepository entry)
                            (object
                                [ "action" .= ("merge_failure" :: Text)
                                , "source" .= meSource entry
                                , "target" .= meTarget entry
                                , "error" .= err
                                ])
                            (systemContext "merge")

                        -- Cleanup on failure
                        void $ checkout (gmqGit queue) (meRepository entry) (meTarget entry)
                        void $ deleteBranch (gmqGit queue) (meRepository entry) tempBranch
                        pure $ MergeFailure $ ConflictDetected []

            Nothing -> pure $ MergeFailure $ SystemError "Entry not found"

    rollbackMerge entryId = do
        mEntry <- loadEntry (gmqStorage queue) entryId
        case mEntry of
            Just entry -> do
                -- Log rollback start
                logOperation (gmqAuditLogger queue)
                    "system"
                    "system"
                    MergeOperation
                    (RepoResource $ repoPath $ meRepository entry)
                    (object
                        [ "action" .= ("rollback_start" :: Text)
                        , "entry_id" .= entryId
                        ])
                    (systemContext "rollback")

                -- Reset target branch to original state
                void $ checkout (gmqGit queue) (meRepository entry) (meTarget entry)
                void $ reset (gmqGit queue) (meRepository entry) ResetHard

                -- Log rollback completion
                logOperation (gmqAuditLogger queue)
                    "system"
                    "system"
                    MergeOperation
                    (RepoResource $ repoPath $ meRepository entry)
                    (object
                        [ "action" .= ("rollback_complete" :: Text)
                        , "entry_id" .= entryId
                        ])
                    (systemContext "rollback")

            Nothing -> pure ()

    getQueueMetrics repo = do
        entries <- listAllEntries (gmqStorage queue) repo
        now <- liftIO getCurrentTime
        let
            totalCount = length entries
            successCount = length $ filter ((== Succeeded) . meStatus) entries
            waitTimes = map (diffUTCTime now . meCreated) entries
            processTimes = map (diffUTCTime . meUpdated . meCreated)
                        $ filter ((/= Queued) . meStatus) entries
            failures = Map.fromListWith (+)
                    [ (f, 1) | Failed f <- map meStatus entries ]

        let metrics = QueueMetrics
                { qmTotalEntries = totalCount
                , qmSuccessRate = fromIntegral successCount / fromIntegral totalCount
                , qmAverageWaitTime = average waitTimes
                , qmAverageProcessTime = average processTimes
                , qmFailureRates = failures
                , qmConcurrentMerges = length $ filter ((== Merging) . meStatus) entries
                }

        -- Log metrics collection
        logOperation (gmqAuditLogger queue)
            "system"
            "system"
            AdminAction
            (ConfigResource "merge-queue")
            (object
                [ "action" .= ("metrics_collection" :: Text)
                , "metrics" .= metrics
                ])
            (systemContext "metrics")

        pure metrics

-- | Mercurial merge queue implementation
data HgMergeQueue = HgMergeQueue
    { hmqConfig :: QueueConfig
    , hmqRepo :: Repository
    , hmqHg :: Mercurial
    , hmqStorage :: QueueStorage
    , hmqNotifier :: NotificationSystem
    , hmqWebhooks :: WebhookSystem
    , hmqQueue :: TQueue QueueItem
    , hmqStatus :: TVar QueueStatus
    , hmqProcessor :: TVar (Maybe ThreadId)
    , hmqAuditLogger :: AuditLoggerConfig
    }

instance MergeQueue HgMergeQueue where
    enqueue repo source target = do
        now <- liftIO getCurrentTime
        let entryId = EntryId $ T.pack $ show now
        let entry = MergeEntry
                { meId = entryId
                , meRepository = repo
                , meSource = source
                , meTarget = target
                , mePriority = Normal
                , meStatus = Queued
                , meValidation = []
                , meDependencies = []
                , meCreated = now
                , meUpdated = now
                }

        -- Log enqueue operation
        logOperation (hmqAuditLogger queue)
            "system"
            "system"
            MergeOperation
            (RepoResource $ repoPath repo)
            (object
                [ "action" .= ("enqueue" :: Text)
                , "entry_id" .= entryId
                , "source" .= source
                , "target" .= target
                ])
            (systemContext "enqueue")

        storeEntry (hmqStorage queue) entry
        deliverEvent (hmqWebhooks queue) EntryCreated $ object
            [ "entry_id" .= entryId
            , "repository" .= repo
            , "source" .= source
            , "target" .= target
            ]
        pure entryId

    dequeue entryId = do
        -- Log dequeue operation
        logOperation (hmqAuditLogger queue)
            "system"
            "system"
            MergeOperation
            (RepoResource "queue")
            (object
                [ "action" .= ("dequeue" :: Text)
                , "entry_id" .= entryId
                ])
            (systemContext "dequeue")

        deleteEntry (hmqStorage queue) entryId
        deliverEvent (hmqWebhooks queue) EntryDeleted $ object
            [ "entry_id" .= entryId
            ]

    getEntry entryId = do
        -- Log entry lookup
        logOperation (hmqAuditLogger queue)
            "system"
            "system"
            ResourceRead
            (RepoResource "queue")
            (object
                [ "action" .= ("get_entry" :: Text)
                , "entry_id" .= entryId
                ])
            (systemContext "get-entry")

        loadEntry (hmqStorage queue) entryId

    listEntries repo = do
        -- Log entries listing
        logOperation (hmqAuditLogger queue)
            "system"
            "system"
            ResourceRead
            (RepoResource $ repoPath repo)
            (object [ "action" .= ("list_entries" :: Text) ])
            (systemContext "list-entries")

        listAllEntries (hmqStorage queue) repo

    updateStatus entryId status = do
        -- Log status update
        logOperation (hmqAuditLogger queue)
            "system"
            "system"
            MergeOperation
            (RepoResource "queue")
            (object
                [ "action" .= ("update_status" :: Text)
                , "entry_id" .= entryId
                , "status" .= status
                ])
            (systemContext "update-status")

        updateEntryStatus (hmqStorage queue) entryId status
        deliverEvent (hmqWebhooks queue) StatusChanged $ object
            [ "entry_id" .= entryId
            , "status" .= status
            ]

    getStatus entryId = do
        mEntry <- loadEntry (hmqStorage queue) entryId
        pure $ maybe Queued meStatus mEntry

    runValidation entryId = do
        mEntry <- loadEntry (hmqStorage queue) entryId
        case mEntry of
            Just entry -> do
                -- Log validation start
                logOperation (hmqAuditLogger queue)
                    "system"
                    "system"
                    ReviewActivity
                    (ReviewResource $ "merge/" <> unEntryId entryId)
                    (object [ "action" .= ("validation_start" :: Text) ])
                    (systemContext "validation")

                -- Run validations
                results <- runValidations entry

                -- Log validation results
                logOperation (hmqAuditLogger queue)
                    "system"
                    "system"
                    ReviewActivity
                    (ReviewResource $ "merge/" <> unEntryId entryId)
                    (object
                        [ "action" .= ("validation_complete" :: Text)
                        , "results" .= results
                        ])
                    (systemContext "validation")

                -- Update validation status
                updateEntryValidation (hmqStorage queue) entryId results
                deliverEvent (hmqWebhooks queue) ValidationUpdated $ object
                    [ "entry_id" .= entryId
                    , "results" .= results
                    ]
                pure $ if all isSuccess results
                    then ValidationSuccess
                    else ValidationFailure "Validation failed"
            Nothing -> pure $ ValidationFailure "Entry not found"

    processMerge entryId = do
        mEntry <- loadEntry (hmqStorage queue) entryId
        case mEntry of
            Just entry -> do
                -- Log merge start
                logOperation (hmqAuditLogger queue)
                    "system"
                    "system"
                    MergeOperation
                    (RepoResource $ repoPath $ meRepository entry)
                    (object
                        [ "action" .= ("merge_start" :: Text)
                        , "source" .= meSource entry
                        , "target" .= meTarget entry
                        ])
                    (systemContext "merge")

                -- Create bundle for validation
                let bundlePath = repoPath (meRepository entry) </> "merge.bundle"
                createBundle (hmqHg queue) (meRepository entry) [RevisionSingle (meSource entry)] bundlePath

                -- Validate bundle
                validation <- validateBundle (hmqHg queue) (meRepository entry) bundlePath
                case validation of
                    ValidationSuccess -> do
                        -- Apply bundle and update phases
                        applyBundle (hmqHg queue) (meRepository entry) bundlePath
                        setPhase (hmqHg queue) (meRepository entry) Draft [RevisionSingle (meSource entry)]

                        -- Log merge success
                        logOperation (hmqAuditLogger queue)
                            "system"
                            "system"
                            MergeOperation
                            (RepoResource $ repoPath $ meRepository entry)
                            (object
                                [ "action" .= ("merge_success" :: Text)
                                , "source" .= meSource entry
                                , "target" .= meTarget entry
                                ])
                            (systemContext "merge")

                        pure MergeSuccess

                    ValidationFailure reason -> do
                        -- Log merge failure
                        logOperation (hmqAuditLogger queue)
                            "system"
                            "system"
                            MergeOperation
                            (RepoResource $ repoPath $ meRepository entry)
                            (object
                                [ "action" .= ("merge_failure" :: Text)
                                , "source" .= meSource entry
                                , "target" .= meTarget entry
                                , "reason" .= reason
                                ])
                            (systemContext "merge")

                        pure $ MergeFailure $ ValidationFailed reason

            Nothing -> pure $ MergeFailure $ SystemError "Entry not found"

    rollbackMerge entryId = do
        mEntry <- loadEntry (hmqStorage queue) entryId
        case mEntry of
            Just entry -> do
                -- Log rollback start
                logOperation (hmqAuditLogger queue)
                    "system"
                    "system"
                    MergeOperation
                    (RepoResource $ repoPath $ meRepository entry)
                    (object
                        [ "action" .= ("rollback_start" :: Text)
                        , "entry_id" .= entryId
                        ])
                    (systemContext "rollback")

                -- Strip applied changes
                void $ strip (hmqHg queue) (meRepository entry) (meSource entry)

                -- Log rollback completion
                logOperation (hmqAuditLogger queue)
                    "system"
                    "system"
                    MergeOperation
                    (RepoResource $ repoPath $ meRepository entry)
                    (object
                        [ "action" .= ("rollback_complete" :: Text)
                        , "entry_id" .= entryId
                        ])
                    (systemContext "rollback")

            Nothing -> pure ()

    getQueueMetrics repo = do
        entries <- listAllEntries (hmqStorage queue) repo
        now <- liftIO getCurrentTime
        let
            totalCount = length entries
            successCount = length $ filter ((== Succeeded) . meStatus) entries
            waitTimes = map (diffUTCTime now . meCreated) entries
            processTimes = map (diffUTCTime . meUpdated . meCreated)
                        $ filter ((/= Queued) . meStatus) entries
            failures = Map.fromListWith (+)
                    [ (f, 1) | Failed f <- map meStatus entries ]

        let metrics = QueueMetrics
                { qmTotalEntries = totalCount
                , qmSuccessRate = fromIntegral successCount / fromIntegral totalCount
                , qmAverageWaitTime = average waitTimes
                , qmAverageProcessTime = average processTimes
                , qmFailureRates = failures
                , qmConcurrentMerges = length $ filter ((== Merging) . meStatus) entries
                }

        -- Log metrics collection
        logOperation (hmqAuditLogger queue)
            "system"
            "system"
            AdminAction
            (ConfigResource "merge-queue")
            (object
                [ "action" .= ("metrics_collection" :: Text)
                , "metrics" .= metrics
                ])
            (systemContext "metrics")

        pure metrics

-- | jj merge queue implementation
data JJMergeQueue = JJMergeQueue
    { jmqConfig :: QueueConfig
    , jmqRepo :: Repository
    , jmqJJ :: JJ
    , jmqStorage :: QueueStorage
    , jmqNotifier :: NotificationSystem
    , jmqWebhooks :: WebhookSystem
    , jmqQueue :: TQueue QueueItem
    , jmqStatus :: TVar QueueStatus
    , jmqProcessor :: TVar (Maybe ThreadId)
    , jmqAuditLogger :: AuditLoggerConfig
    }

instance MergeQueue JJMergeQueue where
    enqueue repo source target = do
        now <- liftIO getCurrentTime
        let entryId = EntryId $ T.pack $ show now
        let entry = MergeEntry
                { meId = entryId
                , meRepository = repo
                , meSource = source
                , meTarget = target
                , mePriority = Normal
                , meStatus = Queued
                , meValidation = []
                , meDependencies = []
                , meCreated = now
                , meUpdated = now
                }

        -- Log enqueue operation
        logOperation (jmqAuditLogger queue)
            "system"
            "system"
            MergeOperation
            (RepoResource $ repoPath repo)
            (object
                [ "action" .= ("enqueue" :: Text)
                , "entry_id" .= entryId
                , "source" .= source
                , "target" .= target
                ])
            (systemContext "enqueue")

        storeEntry (jmqStorage queue) entry
        deliverEvent (jmqWebhooks queue) EntryCreated $ object
            [ "entry_id" .= entryId
            , "repository" .= repo
            , "source" .= source
            , "target" .= target
            ]
        pure entryId

    dequeue entryId = do
        -- Log dequeue operation
        logOperation (jmqAuditLogger queue)
            "system"
            "system"
            MergeOperation
            (RepoResource "queue")
            (object
                [ "action" .= ("dequeue" :: Text)
                , "entry_id" .= entryId
                ])
            (systemContext "dequeue")

        deleteEntry (jmqStorage queue) entryId
        deliverEvent (jmqWebhooks queue) EntryDeleted $ object
            [ "entry_id" .= entryId
            ]

    getEntry entryId = do
        -- Log entry lookup
        logOperation (jmqAuditLogger queue)
            "system"
            "system"
            ResourceRead
            (RepoResource "queue")
            (object
                [ "action" .= ("get_entry" :: Text)
                , "entry_id" .= entryId
                ])
            (systemContext "get-entry")

        loadEntry (jmqStorage queue) entryId

    listEntries repo = do
        -- Log entries listing
        logOperation (jmqAuditLogger queue)
            "system"
            "system"
            ResourceRead
            (RepoResource $ repoPath repo)
            (object [ "action" .= ("list_entries" :: Text) ])
            (systemContext "list-entries")

        listAllEntries (jmqStorage queue) repo

    updateStatus entryId status = do
        -- Log status update
        logOperation (jmqAuditLogger queue)
            "system"
            "system"
            MergeOperation
            (RepoResource "queue")
            (object
                [ "action" .= ("update_status" :: Text)
                , "entry_id" .= entryId
                , "status" .= status
                ])
            (systemContext "update-status")

        updateEntryStatus (jmqStorage queue) entryId status
        deliverEvent (jmqWebhooks queue) StatusChanged $ object
            [ "entry_id" .= entryId
            , "status" .= status
            ]

    getStatus entryId = do
        mEntry <- loadEntry (jmqStorage queue) entryId
        pure $ maybe Queued meStatus mEntry

    runValidation entryId = do
        mEntry <- loadEntry (jmqStorage queue) entryId
        case mEntry of
            Just entry -> do
                -- Log validation start
                logOperation (jmqAuditLogger queue)
                    "system"
                    "system"
                    ReviewActivity
                    (ReviewResource $ "merge/" <> unEntryId entryId)
                    (object [ "action" .= ("validation_start" :: Text) ])
                    (systemContext "validation")

                -- Run validations
                results <- runValidations entry

                -- Log validation results
                logOperation (jmqAuditLogger queue)
                    "system"
                    "system"
                    ReviewActivity
                    (ReviewResource $ "merge/" <> unEntryId entryId)
                    (object
                        [ "action" .= ("validation_complete" :: Text)
                        , "results" .= results
                        ])
                    (systemContext "validation")

                -- Update validation status
                updateEntryValidation (jmqStorage queue) entryId results
                deliverEvent (jmqWebhooks queue) ValidationUpdated $ object
                    [ "entry_id" .= entryId
                    , "results" .= results
                    ]
                pure $ if all isSuccess results
                    then ValidationSuccess
                    else ValidationFailure "Validation failed"
            Nothing -> pure $ ValidationFailure "Entry not found"

    processMerge entryId = do
        mEntry <- loadEntry (jmqStorage queue) entryId
        case mEntry of
            Just entry -> do
                -- Log merge start
                logOperation (jmqAuditLogger queue)
                    "system"
                    "system"
                    MergeOperation
                    (RepoResource $ repoPath $ meRepository entry)
                    (object
                        [ "action" .= ("merge_start" :: Text)
                        , "source" .= meSource entry
                        , "target" .= meTarget entry
                        ])
                    (systemContext "merge")

                -- Create workspace for merge
                let wsName = "merge-" <> unEntryId (meId entry)
                workspace <- createWorkspace (jmqJJ queue) (meRepository entry) wsName

                -- Attempt merge in workspace
                result <- try $ do
                    switchWorkspace (jmqJJ queue) (meRepository entry) wsName
                    merge (jmqJJ queue) (meRepository entry) (meSource entry)

                case result of
                    Right _ -> do
                        -- Commit changes
                        commitWorkspace (jmqJJ queue) workspace

                        -- Log merge success
                        logOperation (jmqAuditLogger queue)
                            "system"
                            "system"
                            MergeOperation
                            (RepoResource $ repoPath $ meRepository entry)
                            (object
                                [ "action" .= ("merge_success" :: Text)
                                , "source" .= meSource entry
                                , "target" .= meTarget entry
                                ])
                            (systemContext "merge")

                        pure MergeSuccess

                    Left err -> do
                        -- Log merge failure
                        logOperation (jmqAuditLogger queue)
                            "system"
                            "system"
                            MergeOperation
                            (RepoResource $ repoPath $ meRepository entry)
                            (object
                                [ "action" .= ("merge_failure" :: Text)
                                , "source" .= meSource entry
                                , "target" .= meTarget entry
                                , "error" .= err
                                ])
                            (systemContext "merge")

                        -- Cleanup on failure
                        cleanupWorkspace (jmqJJ queue) workspace
                        pure $ MergeFailure $ ConflictDetected []

            Nothing -> pure $ MergeFailure $ SystemError "Entry not found"

    rollbackMerge entryId = do
        mEntry <- loadEntry (jmqStorage queue) entryId
        case mEntry of
            Just entry -> do
                -- Log rollback start
                logOperation (jmqAuditLogger queue)
                    "system"
                    "system"
                    MergeOperation
                    (RepoResource $ repoPath $ meRepository entry)
                    (object
                        [ "action" .= ("rollback_start" :: Text)
                        , "entry_id" .= entryId
                        ])
                    (systemContext "rollback")

                -- Remove workspace
                let wsName = "merge-" <> unEntryId (meId entry)
                cleanupWorkspace (jmqJJ queue) =<< getWorkspace (jmqJJ queue) (meRepository entry) wsName

                -- Log rollback completion
                logOperation (jmqAuditLogger queue)
                    "system"
                    "system"
                    MergeOperation
                    (RepoResource $ repoPath $ meRepository entry)
                    (object
                        [ "action" .= ("rollback_complete" :: Text)
                        , "entry_id" .= entryId
                        ])
                    (systemContext "rollback")

            Nothing -> pure ()

    getQueueMetrics repo = do
        entries <- listAllEntries (jmqStorage queue) repo
        now <- liftIO getCurrentTime
        let
            totalCount = length entries
            successCount = length $ filter ((== Succeeded) . meStatus) entries
            waitTimes = map (diffUTCTime now . meCreated) entries
            processTimes = map (diffUTCTime . meUpdated . meCreated)
                        $ filter ((/= Queued) . meStatus) entries
            failures = Map.fromListWith (+)
                    [ (f, 1) | Failed f <- map meStatus entries ]

        let metrics = QueueMetrics
                { qmTotalEntries = totalCount
                , qmSuccessRate = fromIntegral successCount / fromIntegral totalCount
                , qmAverageWaitTime = average waitTimes
                , qmAverageProcessTime = average processTimes
                , qmFailureRates = failures
                , qmConcurrentMerges = length $ filter ((== Merging) . meStatus) entries
                }

        -- Log metrics collection
        logOperation (jmqAuditLogger queue)
            "system"
            "system"
            AdminAction
            (ConfigResource "merge-queue")
            (object
                [ "action" .= ("metrics_collection" :: Text)
                , "metrics" .= metrics
                ])
            (systemContext "metrics")

        pure metrics

-- | Queue processor configuration
data ProcessorConfig = ProcessorConfig
    { pcMaxConcurrent :: Int          -- Maximum concurrent merges
    , pcRetryLimit :: Int             -- Maximum retry attempts
    , pcRetryDelay :: NominalDiffTime -- Delay between retries
    , pcBatchSize :: Int              -- Number of changes to process in a batch
    , pcPollingInterval :: Int        -- Queue polling interval in microseconds
    }

-- | Queue item representing a change to be merged
data QueueItem = QueueItem
    { qiId :: Text                    -- Queue item ID
    , qiChangeId :: Text              -- Change ID
    , qiStackId :: Maybe Text         -- Optional stack ID for stacked changes
    , qiDependencies :: [Text]        -- Change dependencies
    , qiPriority :: Int              -- Processing priority (lower = higher)
    , qiRetries :: Int               -- Number of retry attempts
    , qiSubmitted :: UTCTime         -- When the change was submitted
    , qiStarted :: Maybe UTCTime     -- When processing started
    , qiCompleted :: Maybe UTCTime   -- When processing completed
    , qiStatus :: QueueItemStatus    -- Current status
    , qiError :: Maybe Text          -- Error message if failed
    }

-- | Queue item status
data QueueItemStatus
    = Queued        -- Waiting to be processed
    | Processing    -- Currently being processed
    | Merged        -- Successfully merged
    | Failed        -- Failed to merge
    | Abandoned     -- Abandoned due to conflicts/errors
    deriving (Show, Eq)

-- | Overall queue status
data QueueStatus = QueueStatus
    { qsActive :: Bool                -- Whether the queue is processing
    , qsSize :: Int                   -- Current queue size
    , qsProcessing :: Int             -- Number of items being processed
    , qsLastProcessed :: Maybe UTCTime -- Last successful processing time
    , qsErrors :: Int                 -- Number of errors
    }

-- | Queue metrics
data QueueMetrics = QueueMetrics
    { qmTotalProcessed :: Int         -- Total number of processed items
    , qmSuccessful :: Int             -- Number of successful merges
    , qmFailed :: Int                 -- Number of failed merges
    , qmAverageWaitTime :: NominalDiffTime  -- Average wait time
    , qmAverageProcessTime :: NominalDiffTime -- Average processing time
    , qmErrorRate :: Double           -- Error rate
    }

-- | Start the queue processor
startQueueProcessor :: MonadIO m => ProcessorConfig -> QueueProcessor -> m ThreadId
startQueueProcessor config processor = liftIO $ do
    -- Initialize queue and status
    queue <- newTQueueIO
    status <- newTVarIO initialStatus
    processorVar <- newTVarIO Nothing

    -- Log processor initialization
    logOperation (qpAuditLogger processor)
        "system"
        "system"
        AdminAction
        (ConfigResource "merge-queue")
        (object
            [ "action" .= ("processor_init" :: Text)
            , "status" .= initialStatus
            ])
        (systemContext "processor-init")

    -- Log processor configuration
    logOperation (qpAuditLogger processor)
        "system"
        "system"
        AdminAction
        (ConfigResource "merge-queue")
        (object
            [ "action" .= ("processor_config" :: Text)
            , "config" .= object
                [ "max_concurrent" .= pcMaxConcurrent config
                , "retry_limit" .= pcRetryLimit config
                , "retry_delay" .= pcRetryDelay config
                , "batch_size" .= pcBatchSize config
                , "polling_interval" .= pcPollingInterval config
                ]
            ])
        (systemContext "processor-config")

    -- Start processor thread
    tid <- async $ forever $ do
        -- Log processing cycle start
        logOperation (qpAuditLogger processor)
            "system"
            "system"
            AdminAction
            (ConfigResource "merge-queue")
            (object [ "action" .= ("processing_cycle_start" :: Text) ])
            (systemContext "processor-cycle")

        processQueue config processor queue status

        -- Log processing cycle end
        logOperation (qpAuditLogger processor)
            "system"
            "system"
            AdminAction
            (ConfigResource "merge-queue")
            (object [ "action" .= ("processing_cycle_end" :: Text) ])
            (systemContext "processor-cycle")

        threadDelay $ pcPollingInterval config

    -- Log processor start success
    logOperation (qpAuditLogger processor)
        "system"
        "system"
        AdminAction
        (ConfigResource "merge-queue")
        (object
            [ "action" .= ("processor_start" :: Text)
            , "thread_id" .= show tid
            ])
        (systemContext "processor-start")

    -- Store thread ID
    atomically $ writeTVar processorVar (Just tid)
    pure tid
  where
    initialStatus = QueueStatus
        { qsActive = True
        , qsSize = 0
        , qsProcessing = 0
        , qsLastProcessed = Nothing
        , qsErrors = 0
        }

-- | Stop the queue processor
stopQueueProcessor :: MonadIO m => QueueProcessor -> TVar (Maybe ThreadId) -> m ()
stopQueueProcessor processor processorVar = liftIO $ do
    -- Log stop initiation
    logOperation (qpAuditLogger processor)
        "system"
        "system"
        AdminAction
        (ConfigResource "merge-queue")
        (object [ "action" .= ("processor_stop_init" :: Text) ])
        (systemContext "processor-stop")

    mTid <- atomically $ do
        tid <- readTVar processorVar
        writeTVar processorVar Nothing
        pure tid

    case mTid of
        Just tid -> do
            -- Log thread cancellation
            logOperation (qpAuditLogger processor)
                "system"
                "system"
                AdminAction
                (ConfigResource "merge-queue")
                (object
                    [ "action" .= ("processor_thread_cancel" :: Text)
                    , "thread_id" .= show tid
                    ])
                (systemContext "processor-stop")

            cancel tid

            -- Log successful stop
            logOperation (qpAuditLogger processor)
                "system"
                "system"
                AdminAction
                (ConfigResource "merge-queue")
                (object
                    [ "action" .= ("processor_stop_complete" :: Text)
                    , "thread_id" .= show tid
                    ])
                (systemContext "processor-stop")

        Nothing ->
            -- Log no processor running
            logOperation (qpAuditLogger processor)
                "system"
                "system"
                AdminAction
                (ConfigResource "merge-queue")
                (object
                    [ "action" .= ("processor_stop_noop" :: Text)
                    , "reason" .= ("no processor running" :: Text)
                    ])
                (systemContext "processor-stop")

-- | Process queue items
processQueue :: ProcessorConfig -> QueueProcessor -> TQueue QueueItem -> TVar QueueStatus -> IO ()
processQueue config processor queue status = do
    -- Get current queue status
    currentStatus <- atomically $ readTVar status

    -- Log queue status check
    logOperation (qpAuditLogger processor)
        "system"
        "system"
        AdminAction
        (ConfigResource "merge-queue")
        (object
            [ "action" .= ("queue_status_check" :: Text)
            , "status" .= object
                [ "active" .= qsActive currentStatus
                , "size" .= qsSize currentStatus
                , "processing" .= qsProcessing currentStatus
                , "errors" .= qsErrors currentStatus
                ]
            ])
        (systemContext "queue-status")

    -- Get batch of items to process
    items <- atomically $ do
        items <- flushTQueue queue
        let batch = take (pcBatchSize config) items
        -- Put remaining items back in queue
        mapM_ (writeTQueue queue) (drop (pcBatchSize config) items)
        pure batch

    -- Log batch acquisition
    when (not $ null items) $
        logOperation (qpAuditLogger processor)
            "system"
            "system"
            AdminAction
            (ConfigResource "merge-queue")
            (object
                [ "action" .= ("batch_acquired" :: Text)
                , "batch_size" .= length items
                , "total_items" .= length items
                ])
            (systemContext "batch-acquire")

    -- Process batch
    forM_ items $ \item -> do
        now <- getCurrentTime
        let item' = item { qiStarted = Just now }

        -- Log item processing start with detailed context
        logOperation (qpAuditLogger processor)
            (qiUserId item)
            (qiEnterpriseId item)
            MergeOperation
            (RepoResource $ "queue/" <> qiChangeId item)
            (object
                [ "action" .= ("item_processing_start" :: Text)
                , "item_id" .= qiId item
                , "change_id" .= qiChangeId item
                , "attempt" .= qiRetries item
                , "priority" .= qiPriority item
                , "dependencies" .= qiDependencies item
                , "wait_time" .= diffUTCTime now (qiSubmitted item)
                ])
            (queueContext item)

        -- Update queue status for processing
        atomically $ modifyTVar status $ \s -> s
            { qsProcessing = qsProcessing s + 1 }

        -- Process item
        result <- processItem config processor item'

        -- Get completion time for metrics
        completed <- getCurrentTime
        let processingTime = diffUTCTime completed now

        -- Update item status and log completion
        let finalItem = case result of
                Right () -> do
                    -- Log processing success with metrics
                    logOperation (qpAuditLogger processor)
                        (qiUserId item)
                        (qiEnterpriseId item)
                        MergeOperation
                        (RepoResource $ "queue/" <> qiChangeId item)
                        (object
                            [ "action" .= ("item_processing_success" :: Text)
                            , "item_id" .= qiId item
                            , "change_id" .= qiChangeId item
                            , "processing_time" .= processingTime
                            , "total_time" .= diffUTCTime completed (qiSubmitted item)
                            ])
                        (queueContext item)

                    item' { qiStatus = Merged, qiCompleted = Just completed }

                Left err -> do
                    -- Log processing failure with details
                    logOperation (qpAuditLogger processor)
                        (qiUserId item)
                        (qiEnterpriseId item)
                        MergeOperation
                        (RepoResource $ "queue/" <> qiChangeId item)
                        (object
                            [ "action" .= ("item_processing_failure" :: Text)
                            , "item_id" .= qiId item
                            , "change_id" .= qiChangeId item
                            , "error" .= err
                            , "processing_time" .= processingTime
                            , "total_time" .= diffUTCTime completed (qiSubmitted item)
                            , "attempt" .= qiRetries item
                            , "max_attempts" .= pcRetryLimit config
                            ])
                        (queueContext item)

                    item'
                        { qiStatus = if qiRetries item' >= pcRetryLimit config
                                    then Abandoned
                                    else Failed
                        , qiError = Just err
                        , qiCompleted = Just completed
                        }

        -- Update queue status
        atomically $ modifyTVar status $ \s -> s
            { qsProcessing = qsProcessing s - 1
            , qsLastProcessed = Just completed
            , qsErrors = qsErrors s + if isLeft result then 1 else 0
            }

    -- Log batch completion with metrics
    when (not $ null items) $ do
        let successCount = length [i | i <- items, qiStatus i == Merged]
            failureCount = length [i | i <- items, qiStatus i `elem` [Failed, Abandoned]]

        logOperation (qpAuditLogger processor)
            "system"
            "system"
            AdminAction
            (ConfigResource "merge-queue")
            (object
                [ "action" .= ("batch_complete" :: Text)
                , "total_items" .= length items
                , "successful" .= successCount
                , "failed" .= failureCount
                , "success_rate" .= (fromIntegral successCount / fromIntegral (length items) :: Double)
            ])
            (systemContext "batch-complete")

-- | Process a single queue item
processItem :: ProcessorConfig -> QueueProcessor -> QueueItem -> IO (Either Text ())
processItem config processor item = do
    -- Log item processing initialization
    logOperation (qpAuditLogger processor)
        (qiUserId item)
        (qiEnterpriseId item)
        MergeOperation
        (RepoResource $ "queue/" <> qiChangeId item)
        (object
            [ "action" .= ("item_processing_init" :: Text)
            , "item_id" .= qiId item
            , "change_id" .= qiChangeId item
            , "priority" .= qiPriority item
            , "dependencies" .= qiDependencies item
            ])
        (queueContext item)

    -- Check dependencies
    depsStartTime <- getCurrentTime
    depsReady <- checkDependencies processor item

    -- Log dependency check result
    logOperation (qpAuditLogger processor)
        (qiUserId item)
        (qiEnterpriseId item)
        MergeOperation
        (RepoResource $ "queue/" <> qiChangeId item)
        (object
            [ "action" .= ("dependency_check_complete" :: Text)
            , "item_id" .= qiId item
            , "dependencies_ready" .= depsReady
            , "check_duration" .= diffUTCTime depsStartTime (qiSubmitted item)
            ])
        (queueContext item)

    if not depsReady
        then do
            -- Log dependency check failure with details
            logOperation (qpAuditLogger processor)
                (qiUserId item)
                (qiEnterpriseId item)
                MergeOperation
                (RepoResource $ "queue/" <> qiChangeId item)
                (object
                    [ "action" .= ("dependency_check_failed" :: Text)
                    , "item_id" .= qiId item
                    , "change_id" .= qiChangeId item
                    , "dependencies" .= qiDependencies item
                    , "reason" .= ("dependencies not ready" :: Text)
                    ])
                    (queueContext item)

            pure $ Left "Dependencies not ready"
        else do
            -- Log merge attempt start
            mergeStartTime <- getCurrentTime
            logOperation (qpAuditLogger processor)
                (qiUserId item)
                (qiEnterpriseId item)
                MergeOperation
                (RepoResource $ "queue/" <> qiChangeId item)
                (object
                    [ "action" .= ("merge_attempt_start" :: Text)
                    , "item_id" .= qiId item
                    , "change_id" .= qiChangeId item
                    , "attempt" .= qiRetries item
                    , "wait_time" .= diffUTCTime mergeStartTime (qiSubmitted item)
                    ])
                    (queueContext item)

            -- Attempt merge
            result <- tryMerge processor item
            mergeEndTime <- getCurrentTime

            case result of
                Right () -> do
                    -- Log merge success with metrics
                    logOperation (qpAuditLogger processor)
                        (qiUserId item)
                        (qiEnterpriseId item)
                        MergeOperation
                        (RepoResource $ "queue/" <> qiChangeId item)
                        (object
                            [ "action" .= ("merge_attempt_success" :: Text)
                            , "item_id" .= qiId item
                            , "change_id" .= qiChangeId item
                            , "attempt" .= qiRetries item
                            , "merge_duration" .= diffUTCTime mergeEndTime mergeStartTime
                            , "total_duration" .= diffUTCTime mergeEndTime (qiSubmitted item)
                            ])
                            (queueContext item)

                    pure $ Right ()

                Left err
                    | qiRetries item < pcRetryLimit config -> do
                        -- Log retry decision with context
                        logOperation (qpAuditLogger processor)
                            (qiUserId item)
                            (qiEnterpriseId item)
                            MergeOperation
                            (RepoResource $ "queue/" <> qiChangeId item)
                            (object
                                [ "action" .= ("merge_retry_scheduled" :: Text)
                                , "item_id" .= qiId item
                                , "change_id" .= qiChangeId item
                                , "current_attempt" .= qiRetries item
                                , "next_attempt" .= (qiRetries item + 1)
                                , "max_attempts" .= pcRetryLimit config
                                , "retry_delay" .= pcRetryDelay config
                                , "error" .= err
                                ])
                                (queueContext item)

                        -- Retry after delay
                        threadDelay $ round $ pcRetryDelay config * 1000000
                        processItem config processor $ item { qiRetries = qiRetries item + 1 }

                    | otherwise -> do
                        -- Log max retries exceeded with full context
                        logOperation (qpAuditLogger processor)
                            (qiUserId item)
                            (qiEnterpriseId item)
                            MergeOperation
                            (RepoResource $ "queue/" <> qiChangeId item)
                            (object
                                [ "action" .= ("max_retries_exceeded" :: Text)
                                , "item_id" .= qiId item
                                , "change_id" .= qiChangeId item
                                , "attempts" .= qiRetries item
                                , "max_attempts" .= pcRetryLimit config
                                , "first_attempt" .= qiSubmitted item
                                , "last_attempt" .= mergeEndTime
                                , "total_duration" .= diffUTCTime mergeEndTime (qiSubmitted item)
                                , "error" .= err
                                ])
                                (queueContext item)

                        pure $ Left err

-- | Check if all dependencies are merged
checkDependencies :: QueueProcessor -> QueueItem -> IO Bool
checkDependencies processor item = do
    -- Log dependency check start with full context
    logOperation (qpAuditLogger processor)
        (qiUserId item)
        (qiEnterpriseId item)
        MergeOperation
        (RepoResource $ "queue/" <> qiChangeId item)
        (object
            [ "action" .= ("dependency_check_start" :: Text)
            , "item_id" .= qiId item
            , "change_id" .= qiChangeId item
            , "dependencies" .= qiDependencies item
            , "stack_id" .= qiStackId item
            ])
        (queueContext item)

    -- Check each dependency
    results <- forM (qiDependencies item) $ \depId -> do
        -- Get dependency status from storage
        depStatus <- getDependencyStatus (qpStorage processor) depId
        let result = depStatus == Just Merged

        -- Log individual dependency check
        logOperation (qpAuditLogger processor)
            (qiUserId item)
            (qiEnterpriseId item)
            MergeOperation
            (RepoResource $ "queue/" <> qiChangeId item)
            (object
                [ "action" .= ("dependency_check" :: Text)
                , "item_id" .= qiId item
                , "dependency_id" .= depId
                , "dependency_status" .= depStatus
                , "is_ready" .= result
                ])
                (queueContext item)

        pure result

    let allReady = all id results

    -- Log final dependency check result
    logOperation (qpAuditLogger processor)
        (qiUserId item)
        (qiEnterpriseId item)
        MergeOperation
        (RepoResource $ "queue/" <> qiChangeId item)
        (object
            [ "action" .= ("dependency_check_complete" :: Text)
            , "item_id" .= qiId item
            , "change_id" .= qiChangeId item
            , "all_dependencies_ready" .= allReady
            , "total_dependencies" .= length (qiDependencies item)
            , "ready_dependencies" .= length (filter id results)
            ])
            (queueContext item)

    pure allReady

-- | Attempt to merge a change
tryMerge :: QueueProcessor -> QueueItem -> IO (Either Text ())
tryMerge processor item = do
    -- Log merge attempt start with full context
    startTime <- getCurrentTime
    logOperation (qpAuditLogger processor)
        (qiUserId item)
        (qiEnterpriseId item)
        MergeOperation
        (RepoResource $ "queue/" <> qiChangeId item)
        (object
            [ "action" .= ("merge_attempt_start" :: Text)
            , "item_id" .= qiId item
            , "change_id" .= qiChangeId item
            , "attempt" .= qiRetries item
            , "stack_id" .= qiStackId item
            ])
        (queueContext item)

    -- Get repository and branches
    mEntry <- getChangeDetails (qpStorage processor) (qiChangeId item)
    case mEntry of
        Nothing -> do
            -- Log change not found error
            logOperation (qpAuditLogger processor)
                (qiUserId item)
                (qiEnterpriseId item)
                MergeOperation
                (RepoResource $ "queue/" <> qiChangeId item)
                (object
                    [ "action" .= ("merge_attempt_error" :: Text)
                    , "item_id" .= qiId item
                    , "error" .= ("change not found" :: Text)
                    ])
                    (queueContext item)

            pure $ Left "Change not found"

        Just entry -> do
            -- Create workspace for merge
            let wsName = "merge-" <> qiId item
            createResult <- try $ do
                -- Create and switch to workspace
                workspace <- createWorkspace (qpVCS processor) (meRepository entry) wsName
                switchWorkspace (qpVCS processor) (meRepository entry) wsName
                pure workspace

            case createResult of
                Left err -> do
                    -- Log workspace creation failure
                    logOperation (qpAuditLogger processor)
                        (qiUserId item)
                        (qiEnterpriseId item)
                        MergeOperation
                        (RepoResource $ "queue/" <> qiChangeId item)
                        (object
                            [ "action" .= ("workspace_creation_failed" :: Text)
                            , "item_id" .= qiId item
                            , "workspace" .= wsName
                            , "error" .= show err
                            ])
                            (queueContext item)

                    pure $ Left "Failed to create workspace"

                Right workspace -> do
                    -- Attempt merge
                    mergeResult <- try $ merge (qpVCS processor) (meRepository entry) (meSource entry)

                    endTime <- getCurrentTime
                    case mergeResult of
                        Right () -> do
                            -- Commit changes
                            commitResult <- try $ commitWorkspace (qpVCS processor) workspace

                            case commitResult of
                                Right () -> do
                                    -- Log successful merge
                                    logOperation (qpAuditLogger processor)
                                        (qiUserId item)
                                        (qiEnterpriseId item)
                                        MergeOperation
                                        (RepoResource $ "queue/" <> qiChangeId item)
                                        (object
                                            [ "action" .= ("merge_attempt_success" :: Text)
                                            , "item_id" .= qiId item
                                            , "change_id" .= qiChangeId item
                                            , "duration" .= diffUTCTime endTime startTime
                                            , "source" .= meSource entry
                                            , "target" .= meTarget entry
                                            ])
                                            (queueContext item)

                                    pure $ Right ()

                                Left err -> do
                                    -- Log commit failure
                                    logOperation (qpAuditLogger processor)
                                        (qiUserId item)
                                        (qiEnterpriseId item)
                        -- Log merge failure
                        logOperation qpAuditLogger
                            (meUserId entry)
                            (meEnterpriseId entry)
                            MergeOperation
                            (RepoResource $ repoPath $ meRepository entry)
                            (object
                                [ "action" .= ("merge_failure" :: Text)
                                , "source" .= meSource entry
                                , "target" .= meTarget entry
                                , "error" .= err
                                ])
                                (defaultContext entry)

                        -- Merge failed
                        let status = Failed err
                        updateEntryStatus qpStorage (meId entry) status
                        deliverEvent qpWebhooks StatusChanged $ object
                            [ "entry_id" .= meId entry
                            , "status" .= status
                            ]
                        when (isConflict err) $
                            deliverEvent qpWebhooks ConflictDetected $ object
                                [ "entry_id" .= meId entry
                                , "error" .= err
                                ]

            else do
                -- Log validation failure
                logOperation qpAuditLogger
                    (meUserId entry)
                    (meEnterpriseId entry)
                    ReviewActivity
                    (ReviewResource $ "merge/" <> unEntryId (meId entry))
                    (object
                        [ "action" .= ("validation_failure" :: Text)
                        , "results" .= validationResults
                        ])
                        (defaultContext entry)

                -- Validation failed
                let status = Failed ValidationFailed
                updateEntryStatus qpStorage (meId entry) status
                deliverEvent qpWebhooks StatusChanged $ object
                    [ "entry_id" .= meId entry
                    , "status" .= status
                    ]

-- | Create default audit context for merge operations
defaultContext :: MergeEntry -> AuditContext
defaultContext entry = AuditContext
    { acRequestId = "merge-" <> unEntryId (meId entry)
    , acIpAddress = "internal"
    , acUserAgent = "merge-queue"
    , acSessionId = Nothing
    }

-- | Helper function to create queue context
queueContext :: QueueItem -> AuditContext
queueContext item = AuditContext
    { acRequestId = "queue-" <> qiId item
    , acIpAddress = "internal"
    , acUserAgent = "merge-queue"
    , acSessionId = Nothing
    }

-- | Helper function to create system context
systemContext :: Text -> AuditContext
systemContext action = AuditContext
    { acRequestId = "system-" <> action
    , acIpAddress = "internal"
    , acUserAgent = "merge-queue"
    , acSessionId = Nothing
    }
