{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Alerts
    ( -- * Handlers
      handleListAlerts
    , handleCreateAlert
    , handleGetAlert
    , handleAcknowledgeAlert
    , handleUpdateAlertStatus
    , handleDeleteAlert
      -- * Request Types
    , CreateAlertRequest(..)
    , AcknowledgeAlertRequest(..)
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson
import Data.Text (Text)
import Data.Time (getCurrentTime, diffUTCTime)
import Servant

import Gerrit.Models.Alert
import Gerrit.Api.Types (Response(..), ErrorResponse(..))
import Gerrit.Api.Config (Config(..))
import Gerrit.Api.Metrics (Metrics(..), incrementErrors, incrementAlerts, observeAlertDuration, incrementAlertOperations)
import Gerrit.VCS.Notification (NotificationSystem(..), NotificationType(..))

-- | Request to create a new alert
data CreateAlertRequest = CreateAlertRequest
    { createAlertTitle :: Text
    , createAlertMessage :: Text
    , createAlertSeverity :: AlertSeverity
    , createAlertSource :: Text
    , createAlertMetadata :: Maybe Value
    } deriving (Show, Eq)

instance FromJSON CreateAlertRequest where
    parseJSON = withObject "CreateAlertRequest" $ \v -> CreateAlertRequest
        <$> v .: "title"
        <*> v .: "message"
        <*> v .: "severity"
        <*> v .: "source"
        <*> v .:? "metadata"

-- | Request to acknowledge an alert
data AcknowledgeAlertRequest = AcknowledgeAlertRequest
    { acknowledgeUserId :: Text
    } deriving (Show, Eq)

instance FromJSON AcknowledgeAlertRequest where
    parseJSON = withObject "AcknowledgeAlertRequest" $ \v -> AcknowledgeAlertRequest
        <$> v .: "user_id"

-- | Handler to list active alerts
handleListAlerts :: Maybe AlertSeverity -> Maybe Text -> Handler (Response [Alert])
handleListAlerts maybeSeverity maybeSource = do
    config <- asks getConfig
    metrics <- asks getMetrics
    startTime <- liftIO getCurrentTime

    -- Track operation
    liftIO $ incrementAlertOperations metrics "list"

    alerts <- liftIO $ case (maybeSeverity, maybeSource) of
        (Just severity, _) -> runDB (configDbPath config) $ getAlertsBySeverity severity
        (_, Just source) -> runDB (configDbPath config) $ getAlertsBySource source
        _ -> runDB (configDbPath config) getActiveAlerts

    -- Record duration
    endTime <- liftIO getCurrentTime
    liftIO $ observeAlertDuration metrics "list" $ realToFrac $ diffUTCTime endTime startTime

    return $ Response
        { success = True
        , data_ = Just alerts
        , audit = Nothing
        , error = Nothing
        }

-- | Handler to create a new alert
handleCreateAlert :: CreateAlertRequest -> Handler (Response Alert)
handleCreateAlert CreateAlertRequest{..} = do
    config <- asks getConfig
    metrics <- asks getMetrics
    notifier <- asks getNotifier
    startTime <- liftIO getCurrentTime

    -- Track operation and increment alert counter
    liftIO $ do
        incrementAlertOperations metrics "create"
        incrementAlerts metrics createAlertSeverity

    alert <- liftIO $ createAlert
        (configDbPath config)
        createAlertTitle
        createAlertMessage
        createAlertSeverity
        createAlertSource
        createAlertMetadata

    -- Send notification
    liftIO $ notifyNewAlert notifier alert

    -- Record duration
    endTime <- liftIO getCurrentTime
    liftIO $ observeAlertDuration metrics "create" $ realToFrac $ diffUTCTime endTime startTime

    return $ Response
        { success = True
        , data_ = Just alert
        , audit = Nothing
        , error = Nothing
        }

-- | Handler to get a specific alert
handleGetAlert :: Text -> Handler (Response Alert)
handleGetAlert alertId' = do
    config <- asks getConfig
    metrics <- asks getMetrics
    startTime <- liftIO getCurrentTime

    -- Track operation
    liftIO $ incrementAlertOperations metrics "get"

    maybeAlert <- liftIO $ getAlertById (configDbPath config) alertId'

    -- Record duration
    endTime <- liftIO getCurrentTime
    liftIO $ observeAlertDuration metrics "get" $ realToFrac $ diffUTCTime endTime startTime

    case maybeAlert of
        Just alert -> return $ Response
            { success = True
            , data_ = Just alert
            , audit = Nothing
            , error = Nothing
            }
        Nothing -> do
            liftIO $ incrementErrors metrics
            throwError err404
                { errBody = "Alert not found"
                }

-- | Handler to acknowledge an alert
handleAcknowledgeAlert :: Text -> AcknowledgeAlertRequest -> Handler (Response Alert)
handleAcknowledgeAlert alertId' AcknowledgeAlertRequest{..} = do
    config <- asks getConfig
    metrics <- asks getMetrics
    notifier <- asks getNotifier
    startTime <- liftIO getCurrentTime

    -- Track operation
    liftIO $ incrementAlertOperations metrics "acknowledge"

    maybeAlert <- liftIO $ getAlertById (configDbPath config) alertId'
    case maybeAlert of
        Just alert -> do
            result <- liftIO $ acknowledgeAlert (configDbPath config) alert acknowledgeUserId

            -- Send notification
            liftIO $ notifyAlertAcknowledged notifier result acknowledgeUserId

            -- Record duration
            endTime <- liftIO getCurrentTime
            liftIO $ observeAlertDuration metrics "acknowledge" $ realToFrac $ diffUTCTime endTime startTime

            return $ Response
                { success = True
                , data_ = Just result
                , audit = Nothing
                , error = Nothing
                }
        Nothing -> do
            liftIO $ incrementErrors metrics
            throwError err404
                { errBody = "Alert not found"
                }

-- | Handler to update alert status
handleUpdateAlertStatus :: Text -> AlertStatus -> Handler (Response Alert)
handleUpdateAlertStatus alertId' newStatus = do
    config <- asks getConfig
    metrics <- asks getMetrics
    notifier <- asks getNotifier
    startTime <- liftIO getCurrentTime

    -- Track operation
    liftIO $ incrementAlertOperations metrics "update_status"

    maybeAlert <- liftIO $ getAlertById (configDbPath config) alertId'
    case maybeAlert of
        Just alert -> do
            result <- liftIO $ updateAlertStatus (configDbPath config) alert newStatus

            -- Send notification
            liftIO $ notifyAlertStatusChanged notifier result newStatus

            -- Record duration
            endTime <- liftIO getCurrentTime
            liftIO $ observeAlertDuration metrics "update_status" $ realToFrac $ diffUTCTime endTime startTime

            return $ Response
                { success = True
                , data_ = Just result
                , audit = Nothing
                , error = Nothing
                }
        Nothing -> do
            liftIO $ incrementErrors metrics
            throwError err404
                { errBody = "Alert not found"
                }

-- | Handler to delete an alert
handleDeleteAlert :: Text -> Handler (Response ())
handleDeleteAlert alertId' = do
    config <- asks getConfig
    metrics <- asks getMetrics
    notifier <- asks getNotifier
    startTime <- liftIO getCurrentTime

    -- Track operation
    liftIO $ incrementAlertOperations metrics "delete"

    -- Get alert before deletion for notification
    maybeAlert <- liftIO $ getAlertById (configDbPath config) alertId'

    liftIO $ runDB (configDbPath config) $ SQLiteM $ \conn ->
        execute conn "DELETE FROM alerts WHERE id = ?" (Only alertId')

    -- Send notification if alert existed
    case maybeAlert of
        Just alert -> liftIO $ notifyAlertDeleted notifier alert
        Nothing -> return ()

    -- Record duration
    endTime <- liftIO getCurrentTime
    liftIO $ observeAlertDuration metrics "delete" $ realToFrac $ diffUTCTime endTime startTime

    return $ Response
        { success = True
        , data_ = Just ()
        , audit = Nothing
        , error = Nothing
        }
