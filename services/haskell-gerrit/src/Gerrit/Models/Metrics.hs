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

module Gerrit.Models.Metrics
    ( -- * Types
      MetricType(..)
    , MetricCategory(..)
    , MetricValue(..)
    , MetricAggregation(..)
    , Metric(..)
    , MetricId
    , MetricSeries(..)
    , MetricSeriesId
    , MetricAlert(..)
    , MetricAlertId
    , MetricThreshold(..)
    , MetricThresholdId
      -- * Operations
    , recordMetric
    , getMetricById
    , listMetrics
    , createMetricSeries
    , updateMetricSeries
    , getMetricSeriesById
    , listMetricSeries
    , createMetricAlert
    , updateMetricAlert
    , getMetricAlertById
    , listMetricAlerts
    , setMetricThreshold
    , getMetricThreshold
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Metric type
data MetricType
    = Counter
    | Gauge
    | Histogram
    | Summary
    | Timer
    deriving (Show, Read, Eq, Generic)
derivePersistField "MetricType"

-- | Metric category
data MetricCategory
    = System
    | Application
    | Database
    | Network
    | User
    | Business
    | Custom Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "MetricCategory"

-- | Metric value
data MetricValue
    = IntValue Int
    | DoubleValue Double
    | TextValue Text
    | BoolValue Bool
    | JSONValue Value
    deriving (Show, Read, Eq, Generic)
derivePersistField "MetricValue"

-- | Metric aggregation
data MetricAggregation
    = Sum
    | Average
    | Min
    | Max
    | Count
    | Percentile Double
    | Custom Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "MetricAggregation"

-- | Define the metric entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Metric
    metricId Text
    name Text
    description Text
    category MetricCategory
    metricType MetricType
    value MetricValue
    tags Value
    metadata Value Maybe
    timestamp UTCTime
    created UTCTime
    UniqueMetricId metricId
    deriving Show Eq Generic

MetricSeries
    seriesId Text
    name Text
    description Text
    category MetricCategory
    metricType MetricType
    aggregation MetricAggregation
    interval Int  -- Interval in seconds
    retentionDays Int
    tags Value
    metadata Value Maybe
    isActive Bool
    created UTCTime
    updated UTCTime
    UniqueSeriesId seriesId
    UniqueSeriesName name
    deriving Show Eq Generic

MetricAlert
    alertId Text
    seriesId Text
    name Text
    description Text
    condition Text  -- SQL-like condition
    threshold MetricValue
    evaluationPeriod Int  -- Period in seconds
    cooldownPeriod Int  -- Period in seconds
    isActive Bool
    lastTriggered UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueAlertId alertId
    Foreign MetricSeries seriesId References metricSeries OnDeleteCascade
    deriving Show Eq Generic

MetricThreshold
    thresholdId Text
    seriesId Text
    warning MetricValue Maybe
    critical MetricValue Maybe
    action Text Maybe
    isActive Bool
    created UTCTime
    updated UTCTime
    UniqueThresholdId thresholdId
    UniqueSeriesThreshold seriesId
    Foreign MetricSeries seriesId References metricSeries OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Record a new metric
recordMetric :: MonadIO m
             => Text  -- ^ Name
             -> Text  -- ^ Description
             -> MetricCategory  -- ^ Category
             -> MetricType  -- ^ Metric type
             -> MetricValue  -- ^ Value
             -> Value  -- ^ Tags
             -> Maybe Value  -- ^ Additional metadata
             -> m (Entity Metric)
recordMetric name description category mType value tags metadata = do
    now <- liftIO getCurrentTime
    let metricId = generateMetricId name now
    let metric = Metric
            { metricMetricId = metricId
            , metricName = name
            , metricDescription = description
            , metricCategory = category
            , metricMetricType = mType
            , metricValue = value
            , metricTags = tags
            , metricMetadata = metadata
            , metricTimestamp = now
            , metricCreated = now
            }
    runDB $ insertEntity metric

-- | Get metric by ID
getMetricById :: MonadIO m
              => Text  -- ^ Metric ID
              -> m (Maybe (Entity Metric))
getMetricById metricId =
    runDB $ getBy $ UniqueMetricId metricId

-- | List metrics
listMetrics :: MonadIO m
            => Maybe MetricCategory  -- ^ Category filter
            -> Maybe MetricType  -- ^ Type filter
            -> UTCTime  -- ^ Start time
            -> UTCTime  -- ^ End time
            -> Int  -- ^ Offset
            -> Int  -- ^ Limit
            -> m [Entity Metric]
listMetrics mCategory mType start end offset limit = do
    let filters = catMaybes
            [ (MetricCategory ==.) <$> mCategory
            , (MetricMetricType ==.) <$> mType
            ] ++
            [ MetricTimestamp >=. start
            , MetricTimestamp <=. end
            ]
    runDB $ selectList filters [Desc MetricTimestamp, OffsetBy offset, LimitTo limit]

-- | Create a new metric series
createMetricSeries :: MonadIO m
                   => Text  -- ^ Name
                   -> Text  -- ^ Description
                   -> MetricCategory  -- ^ Category
                   -> MetricType  -- ^ Metric type
                   -> MetricAggregation  -- ^ Aggregation
                   -> Int  -- ^ Interval in seconds
                   -> Int  -- ^ Retention days
                   -> Value  -- ^ Tags
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity MetricSeries)
createMetricSeries name description category mType aggregation interval retention tags metadata = do
    now <- liftIO getCurrentTime
    let seriesId = generateSeriesId name now
    let series = MetricSeries
            { metricSeriesSeriesId = seriesId
            , metricSeriesName = name
            , metricSeriesDescription = description
            , metricSeriesCategory = category
            , metricSeriesMetricType = mType
            , metricSeriesAggregation = aggregation
            , metricSeriesInterval = interval
            , metricSeriesRetentionDays = retention
            , metricSeriesTags = tags
            , metricSeriesMetadata = metadata
            , metricSeriesIsActive = True
            , metricSeriesCreated = now
            , metricSeriesUpdated = now
            }
    runDB $ insertEntity series

