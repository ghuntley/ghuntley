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

module Gerrit.Models.PerformanceMetrics where

import Data.Aeson
import Data.Text (Text)
import Data.Time
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

-- | Performance metric types
data MetricType = QueryMetric | ConnectionMetric | CacheMetric | ResourceMetric
    deriving (Show, Eq, Generic)

instance ToJSON MetricType
instance FromJSON MetricType

-- | Resource types for performance metrics
data ResourceType = CPU | Memory | DiskIO | NetworkIO
    deriving (Show, Eq, Generic)

instance ToJSON ResourceType
instance FromJSON ResourceType

-- | Cache types for performance metrics
data CacheType = ConnectionCache | StatementCache | ResultCache | MetadataCache
    deriving (Show, Eq, Generic)

instance ToJSON CacheType
instance FromJSON CacheType

-- | Persistent models for performance metrics
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
DatabaseMetric
    metricId Text
    queryName Text Maybe
    executionTime NominalDiffTime
    rowsAffected Int
    timestamp UTCTime
    details Value Maybe
    UniqueDatabaseMetricId metricId
    deriving Show Eq Generic

ConnectionMetric
    metricId Text
    poolSize Int
    activeConnections Int
    idleConnections Int
    waitTime NominalDiffTime
    timestamp UTCTime
    details Value Maybe
    UniqueConnectionMetricId metricId
    deriving Show Eq Generic

CacheMetric
    metricId Text
    cacheType CacheType
    hitCount Int
    missCount Int
    size Int
    evictionCount Int
    timestamp UTCTime
    details Value Maybe
    UniqueCacheMetricId metricId
    deriving Show Eq Generic

ResourceMetric
    metricId Text
    resourceType ResourceType
    utilization Double
    available Double
    timestamp UTCTime
    details Value Maybe
    UniqueResourceMetricId metricId
    deriving Show Eq Generic

PerformanceAlert
    alertId Text
    metricType MetricType
    threshold Double
    actualValue Double
    message Text
    timestamp UTCTime
    acknowledged Bool
    acknowledgedBy Text Maybe
    acknowledgedAt UTCTime Maybe
    UniquePerformanceAlertId alertId
    deriving Show Eq Generic
|]

-- | Helper functions for recording performance metrics
recordDatabaseMetric :: MonadIO m
                    => Maybe Text  -- ^ Query name
                    -> NominalDiffTime  -- ^ Execution time
                    -> Int  -- ^ Rows affected
                    -> Maybe Value  -- ^ Additional details
                    -> m (Either Text ())
recordDatabaseMetric queryName execTime rowsAffected details = do
    metricId <- generateMetricId
    now <- getCurrentTime
    runDB $ insert_ DatabaseMetric
        { databaseMetricMetricId = metricId
        , databaseMetricQueryName = queryName
        , databaseMetricExecutionTime = execTime
        , databaseMetricRowsAffected = rowsAffected
        , databaseMetricTimestamp = now
        , databaseMetricDetails = details
        }
    return $ Right ()
  where
    generateMetricId = undefined -- Replace with actual ID generation in implementation

recordConnectionMetric :: MonadIO m
                      => Int  -- ^ Pool size
                      -> Int  -- ^ Active connections
                      -> Int  -- ^ Idle connections
                      -> NominalDiffTime  -- ^ Wait time
                      -> Maybe Value  -- ^ Additional details
                      -> m (Either Text ())
recordConnectionMetric poolSize active idle waitTime details = do
    metricId <- generateMetricId
    now <- getCurrentTime
    runDB $ insert_ ConnectionMetric
        { connectionMetricMetricId = metricId
        , connectionMetricPoolSize = poolSize
        , connectionMetricActiveConnections = active
        , connectionMetricIdleConnections = idle
        , connectionMetricWaitTime = waitTime
        , connectionMetricTimestamp = now
        , connectionMetricDetails = details
        }
    return $ Right ()
  where
    generateMetricId = undefined -- Replace with actual ID generation in implementation

recordCacheMetric :: MonadIO m
                  => CacheType  -- ^ Cache type
                  -> Int  -- ^ Hit count
                  -> Int  -- ^ Miss count
                  -> Int  -- ^ Cache size
                  -> Int  -- ^ Eviction count
                  -> Maybe Value  -- ^ Additional details
                  -> m (Either Text ())
recordCacheMetric cacheType hits misses size evictions details = do
    metricId <- generateMetricId
    now <- getCurrentTime
    runDB $ insert_ CacheMetric
        { cacheMetricMetricId = metricId
        , cacheMetricCacheType = cacheType
        , cacheMetricHitCount = hits
        , cacheMetricMissCount = misses
        , cacheMetricSize = size
        , cacheMetricEvictionCount = evictions
        , cacheMetricTimestamp = now
        , cacheMetricDetails = details
        }
    return $ Right ()
  where
    generateMetricId = undefined -- Replace with actual ID generation in implementation

