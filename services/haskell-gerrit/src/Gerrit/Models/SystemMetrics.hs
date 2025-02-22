-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Models.SystemMetrics
    ( -- * Types
      RequestMetric(..)
    , RequestMetricId
    , ResourceMetric(..)
    , ResourceMetricId
    , PerformanceMetric(..)
    , PerformanceMetricId
    , MetricType(..)
    , MetricValue(..)
      -- * Operations
    , recordRequestMetric
    , recordResourceMetric
    , recordPerformanceMetric
    , getRequestMetrics
    , getResourceMetrics
    , getPerformanceMetrics
    , aggregateMetrics
    , calculateTrends
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Metric types
data MetricType
    = Counter    -- ^ Monotonically increasing counter
    | Gauge      -- ^ Value that can go up and down
    | Histogram  -- ^ Distribution of values
    | Summary    -- ^ Statistical summary (count, sum, etc.)
    deriving (Show, Read, Eq, Generic)
derivePersistField "MetricType"

-- | Metric value with metadata
data MetricValue = MetricValue
    { value :: Double
    , labels :: Value
    , metadata :: Value
    } deriving (Show, Eq, Generic)
derivePersistField "MetricValue"

-- | Define the system metrics entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
RequestMetric
    metricId Text
    method Text
    path Text
    status Int
    duration Int  -- in milliseconds
    responseSize Int64
    clientInfo Value
    metricType MetricType
    metricValue MetricValue
    timestamp UTCTime
    UniqueRequestMetricId metricId
    deriving Show Eq Generic

ResourceMetric
    metricId Text
    resourceType ResourceType
    resourceId Text
    operation Text
    usageValue Int64
    metricType MetricType
    metricValue MetricValue
    timestamp UTCTime
    UniqueResourceMetricId metricId
    deriving Show Eq Generic

PerformanceMetric
    metricId Text
    component Text
    metric Text
    value Double
    threshold Double Maybe
    metricType MetricType
    metricValue MetricValue
    timestamp UTCTime
    UniquePerformanceMetricId metricId
    deriving Show Eq Generic
|]

-- | Record a request metric
recordRequestMetric :: MonadIO m
                   => ConnectionPool
                   -> Text  -- ^ Method
                   -> Text  -- ^ Path
                   -> Int   -- ^ Status
                   -> Int   -- ^ Duration
                   -> Int64 -- ^ Response size
                   -> Value -- ^ Client info
                   -> m (Entity RequestMetric)
recordRequestMetric pool method path status duration size clientInfo = do
    now <- liftIO getCurrentTime
    let metricId = generateMetricId "request" method path now
    let metricValue = MetricValue
            { value = fromIntegral duration
            , labels = object
                [ "method" .= method
                , "path" .= path
                , "status" .= status
                ]
            , metadata = clientInfo
            }
    let metric = RequestMetric
            { requestMetricMetricId = metricId
            , requestMetricMethod = method
            , requestMetricPath = path
            , requestMetricStatus = status
            , requestMetricDuration = duration
            , requestMetricResponseSize = size
            , requestMetricClientInfo = clientInfo
            , requestMetricMetricType = Histogram
            , requestMetricMetricValue = metricValue
            , requestMetricTimestamp = now
            }
    runSqlPool (insertEntity metric) pool

-- | Record a resource metric
recordResourceMetric :: MonadIO m
                    => ConnectionPool
                    -> ResourceType
                    -> Text  -- ^ Resource ID
                    -> Text  -- ^ Operation
                    -> Int64 -- ^ Usage value
                    -> m (Entity ResourceMetric)
recordResourceMetric pool resourceType resourceId operation usageValue = do
    now <- liftIO getCurrentTime
    let metricId = generateMetricId "resource" (Text.pack $ show resourceType) resourceId now
    let metricValue = MetricValue
            { value = fromIntegral usageValue
            , labels = object
                [ "resource_type" .= show resourceType
                , "operation" .= operation
                ]
            , metadata = object []
            }
    let metric = ResourceMetric
            { resourceMetricMetricId = metricId
            , resourceMetricResourceType = resourceType
            , resourceMetricResourceId = resourceId
            , resourceMetricOperation = operation
            , resourceMetricUsageValue = usageValue
            , resourceMetricMetricType = Counter
            , resourceMetricMetricValue = metricValue
            , resourceMetricTimestamp = now
            }
    runSqlPool (insertEntity metric) pool

-- | Record a performance metric
recordPerformanceMetric :: MonadIO m
                       => ConnectionPool
                       -> Text  -- ^ Component
                       -> Text  -- ^ Metric name
                       -> Double -- ^ Value
                       -> Maybe Double -- ^ Threshold
                       -> m (Entity PerformanceMetric)
