{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Alerts
    ( -- * Types
      Alert(..)
    , AlertSeverity(..)
    , AlertStatus(..)
    , AlertRule(..)
    , AlertThreshold(..)
      -- * Alert Management
    , getActiveAlerts
    , acknowledgeAlert
    , createAlert
    , updateAlertStatus
    , deleteAlert
      -- * Alert Rules
    , checkThresholds
    , evaluateMetrics
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime)
import Database.SQLite.Simple (FromRow(..), ToRow(..))
import GHC.Generics (Generic)
import qualified Data.Text as Text
import qualified Data.Set as Set

import Gerrit.Api.Metrics (Metrics(..))
import Gerrit.Database.Operations (SQLiteM(..), runDB)

-- | Alert severity levels
data AlertSeverity
    = Critical
    | Warning
    | Info
    deriving (Show, Eq, Generic)

instance FromJSON AlertSeverity
instance ToJSON AlertSeverity

-- | Alert status
data AlertStatus
    = Active
    | Acknowledged
    | Resolved
    deriving (Show, Eq, Generic)

instance FromJSON AlertStatus
instance ToJSON AlertStatus

-- | Alert data structure
data Alert = Alert
    { alertId :: Text
    , alertTitle :: Text
    , alertMessage :: Text
    , alertSeverity :: AlertSeverity
    , alertStatus :: AlertStatus
    , alertSource :: Text
    , alertTimestamp :: UTCTime
    , alertAcknowledgedBy :: Maybe Text
    , alertAcknowledgedAt :: Maybe UTCTime
    , alertMetadata :: Maybe Value
    } deriving (Show, Eq, Generic)

instance FromJSON Alert
instance ToJSON Alert
instance FromRow Alert
instance ToRow Alert

-- | Alert threshold configuration
data AlertThreshold = AlertThreshold
    { metricName :: Text
    , warningThreshold :: Double
    , criticalThreshold :: Double
    , comparisonType :: Text  -- "gt" (>), "lt" (<), "eq" (==)
    , duration :: Int         -- Duration in seconds for the condition to persist
    } deriving (Show, Eq, Generic)

instance FromJSON AlertThreshold
instance ToJSON AlertThreshold

-- | Alert rule configuration
data AlertRule = AlertRule
    { ruleName :: Text
    , ruleDescription :: Text
    , ruleEnabled :: Bool
    , ruleThresholds :: [AlertThreshold]
    , ruleMetadata :: Maybe Value
    } deriving (Show, Eq, Generic)

instance FromJSON AlertRule
instance ToJSON AlertRule

-- | Get all active alerts
getActiveAlerts :: FilePath -> IO [Alert]
getActiveAlerts dbPath = runDB dbPath $ SQLiteM $ \conn ->
    query conn
        "SELECT * FROM alerts WHERE status = ? ORDER BY timestamp DESC"
        (Only Active)

-- | Acknowledge an alert
acknowledgeAlert :: FilePath -> Text -> Text -> IO Alert
acknowledgeAlert dbPath alertId' userId = do
    now <- getCurrentTime
    runDB dbPath $ SQLiteM $ \conn -> do
        execute conn
            "UPDATE alerts SET status = ?, acknowledged_by = ?, acknowledged_at = ? WHERE id = ?"
            (Acknowledged, userId, now, alertId')
        results <- query conn "SELECT * FROM alerts WHERE id = ?" (Only alertId')
        case results of
            [alert] -> return alert
            _ -> fail $ "Alert not found: " ++ Text.unpack alertId'

-- | Create a new alert
createAlert :: FilePath -> Text -> Text -> AlertSeverity -> Text -> Maybe Value -> IO Alert
createAlert dbPath title message severity source metadata = do
    now <- getCurrentTime
    let alertId' = generateAlertId now
    let alert = Alert
            { alertId = alertId'
            , alertTitle = title
            , alertMessage = message
            , alertSeverity = severity
            , alertStatus = Active
            , alertSource = source
            , alertTimestamp = now
            , alertAcknowledgedBy = Nothing
            , alertAcknowledgedAt = Nothing
            , alertMetadata = metadata
            }
    runDB dbPath $ SQLiteM $ \conn -> do
        execute conn
            "INSERT INTO alerts (id, title, message, severity, status, source, timestamp, metadata) \
            \VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            alert
        return alert

-- | Update alert status
updateAlertStatus :: FilePath -> Text -> AlertStatus -> IO Alert
updateAlertStatus dbPath alertId' newStatus = do
    now <- getCurrentTime
    runDB dbPath $ SQLiteM $ \conn -> do
        execute conn
            "UPDATE alerts SET status = ?, updated_at = ? WHERE id = ?"
            (newStatus, now, alertId')
        results <- query conn "SELECT * FROM alerts WHERE id = ?" (Only alertId')
        case results of
            [alert] -> return alert
            _ -> fail $ "Alert not found: " ++ Text.unpack alertId'

-- | Delete an alert
deleteAlert :: FilePath -> Text -> IO ()
deleteAlert dbPath alertId' =
    runDB dbPath $ SQLiteM $ \conn ->
        execute conn "DELETE FROM alerts WHERE id = ?" (Only alertId')

-- | Check metric thresholds and generate alerts
checkThresholds :: FilePath -> Metrics -> [AlertRule] -> IO [Alert]
checkThresholds dbPath metrics rules = do
    alerts <- concat <$> mapM (evaluateRule dbPath metrics) rules
    mapM_ (createAlert dbPath) alerts
    return alerts

-- | Evaluate metrics against alert rules
evaluateMetrics :: Metrics -> AlertRule -> IO [Alert]
evaluateMetrics metrics rule = do
    now <- getCurrentTime
    let alerts = concatMap (evaluateThreshold metrics now) (ruleThresholds rule)
    -- Only create alerts for new violations
    existingAlerts <- getActiveAlerts dbPath
    let existingIds = Set.fromList $ map alertId existingAlerts
    let newAlerts = filter (\a -> not $ Set.member (alertId a) existingIds) alerts
    mapM_ (createAlert dbPath) newAlerts
    return newAlerts

-- | Helper function to generate a unique alert ID
generateAlertId :: UTCTime -> Text
generateAlertId timestamp =
    "alert-" <> Text.pack (show timestamp)

-- | Helper function to evaluate a threshold
evaluateThreshold :: Metrics -> UTCTime -> AlertThreshold -> [Alert]
evaluateThreshold metrics now threshold =
    let value = getMetricValue metrics (metricName threshold)
        alerts = []
    in case value of
        Nothing -> []  -- Metric not found
        Just v ->
            -- Check critical threshold
            if checkThresholdViolation v (criticalThreshold threshold) (comparisonType threshold)
            then createThresholdAlert Critical v : alerts
            -- Check warning threshold
            else if checkThresholdViolation v (warningThreshold threshold) (comparisonType threshold)
            then createThresholdAlert Warning v : alerts
            else alerts
  where
    createThresholdAlert severity value = Alert
        { alertId = generateAlertId now
        , alertTitle = "Threshold Violation: " <> metricName threshold
        , alertMessage = formatAlertMessage severity value
        , alertSeverity = severity
        , alertStatus = Active
        , alertSource = "metrics"
        , alertTimestamp = now
        , alertAcknowledgedBy = Nothing
        , alertAcknowledgedAt = Nothing
        , alertMetadata = Just $ object
            [ "metric" .= metricName threshold
            , "value" .= value
            , "threshold" .= (if severity == Critical then criticalThreshold else warningThreshold) threshold
            , "comparison" .= comparisonType threshold
            ]
        }

    formatAlertMessage severity value = Text.unwords
        [ metricName threshold
        , "has exceeded"
        , Text.pack (show severity)
        , "threshold:"
        , Text.pack (show value)
        ]

-- | Helper function to check threshold violation
checkThresholdViolation :: Double -> Double -> Text -> Bool
checkThresholdViolation value threshold comparison =
    case comparison of
        "gt" -> value > threshold
        "lt" -> value < threshold
        "eq" -> value == threshold
        "gte" -> value >= threshold
        "lte" -> value <= threshold
        _ -> False

-- | Helper function to get metric value
getMetricValue :: Metrics -> Text -> Maybe Double
getMetricValue metrics name = case name of
    "requests_total" -> Just $ fromIntegral $ Counter.read $ requestsTotal metrics
    "request_duration" -> Just $ Gauge.read $ requestDuration metrics
    "active_connections" -> Just $ Gauge.read $ activeConnections metrics
    "response_size" -> Just $ Gauge.read $ responseSize metrics
    "errors_total" -> Just $ fromIntegral $ Counter.read $ errorsTotal metrics
    "rate_limit_exceeded" -> Just $ fromIntegral $ Counter.read $ rateLimitExceeded metrics
    "validation_errors" -> Just $ fromIntegral $ Counter.read $ validationErrors metrics
    "db_connections" -> Just $ Gauge.read $ dbConnections metrics
    "db_queries_total" -> Just $ fromIntegral $ Counter.read $ dbQueriesTotal metrics
    "db_query_duration" -> Just $ Gauge.read $ dbQueryDuration metrics
    "db_errors" -> Just $ fromIntegral $ Counter.read $ dbErrors metrics
    "git_operations_total" -> Just $ fromIntegral $ Counter.read $ gitOperationsTotal metrics
    "git_operation_errors" -> Just $ fromIntegral $ Counter.read $ gitOperationErrors metrics
    "cache_hits" -> Just $ fromIntegral $ Counter.read $ cacheHits metrics
    "cache_misses" -> Just $ fromIntegral $ Counter.read $ cacheMisses metrics
    "cache_size" -> Just $ Gauge.read $ cacheSize metrics
    _ -> Nothing

-- | Helper function to evaluate a rule
evaluateRule :: FilePath -> Metrics -> AlertRule -> IO [Alert]
evaluateRule dbPath metrics rule =
    if not (ruleEnabled rule)
    then return []
    else do
        now <- getCurrentTime
        let alerts = concatMap (evaluateThreshold metrics now) (ruleThresholds rule)
        -- Only create alerts for new violations
        existingAlerts <- getActiveAlerts dbPath
        let existingIds = Set.fromList $ map alertId existingAlerts
        let newAlerts = filter (\a -> not $ Set.member (alertId a) existingIds) alerts
        mapM_ (createAlert dbPath) newAlerts
        return newAlerts
