{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Revision
    ( -- * Handlers
      handleCreateRevision
    , handleUpdateRevision
    , handleGetRevision
    , handleListRevisions
    , handleGetLatestRevision
    , handleDeleteRevision
    , handleAnalyzeRevision
    , handleGetRevisionStats
    , handleGetRevisionDiff
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Types.Status
import Web.Scotty.Trans

import Gerrit.Api.Types
import Gerrit.Models.Revision
import Gerrit.Services.RevisionService
import qualified Gerrit.Services.RevisionService as RevisionService

-- | Request types
data CreateRevisionRequest = CreateRevisionRequest
    { createChangeId :: Text
    , createCommitId :: Text
    , createDescription :: Maybe Text
    }

data UpdateRevisionRequest = UpdateRevisionRequest
    { updateDescription :: Maybe Text
    }

-- | Handler to create a new revision
handleCreateRevision :: MonadIO m
                    => RevisionService
                    -> ActionT Error m ()
handleCreateRevision service = do
    -- Parse request
    CreateRevisionRequest{..} <- jsonData

    -- Get user ID from auth context
    userId <- requireUserId

    -- Create revision
    result <- liftIO $ RevisionService.createRevision
        service
        createChangeId
        createCommitId
        userId
        createDescription

    case result of
        Left err -> do
            status badRequest400
            json $ object
                [ "status" .= ("error" :: Text)
                , "error" .= show err
                ]
        Right revision -> do
            status created201
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= revision
                ]

-- | Handler to update a revision
handleUpdateRevision :: MonadIO m
                    => RevisionService
                    -> Text  -- ^ Revision ID
                    -> ActionT Error m ()
handleUpdateRevision service revisionId = do
    -- Parse request
    UpdateRevisionRequest{..} <- jsonData

    -- Get revision
    result <- liftIO $ RevisionService.getRevision service revisionId
    case result of
        Left err -> do
            status notFound404
            json $ object
                [ "status" .= ("error" :: Text)
                , "error" .= show err
                ]
        Right revision -> do
            -- Update revision
            updateResult <- liftIO $ RevisionService.updateRevision
                service
                revision
                updateDescription

            case updateResult of
                Left err -> do
                    status badRequest400
                    json $ object
                        [ "status" .= ("error" :: Text)
                        , "error" .= show err
                        ]
                Right updated -> do
                    status ok200
                    json $ object
                        [ "status" .= ("success" :: Text)
                        , "data" .= updated
                        ]

-- | Handler to get a revision
handleGetRevision :: MonadIO m
                  => RevisionService
                  -> Text  -- ^ Revision ID
                  -> ActionT Error m ()
handleGetRevision service revisionId = do
    result <- liftIO $ RevisionService.getRevision service revisionId
    case result of
        Left err -> do
            status notFound404
            json $ object
                [ "status" .= ("error" :: Text)
                , "error" .= show err
                ]
        Right revision -> do
            status ok200
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= revision
                ]

-- | Handler to list revisions for a change
handleListRevisions :: MonadIO m
                   => RevisionService
                   -> ActionT Error m ()
handleListRevisions service = do
    -- Get change ID from query params
    changeId <- param "change_id"

    result <- liftIO $ RevisionService.listRevisions service changeId
    case result of
        Left err -> do
            status badRequest400
            json $ object
                [ "status" .= ("error" :: Text)
                , "error" .= show err
                ]
        Right revisions -> do
            status ok200
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= revisions
                ]

-- | Handler to get latest revision for a change
handleGetLatestRevision :: MonadIO m
                       => RevisionService
                       -> ActionT Error m ()
handleGetLatestRevision service = do
    -- Get change ID from query params
    changeId <- param "change_id"

    result <- liftIO $ RevisionService.getLatestRevision service changeId
    case result of
        Left err -> do
            status notFound404
            json $ object
                [ "status" .= ("error" :: Text)
                , "error" .= show err
                ]
        Right revision -> do
            status ok200
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= revision
                ]

-- | Handler to delete a revision
handleDeleteRevision :: MonadIO m
                    => RevisionService
                    -> Text  -- ^ Revision ID
                    -> ActionT Error m ()
handleDeleteRevision service revisionId = do
    -- Get revision
    result <- liftIO $ RevisionService.getRevision service revisionId
    case result of
        Left err -> do
            status notFound404
            json $ object
                [ "status" .= ("error" :: Text)
                , "error" .= show err
                ]
        Right revision -> do
            -- Delete revision
            deleteResult <- liftIO $ RevisionService.deleteRevision service revision
            case deleteResult of
                Left err -> do
                    status badRequest400
                    json $ object
                        [ "status" .= ("error" :: Text)
                        , "error" .= show err
                        ]
                Right _ -> do
                    status ok200
                    json $ object ["status" .= ("success" :: Text)]

-- | Handler to analyze revision changes
handleAnalyzeRevision :: MonadIO m
                     => RevisionService
                     -> Text  -- ^ Revision ID
                     -> ActionT Error m ()
handleAnalyzeRevision service revisionId = do
    -- Get revision
    result <- liftIO $ RevisionService.getRevision service revisionId
    case result of
        Left err -> do
            status notFound404
            json $ object
                [ "status" .= ("error" :: Text)
                , "error" .= show err
                ]
        Right revision -> do
            -- Analyze revision
            analysisResult <- liftIO $ RevisionService.analyzeRevisionChanges service revision
            case analysisResult of
                Left err -> do
                    status internalServerError500
                    json $ object
                        [ "status" .= ("error" :: Text)
                        , "error" .= show err
                        ]
                Right analysis -> do
                    status ok200
                    json $ object
                        [ "status" .= ("success" :: Text)
                        , "data" .= analysis
                        ]

-- | Handler to get revision statistics
handleGetRevisionStats :: MonadIO m
                      => RevisionService
                      -> Text  -- ^ Revision ID
                      -> ActionT Error m ()
handleGetRevisionStats service revisionId = do
    -- Get revision
    result <- liftIO $ RevisionService.getRevision service revisionId
    case result of
        Left err -> do
            status notFound404
            json $ object
                [ "status" .= ("error" :: Text)
                , "error" .= show err
                ]
        Right revision -> do
            -- Get stats
            statsResult <- liftIO $ RevisionService.getRevisionStats service revision
            case statsResult of
                Left err -> do
                    status internalServerError500
                    json $ object
                        [ "status" .= ("error" :: Text)
                        , "error" .= show err
                        ]
                Right stats -> do
                    status ok200
                    json $ object
                        [ "status" .= ("success" :: Text)
                        , "data" .= stats
                        ]

-- | Handler to get revision diff
handleGetRevisionDiff :: MonadIO m
                     => RevisionService
                     -> Text  -- ^ Revision ID
                     -> ActionT Error m ()
handleGetRevisionDiff service revisionId = do
    -- Get revision
    result <- liftIO $ RevisionService.getRevision service revisionId
    case result of
        Left err -> do
            status notFound404
            json $ object
                [ "status" .= ("error" :: Text)
                , "error" .= show err
                ]
        Right revision -> do
            -- Get diff
            diffResult <- liftIO $ RevisionService.getRevisionDiff service revision
            case diffResult of
                Left err -> do
                    status internalServerError500
                    json $ object
                        [ "status" .= ("error" :: Text)
                        , "error" .= show err
                        ]
                Right diff -> do
                    status ok200
                    json $ object
                        [ "status" .= ("success" :: Text)
                        , "data" .= diff
                        ]
```