-- | Update metric series
updateMetricSeries :: MonadIO m
                   => Entity MetricSeries
                   -> Text  -- ^ Name
                   -> Text  -- ^ Description
                   -> MetricCategory  -- ^ Category
                   -> MetricType  -- ^ Metric type
                   -> MetricAggregation  -- ^ Aggregation
                   -> Int  -- ^ Interval in seconds
                   -> Int  -- ^ Retention days
                   -> Value  -- ^ Tags
                   -> Maybe Value  -- ^ Additional metadata
                   -> Bool  -- ^ Is active
                   -> m (Entity MetricSeries)
updateMetricSeries (Entity key series) name description category mType aggregation interval retention tags metadata isActive = do
    now <- liftIO getCurrentTime
    let updatedSeries = series
            { metricSeriesName = name
            , metricSeriesDescription = description
            , metricSeriesCategory = category
            , metricSeriesMetricType = mType
            , metricSeriesAggregation = aggregation
            , metricSeriesInterval = interval
            , metricSeriesRetentionDays = retention
            , metricSeriesTags = tags
            , metricSeriesMetadata = metadata
            , metricSeriesIsActive = isActive
            , metricSeriesUpdated = now
            }
    runDB $ replace key updatedSeries
    return $ Entity key updatedSeries

-- | Get metric series by ID
getMetricSeriesById :: MonadIO m
                    => Text  -- ^ Series ID
                    -> m (Maybe (Entity MetricSeries))
getMetricSeriesById seriesId =
    runDB $ getBy $ UniqueSeriesId seriesId

-- | List metric series
listMetricSeries :: MonadIO m
                 => Maybe MetricCategory  -- ^ Category filter
                 -> Maybe MetricType  -- ^ Type filter
                 -> Bool  -- ^ Only active series
                 -> Int  -- ^ Offset
                 -> Int  -- ^ Limit
                 -> m [Entity MetricSeries]
listMetricSeries mCategory mType onlyActive offset limit = do
    let filters = catMaybes
            [ (MetricSeriesCategory ==.) <$> mCategory
            , (MetricSeriesMetricType ==.) <$> mType
            ] ++ [MetricSeriesIsActive ==. True | onlyActive]
    runDB $ selectList filters [Asc MetricSeriesName, OffsetBy offset, LimitTo limit]

-- | Create a new metric alert
createMetricAlert :: MonadIO m
                  => Text  -- ^ Series ID
                  -> Text  -- ^ Name
                  -> Text  -- ^ Description
                  -> Text  -- ^ Condition
                  -> MetricValue  -- ^ Threshold
                  -> Int  -- ^ Evaluation period in seconds
                  -> Int  -- ^ Cooldown period in seconds
                  -> m (Entity MetricAlert)