recordResourceMetric :: MonadIO m
                    => ResourceType  -- ^ Resource type
                    -> Double  -- ^ Utilization percentage
                    -> Double  -- ^ Available amount
                    -> Maybe Value  -- ^ Additional details
                    -> m (Either Text ())
recordResourceMetric resourceType utilization available details = do
    metricId <- generateMetricId
    now <- getCurrentTime
    runDB $ insert_ ResourceMetric
        { resourceMetricMetricId = metricId
        , resourceMetricResourceType = resourceType
        , resourceMetricUtilization = utilization
        , resourceMetricAvailable = available
        , resourceMetricTimestamp = now
        , resourceMetricDetails = details
        }
    return $ Right ()
  where
    generateMetricId = undefined -- Replace with actual ID generation in implementation

recordPerformanceAlert :: MonadIO m
                      => MetricType  -- ^ Metric type
                      -> Double  -- ^ Threshold value
                      -> Double  -- ^ Actual value
                      -> Text  -- ^ Alert message
                      -> m (Either Text ())
recordPerformanceAlert metricType threshold actual message = do
    alertId <- generateAlertId
    now <- getCurrentTime
    runDB $ insert_ PerformanceAlert
        { performanceAlertAlertId = alertId
        , performanceAlertMetricType = metricType
        , performanceAlertThreshold = threshold
        , performanceAlertActualValue = actual
        , performanceAlertMessage = message
        , performanceAlertTimestamp = now
        , performanceAlertAcknowledged = False
        , performanceAlertAcknowledgedBy = Nothing
        , performanceAlertAcknowledgedAt = Nothing
        }
    return $ Right ()
  where
    generateAlertId = undefined -- Replace with actual ID generation in implementation

-- | Helper functions for retrieving performance metrics
getDatabaseMetrics :: MonadIO m
                   => UTCTime  -- ^ Start time
                   -> UTCTime  -- ^ End time
                   -> Maybe Text  -- ^ Query name filter
                   -> m [Entity DatabaseMetric]
getDatabaseMetrics start end queryName =
    runDB $ selectList
        ([ DatabaseMetricTimestamp >=. start
         , DatabaseMetricTimestamp <=. end
         ] ++ maybe [] (\q -> [DatabaseMetricQueryName ==. Just q]) queryName)
        [Desc DatabaseMetricTimestamp]

getConnectionMetrics :: MonadIO m
                     => UTCTime  -- ^ Start time
                     -> UTCTime  -- ^ End time
                     -> m [Entity ConnectionMetric]
getConnectionMetrics start end =
    runDB $ selectList
        [ ConnectionMetricTimestamp >=. start
        , ConnectionMetricTimestamp <=. end
        ]
        [Desc ConnectionMetricTimestamp]

getCacheMetrics :: MonadIO m
                => UTCTime  -- ^ Start time
                -> UTCTime  -- ^ End time
                -> Maybe CacheType  -- ^ Cache type filter
                -> m [Entity CacheMetric]
getCacheMetrics start end cacheType =
    runDB $ selectList
        ([ CacheMetricTimestamp >=. start
         , CacheMetricTimestamp <=. end
         ] ++ maybe [] (\ct -> [CacheMetricCacheType ==. ct]) cacheType)
        [Desc CacheMetricTimestamp]

getResourceMetrics :: MonadIO m
                   => UTCTime  -- ^ Start time
                   -> UTCTime  -- ^ End time
                   -> Maybe ResourceType  -- ^ Resource type filter
                   -> m [Entity ResourceMetric]
getResourceMetrics start end resourceType =
    runDB $ selectList
        ([ ResourceMetricTimestamp >=. start
         , ResourceMetricTimestamp <=. end
         ] ++ maybe [] (\rt -> [ResourceMetricResourceType ==. rt]) resourceType)
        [Desc ResourceMetricTimestamp]

getPerformanceAlerts :: MonadIO m
                     => UTCTime  -- ^ Start time
                     -> UTCTime  -- ^ End time
                     -> Bool  -- ^ Include acknowledged alerts
                     -> m [Entity PerformanceAlert]
getPerformanceAlerts start end includeAcknowledged =
    runDB $ selectList
        ([ PerformanceAlertTimestamp >=. start
         , PerformanceAlertTimestamp <=. end
         ] ++ if includeAcknowledged then [] else [PerformanceAlertAcknowledged ==. False])
        [Desc PerformanceAlertTimestamp]