recordPerformanceMetric pool component metric value threshold = do
    now <- liftIO getCurrentTime
    let metricId = generateMetricId "performance" component metric now
    let metricValue = MetricValue
            { value = value
            , labels = object
                [ "component" .= component
                , "metric" .= metric
                ]
            , metadata = object []
            }
    let perfMetric = PerformanceMetric
            { performanceMetricMetricId = metricId
            , performanceMetricComponent = component
            , performanceMetricMetric = metric
            , performanceMetricValue = value
            , performanceMetricThreshold = threshold
            , performanceMetricMetricType = Gauge
            , performanceMetricMetricValue = metricValue
            , performanceMetricTimestamp = now
            }
    runSqlPool (insertEntity perfMetric) pool

-- | Get request metrics with filtering
getRequestMetrics :: MonadIO m
                 => ConnectionPool
                 -> Maybe Text  -- ^ Method filter
                 -> Maybe Text  -- ^ Path filter
                 -> Maybe Int   -- ^ Status filter
                 -> UTCTime     -- ^ Start time
                 -> UTCTime     -- ^ End time
                 -> Int         -- ^ Limit
                 -> m [Entity RequestMetric]
getRequestMetrics pool mMethod mPath mStatus start end limit = do
    let filters = concat
            [ maybe [] (\m -> [RequestMetricMethod ==. m]) mMethod
            , maybe [] (\p -> [RequestMetricPath ==. p]) mPath
            , maybe [] (\s -> [RequestMetricStatus ==. s]) mStatus
            , [RequestMetricTimestamp >=. start]
            , [RequestMetricTimestamp <=. end]
            ]
    runSqlPool (selectList filters [Desc RequestMetricTimestamp, LimitTo limit]) pool

-- | Get resource metrics with filtering
getResourceMetrics :: MonadIO m
                  => ConnectionPool
                  -> Maybe ResourceType
                  -> Maybe Text  -- ^ Resource ID
                  -> Maybe Text  -- ^ Operation
                  -> UTCTime     -- ^ Start time
                  -> UTCTime     -- ^ End time
                  -> Int         -- ^ Limit
                  -> m [Entity ResourceMetric]
getResourceMetrics pool mType mId mOp start end limit = do
    let filters = concat
            [ maybe [] (\t -> [ResourceMetricResourceType ==. t]) mType
            , maybe [] (\i -> [ResourceMetricResourceId ==. i]) mId
            , maybe [] (\o -> [ResourceMetricOperation ==. o]) mOp
            , [ResourceMetricTimestamp >=. start]
            , [ResourceMetricTimestamp <=. end]
            ]
    runSqlPool (selectList filters [Desc ResourceMetricTimestamp, LimitTo limit]) pool

-- | Get performance metrics with filtering
getPerformanceMetrics :: MonadIO m
                     => ConnectionPool
                     -> Maybe Text  -- ^ Component filter
                     -> Maybe Text  -- ^ Metric filter
                     -> UTCTime     -- ^ Start time
                     -> UTCTime     -- ^ End time
                     -> Int         -- ^ Limit
                     -> m [Entity PerformanceMetric]
getPerformanceMetrics pool mComponent mMetric start end limit = do
    let filters = concat
            [ maybe [] (\c -> [PerformanceMetricComponent ==. c]) mComponent
            , maybe [] (\m -> [PerformanceMetricMetric ==. m]) mMetric
            , [PerformanceMetricTimestamp >=. start]
            , [PerformanceMetricTimestamp <=. end]
            ]
    runSqlPool (selectList filters [Desc PerformanceMetricTimestamp, LimitTo limit]) pool

-- | Aggregate metrics by time window
aggregateMetrics :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Metric type
                -> UTCTime  -- ^ Start time
                -> UTCTime  -- ^ End time
                -> Text  -- ^ Aggregation function (sum, avg, min, max)
                -> m [(UTCTime, Double)]
aggregateMetrics pool metricType start end aggFunc = do
    -- Implementation would use raw SQL for efficient time-based aggregation
    -- This is a placeholder that would need to be implemented based on specific DB
    return []

-- | Calculate metric trends
calculateTrends :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Metric type
                -> UTCTime  -- ^ Start time
                -> UTCTime  -- ^ End time
                -> m [(UTCTime, Double, Double)]  -- (time, value, trend)
calculateTrends pool metricType start end = do
    -- Implementation would use statistical analysis for trend calculation
    -- This is a placeholder that would need to be implemented based on requirements
    return []

-- Helper functions for generating IDs
generateMetricId :: Text -> Text -> Text -> UTCTime -> Text
generateMetricId prefix component metric timestamp =
    prefix <> "_" <> Text.filter isAllowed (component <> "_" <> metric) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