createMetricAlert seriesId name description condition threshold evalPeriod cooldownPeriod = do
    now <- liftIO getCurrentTime
    let alertId = generateAlertId name now
    let alert = MetricAlert
            { metricAlertAlertId = alertId
            , metricAlertSeriesId = seriesId
            , metricAlertName = name
            , metricAlertDescription = description
            , metricAlertCondition = condition
            , metricAlertThreshold = threshold
            , metricAlertEvaluationPeriod = evalPeriod
            , metricAlertCooldownPeriod = cooldownPeriod
            , metricAlertIsActive = True
            , metricAlertLastTriggered = Nothing
            , metricAlertCreated = now
            , metricAlertUpdated = now
            }
    runDB $ insertEntity alert

-- | Update metric alert
updateMetricAlert :: MonadIO m
                  => Entity MetricAlert
                  -> Text  -- ^ Name
                  -> Text  -- ^ Description
                  -> Text  -- ^ Condition
                  -> MetricValue  -- ^ Threshold
                  -> Int  -- ^ Evaluation period in seconds
                  -> Int  -- ^ Cooldown period in seconds
                  -> Bool  -- ^ Is active
                  -> m (Entity MetricAlert)
updateMetricAlert (Entity key alert) name description condition threshold evalPeriod cooldownPeriod isActive = do
    now <- liftIO getCurrentTime
    let updatedAlert = alert
            { metricAlertName = name
            , metricAlertDescription = description
            , metricAlertCondition = condition
            , metricAlertThreshold = threshold
            , metricAlertEvaluationPeriod = evalPeriod
            , metricAlertCooldownPeriod = cooldownPeriod
            , metricAlertIsActive = isActive
            , metricAlertUpdated = now
            }
    runDB $ replace key updatedAlert
    return $ Entity key updatedAlert

-- | Get metric alert by ID
getMetricAlertById :: MonadIO m
                   => Text  -- ^ Alert ID
                   -> m (Maybe (Entity MetricAlert))
getMetricAlertById alertId =
    runDB $ getBy $ UniqueAlertId alertId

-- | List metric alerts
listMetricAlerts :: MonadIO m
                 => Text  -- ^ Series ID
                 -> Bool  -- ^ Only active alerts
                 -> Int  -- ^ Offset
                 -> Int  -- ^ Limit
                 -> m [Entity MetricAlert]
listMetricAlerts seriesId onlyActive offset limit = do
    let filters = (MetricAlertSeriesId ==. seriesId) :
                 [MetricAlertIsActive ==. True | onlyActive]
    runDB $ selectList filters [Asc MetricAlertName, OffsetBy offset, LimitTo limit]

-- | Set metric threshold
setMetricThreshold :: MonadIO m
                   => Text  -- ^ Series ID
                   -> Maybe MetricValue  -- ^ Warning threshold
                   -> Maybe MetricValue  -- ^ Critical threshold
                   -> Maybe Text  -- ^ Action
                   -> m (Entity MetricThreshold)
setMetricThreshold seriesId warning critical action = do
    now <- liftIO getCurrentTime
    let thresholdId = generateThresholdId seriesId now
    let threshold = MetricThreshold
            { metricThresholdThresholdId = thresholdId
            , metricThresholdSeriesId = seriesId
            , metricThresholdWarning = warning
            , metricThresholdCritical = critical
            , metricThresholdAction = action
            , metricThresholdIsActive = True
            , metricThresholdCreated = now
            , metricThresholdUpdated = now
            }
    runDB $ insertBy threshold >>= \case
        Left (Entity key _) -> do
            update key
                [ MetricThresholdWarning =. warning
                , MetricThresholdCritical =. critical
                , MetricThresholdAction =. action
                , MetricThresholdUpdated =. now
                ]
            getEntity key
        Right entity -> return entity

-- | Get metric threshold
getMetricThreshold :: MonadIO m
                   => Text  -- ^ Series ID
                   -> m (Maybe (Entity MetricThreshold))
getMetricThreshold seriesId =
    runDB $ getBy $ UniqueSeriesThreshold seriesId

-- Helper functions for generating IDs
generateMetricId :: Text -> UTCTime -> Text
generateMetricId name timestamp =
    "metric_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateSeriesId :: Text -> UTCTime -> Text
generateSeriesId name timestamp =
    "series_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateAlertId :: Text -> UTCTime -> Text
generateAlertId name timestamp =
    "alert_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateThresholdId :: Text -> UTCTime -> Text
generateThresholdId seriesId timestamp =
    "threshold_" <> Text.filter isAllowed seriesId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
