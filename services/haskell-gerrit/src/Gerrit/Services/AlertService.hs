-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.AlertService
    ( -- * Types
      AlertService(..)
    , AlertConfig(..)
      -- * Service
    , initAlertService
    , startAlertService
    , stopAlertService
      -- * Alert Operations
    , processAlert
    , evaluateAlertRules
    , notifyAlert
    ) where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Monad (forever, void, when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist.Sql (ConnectionPool)

import Gerrit.Models.Alert
import Gerrit.Models.AlertRule
import Gerrit.Models.Metrics (Metrics)
import Gerrit.VCS.Notification (NotificationSystem, notifyNewAlert)

-- | Alert service configuration
data AlertConfig = AlertConfig
    { alertEvaluationInterval :: Int  -- ^ Interval in seconds between rule evaluations
    , alertRetentionDays :: Int       -- ^ Number of days to retain resolved alerts
    , alertBatchSize :: Int           -- ^ Maximum number of alerts to process in one batch
    }

-- | Alert service state
data AlertService = AlertService
    { alertConfig :: AlertConfig
    , alertPool :: ConnectionPool
    , alertNotifier :: NotificationSystem
    , alertMetrics :: Metrics
    , alertThread :: Maybe ThreadId
    }

-- | Initialize the alert service
initAlertService :: ConnectionPool -> NotificationSystem -> Metrics -> AlertConfig -> IO AlertService
initAlertService pool notifier metrics config = do
    return AlertService
        { alertConfig = config
        , alertPool = pool
        , alertNotifier = notifier
        , alertMetrics = metrics
        , alertThread = Nothing
        }

-- | Start the alert service
startAlertService :: AlertService -> IO AlertService
startAlertService service = do
    threadId <- forkIO $ alertServiceLoop service
    return service { alertThread = Just threadId }

-- | Stop the alert service
stopAlertService :: AlertService -> IO ()
stopAlertService AlertService{..} =
    mapM_ killThread alertThread

-- | Main alert service loop
alertServiceLoop :: AlertService -> IO ()
alertServiceLoop service@AlertService{..} = forever $ do
    -- Evaluate alert rules
    void $ evaluateAlertRules service

    -- Clean up old alerts
    void $ cleanupOldAlerts service

    -- Wait for next evaluation interval
    threadDelay $ alertEvaluationInterval alertConfig * 1000000

-- | Process a new alert
processAlert :: MonadIO m => AlertService -> Alert -> m ()
processAlert AlertService{..} alert = do
    -- Record the alert
    void $ createAlert
        (alertTitle alert)
        (alertMessage alert)
        (alertSeverity alert)
        (alertSource alert)
        (alertMetadata alert)

    -- Send notification
    liftIO $ notifyNewAlert alertNotifier alert

-- | Evaluate all enabled alert rules
evaluateAlertRules :: MonadIO m => AlertService -> m [Alert]
evaluateAlertRules AlertService{..} = do
    -- Get all enabled rules
    rules <- listAlertRules Nothing Nothing True 0 (alertBatchSize alertConfig)

    -- Evaluate each rule
    alerts <- concat <$> mapM evaluateRule rules

    -- Process any new alerts
    mapM_ (processAlert service) alerts

    return alerts
  where
    evaluateRule (Entity _ rule) = do
        -- Get metrics for evaluation
        metrics <- getCurrentMetrics alertMetrics

        -- Evaluate rule conditions
        let condition = alertRuleCondition rule
        let result = evaluateCondition condition metrics

        -- Generate alert if condition is met
        if result
            then do
                now <- liftIO getCurrentTime
                let alert = Alert
                        { alertTitle = "Alert Rule: " <> alertRuleName rule
                        , alertMessage = generateAlertMessage rule metrics
                        , alertSeverity = readSeverity $ alertRuleSeverity rule
                        , alertStatus = New
                        , alertSource = "alert_rule"
                        , alertTimestamp = now
                        , alertAcknowledgedBy = Nothing
                        , alertAcknowledgedAt = Nothing
                        , alertMetadata = Just $ object
                            [ "rule_id" .= alertRuleRuleId rule
                            , "metrics" .= metrics
                            ]
                        }
                return [alert]
            else return []

-- | Clean up old resolved alerts
cleanupOldAlerts :: MonadIO m => AlertService -> m ()
cleanupOldAlerts AlertService{..} = do
    now <- liftIO getCurrentTime
    let cutoff = addUTCTime (fromIntegral $ -86400 * alertRetentionDays alertConfig) now

    -- Find old resolved alerts
    alerts <- listAlerts
        Nothing
        (Just Resolved)
        Nothing
        0
        (alertBatchSize alertConfig)

    -- Delete alerts older than retention period
    mapM_ deleteOldAlert alerts
  where
    deleteOldAlert (Entity _ alert)
        | alertTimestamp alert < cutoff = void $ deleteAlert (alertId alert)
        | otherwise = return ()

-- | Helper function to evaluate alert conditions
evaluateCondition :: AlertCondition -> Metrics -> Bool
evaluateCondition condition metrics = case condition of
    ThresholdCondition{..} ->
        let value = getMetricValue metrics metric
        in maybe False (checkThreshold operator threshold) value

    PatternCondition{..} ->
        let value = getMetricString metrics pattern
        in maybe False (matchPattern matchType) value

    CompositeCondition{..} ->
        let results = map (`evaluateCondition` metrics) conditions
        in combineResults combinator results

-- | Helper function to check threshold conditions
checkThreshold :: Text -> Double -> Double -> Bool
checkThreshold op threshold value = case op of
    "gt" -> value > threshold
    "lt" -> value < threshold
    "gte" -> value >= threshold
    "lte" -> value <= threshold
    "eq" -> value == threshold
    _ -> False

-- | Helper function to match patterns
matchPattern :: Text -> Text -> Bool
matchPattern matchType pattern = case matchType of
    "exact" -> pattern == pattern
    "contains" -> pattern `Text.isInfixOf` pattern
    "startsWith" -> pattern `Text.isPrefixOf` pattern
    "endsWith" -> pattern `Text.isSuffixOf` pattern
    _ -> False

-- | Helper function to combine multiple conditions
combineResults :: Text -> [Bool] -> Bool
combineResults combinator results = case combinator of
    "and" -> all id results
    "or" -> any id results
    _ -> False

-- | Helper function to generate alert message
generateAlertMessage :: AlertRule -> Metrics -> Text
generateAlertMessage rule metrics =
    let condition = alertRuleCondition rule
        value = case condition of
            ThresholdCondition{..} -> maybe "N/A" Text.pack $ fmap show $ getMetricValue metrics metric
            PatternCondition{..} -> maybe "N/A" id $ getMetricString metrics pattern
            CompositeCondition{..} -> "Multiple conditions"
    in Text.unwords
        [ "Alert rule"
        , quotedText (alertRuleName rule)
        , "triggered with value:"
        , value
        ]
  where
    quotedText t = "\"" <> t <> "\""

-- | Helper function to read severity level
readSeverity :: Text -> AlertSeverity
readSeverity t = case t of
    "critical" -> Critical
    "warning" -> Warning
    _ -> Info
