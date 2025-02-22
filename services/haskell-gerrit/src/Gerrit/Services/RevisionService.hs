{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module Gerrit.Services.RevisionService
    ( -- * Types
      RevisionService(..)
    , RevisionError(..)
      -- * Service Operations
    , initRevisionService
    , createRevision
    , updateRevision
    , getRevision
    , listRevisions
    , getLatestRevision
    , validateRevision
    , deleteRevision
      -- * Revision Analysis
    , analyzeRevisionChanges
    , getRevisionStats
    , getRevisionDiff
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, asks)
import Data.Aeson (ToJSON(..), FromJSON(..), Value)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Change (Change)
import Gerrit.Models.Revision
import Gerrit.Services.NotificationService (NotificationService)
import qualified Gerrit.Services.NotificationService as Notification
import Gerrit.Services.MetricsService (MetricsService)
import qualified Gerrit.Services.MetricsService as Metrics

-- | Revision service errors
data RevisionError
    = RevisionNotFound Text
    | ChangeNotFound Text
    | InvalidRevision Text
    | DatabaseError Text
    | ValidationError Text
    | PermissionDenied Text
    | DiffGenerationError Text
    deriving (Show, Eq, Generic)

instance ToJSON RevisionError
instance FromJSON RevisionError

-- | Revision service
data RevisionService = RevisionService
    { revisionPool :: ConnectionPool
    , revisionNotificationService :: NotificationService
    , revisionMetricsService :: MetricsService
    }

-- | Initialize the revision service
initRevisionService :: MonadIO m
                   => ConnectionPool
                   -> NotificationService
                   -> MetricsService
                   -> m RevisionService
initRevisionService pool notificationSvc metricsSvc =
    return $ RevisionService
        { revisionPool = pool
        , revisionNotificationService = notificationSvc
        , revisionMetricsService = metricsSvc
        }

-- | Create a new revision
createRevision :: MonadIO m
               => RevisionService
               -> Text  -- ^ Change ID
               -> Text  -- ^ Commit ID
               -> Text  -- ^ Uploader ID
               -> Maybe Text  -- ^ Description
               -> m (Either RevisionError (Entity Revision))
createRevision RevisionService{..} changeId commitId uploaderId description = do
    -- Validate change exists
    mChange <- runSqlPool (get changeId) revisionPool
    case mChange of
        Nothing -> return $ Left $ ChangeNotFound changeId
        Just _ -> do
            -- Create revision
            result <- try $ Gerrit.Models.Revision.createRevision
                revisionPool
                changeId
                commitId
                uploaderId
                description

            case result of
                Left err -> return $ Left $ DatabaseError $ T.pack $ show err
                Right revision -> do
                    -- Send notification
                    void $ Notification.sendRevisionCreated
                        revisionNotificationService
                        (entityVal revision)

                    -- Record metrics
                    void $ Metrics.recordRevisionCreated
                        revisionMetricsService
                        (entityVal revision)

                    return $ Right revision

-- | Update a revision
updateRevision :: MonadIO m
               => RevisionService
               -> Entity Revision
               -> Maybe Text  -- ^ New description
               -> m (Either RevisionError (Entity Revision))
updateRevision RevisionService{..} (Entity key revision) newDescription = do
    now <- liftIO getCurrentTime
    let updatedRevision = revision
            { revisionDescription = newDescription
            , revisionUpdated = now
            }

    -- Update revision
    result <- try $ runSqlPool (replace key updatedRevision) revisionPool
    case result of
        Left err -> return $ Left $ DatabaseError $ T.pack $ show err
        Right _ -> do
            let updated = Entity key updatedRevision

            -- Send notification
            void $ Notification.sendRevisionUpdated
                revisionNotificationService
                updatedRevision

            -- Record metrics
            void $ Metrics.recordRevisionUpdated
                revisionMetricsService
                updatedRevision

            return $ Right updated

-- | Get a revision by ID
getRevision :: MonadIO m
            => RevisionService
            -> Text  -- ^ Revision ID
            -> m (Either RevisionError (Entity Revision))
getRevision RevisionService{..} revisionId = do
    result <- runSqlPool (getBy $ UniqueRevisionId revisionId) revisionPool
    case result of
        Nothing -> return $ Left $ RevisionNotFound revisionId
        Just revision -> return $ Right revision

-- | List revisions for a change
listRevisions :: MonadIO m
              => RevisionService
              -> Text  -- ^ Change ID
              -> m (Either RevisionError [Entity Revision])
listRevisions RevisionService{..} changeId = do
    -- Validate change exists
    mChange <- runSqlPool (get changeId) revisionPool
    case mChange of
        Nothing -> return $ Left $ ChangeNotFound changeId
        Just _ -> do
            revisions <- runSqlPool
                (selectList [RevisionChangeId ==. changeId] [Asc RevisionNumber])
                revisionPool
            return $ Right revisions

-- | Get the latest revision for a change
getLatestRevision :: MonadIO m
                  => RevisionService
                  -> Text  -- ^ Change ID
                  -> m (Either RevisionError (Entity Revision))
getLatestRevision RevisionService{..} changeId = do
    -- Validate change exists
    mChange <- runSqlPool (get changeId) revisionPool
    case mChange of
        Nothing -> return $ Left $ ChangeNotFound changeId
        Just _ -> do
            result <- runSqlPool
                (selectFirst [RevisionChangeId ==. changeId] [Desc RevisionNumber])
                revisionPool
            case result of
                Nothing -> return $ Left $ RevisionNotFound changeId
                Just revision -> return $ Right revision

-- | Validate a revision
validateRevision :: MonadIO m
                => RevisionService
                -> Entity Revision
                -> m (Either RevisionError ())
validateRevision RevisionService{..} (Entity _ revision) = do
    -- Validate change exists
    mChange <- runSqlPool (get $ revisionChangeId revision) revisionPool
    case mChange of
        Nothing -> return $ Left $ ChangeNotFound $ revisionChangeId revision
        Just _ -> do
            -- Add additional validation logic here
            -- For example:
            -- - Check commit exists in repository
            -- - Validate commit message format
            -- - Check file permissions
            -- - etc.
            return $ Right ()

-- | Delete a revision
deleteRevision :: MonadIO m
               => RevisionService
               -> Entity Revision
               -> m (Either RevisionError ())
deleteRevision RevisionService{..} (Entity key revision) = do
    -- Delete revision
    result <- try $ runSqlPool (delete key) revisionPool
    case result of
        Left err -> return $ Left $ DatabaseError $ T.pack $ show err
        Right _ -> do
            -- Send notification
            void $ Notification.sendRevisionDeleted
                revisionNotificationService
                revision

            -- Record metrics
            void $ Metrics.recordRevisionDeleted
                revisionMetricsService
                revision

            return $ Right ()

-- | Analyze changes in a revision
analyzeRevisionChanges :: MonadIO m
                      => RevisionService
                      -> Entity Revision
                      -> m (Either RevisionError Value)
analyzeRevisionChanges RevisionService{..} (Entity _ revision) = do
    -- Implement revision analysis logic
    -- For example:
    -- - Get diff stats
    -- - Analyze code complexity changes
    -- - Check for potential issues
    -- - Generate review suggestions
    return $ Right $ object
        [ "revision_id" .= revisionRevisionId revision
        , "analysis" .= object
            [ "files_changed" .= (0 :: Int)
            , "insertions" .= (0 :: Int)
            , "deletions" .= (0 :: Int)
            , "complexity_score" .= (0 :: Double)
            ]
        ]

-- | Get revision statistics
getRevisionStats :: MonadIO m
                 => RevisionService
                 -> Entity Revision
                 -> m (Either RevisionError Value)
getRevisionStats RevisionService{..} (Entity _ revision) = do
    -- Implement revision statistics logic
    -- For example:
    -- - Number of files changed
    -- - Lines added/removed
    -- - File types affected
    -- - etc.
    return $ Right $ object
        [ "revision_id" .= revisionRevisionId revision
        , "stats" .= object
            [ "files_changed" .= (0 :: Int)
            , "lines_added" .= (0 :: Int)
            , "lines_removed" .= (0 :: Int)
            ]
        ]

-- | Get revision diff
getRevisionDiff :: MonadIO m
                => RevisionService
                -> Entity Revision
                -> m (Either RevisionError Value)
getRevisionDiff RevisionService{..} (Entity _ revision) = do
    -- Implement diff generation logic
    -- For example:
    -- - Get diff from VCS
    -- - Format diff for display
    -- - Add metadata
    -- - etc.
    return $ Right $ object
        [ "revision_id" .= revisionRevisionId revision
        , "diff" .= object
            [ "files" .= ([] :: [Value])
            , "stats" .= object
                [ "files_changed" .= (0 :: Int)
                , "insertions" .= (0 :: Int)
                , "deletions" .= (0 :: Int)
                ]
            ]
        ]
