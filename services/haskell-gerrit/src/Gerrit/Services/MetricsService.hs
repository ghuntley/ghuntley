-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.MetricsService
    ( -- * Types
      MetricsService(..)
    , MetricsConfig(..)
      -- * Service
    , initMetricsService
    , startMetricsService
    , stopMetricsService
      -- * Metrics Operations
    , collectMetrics
    , evaluateMetrics
    , getCurrentMetrics
    ) where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Monad (forever, void)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist.Sql (ConnectionPool)

import Gerrit.Models.Metrics
import Gerrit.Models.PerformanceMetrics
import Gerrit.Models.ResourceQuota

-- | Metrics service configuration
data MetricsConfig = MetricsConfig
    { metricsCollectionInterval :: Int  -- ^ Interval in seconds between metric collections
    , metricsRetentionDays :: Int      -- ^ Number of days to retain metrics
    , metricsBatchSize :: Int          -- ^ Maximum number of metrics to process in one batch
    }

-- | Metrics service state
data MetricsService = MetricsService
    { metricsConfig :: MetricsConfig
    , metricsPool :: ConnectionPool
    , metricsThread :: Maybe ThreadId
    }

-- | Initialize the metrics service
initMetricsService :: ConnectionPool -> MetricsConfig -> IO MetricsService
initMetricsService pool config = do
    return MetricsService
        { metricsConfig = config
        , metricsPool = pool
        , metricsThread = Nothing
        }

-- | Start the metrics service
startMetricsService :: MetricsService -> IO MetricsService
startMetricsService service = do
    threadId <- forkIO $ metricsServiceLoop service
    return service { metricsThread = Just threadId }

-- | Stop the metrics service
stopMetricsService :: MetricsService -> IO ()
stopMetricsService MetricsService{..} =
    mapM_ killThread metricsThread

-- | Main metrics service loop
metricsServiceLoop :: MetricsService -> IO ()
metricsServiceLoop service@MetricsService{..} = forever $ do
    -- Collect metrics
    void $ collectMetrics service

    -- Clean up old metrics
    void $ cleanupOldMetrics service

    -- Wait for next collection interval
    threadDelay $ metricsCollectionInterval metricsConfig * 1000000

-- | Collect current system metrics
collectMetrics :: MonadIO m => MetricsService -> m Metrics
collectMetrics MetricsService{..} = do
    now <- liftIO getCurrentTime

    -- Collect various metrics
    systemMetrics <- collectSystemMetrics
    resourceMetrics <- collectResourceMetrics
    performanceMetrics <- collectPerformanceMetrics

    -- Store metrics
    void $ storeMetrics systemMetrics resourceMetrics performanceMetrics

    return $ combineMetrics systemMetrics resourceMetrics performanceMetrics

-- | Get current metrics
getCurrentMetrics :: MonadIO m => MetricsService -> m Metrics
getCurrentMetrics = collectMetrics

-- | Evaluate metrics against thresholds
evaluateMetrics :: MonadIO m => MetricsService -> m [(Text, Bool, Double)]
evaluateMetrics service = do
    metrics <- collectMetrics service
    return
        [ ("cpu_usage", checkThreshold (cpuUsage metrics) 80, cpuUsage metrics)
        , ("memory_usage", checkThreshold (memoryUsage metrics) 85, memoryUsage metrics)
        , ("disk_usage", checkThreshold (diskUsage metrics) 90, diskUsage metrics)
        , ("request_latency", checkLatencyThreshold (requestLatency metrics), requestLatency metrics)
        , ("error_rate", checkErrorRateThreshold (errorRate metrics), errorRate metrics)
        ]

-- | Clean up old metrics
cleanupOldMetrics :: MonadIO m => MetricsService -> m ()
cleanupOldMetrics MetricsService{..} = do
    now <- liftIO getCurrentTime
    let cutoff = addUTCTime (fromIntegral $ -86400 * metricsRetentionDays metricsConfig) now

    -- Delete old metrics
    void $ deleteOldMetrics cutoff

-- | Helper function to collect system metrics
collectSystemMetrics :: MonadIO m => m SystemMetrics
collectSystemMetrics = do
    -- Collect CPU metrics
    cpuUsage <- getCPUUsage
    cpuLoad <- getSystemLoad

    -- Collect memory metrics
    memTotal <- getTotalMemory
    memUsed <- getUsedMemory
    memFree <- getFreeMemory

    -- Collect disk metrics
    diskTotal <- getTotalDiskSpace
    diskUsed <- getUsedDiskSpace
    diskFree <- getFreeDiskSpace

    return SystemMetrics
        { systemMetricsCPUUsage = cpuUsage
        , systemMetricsCPULoad = cpuLoad
        , systemMetricsMemoryTotal = memTotal
        , systemMetricsMemoryUsed = memUsed
        , systemMetricsMemoryFree = memFree
        , systemMetricsDiskTotal = diskTotal
        , systemMetricsDiskUsed = diskUsed
        , systemMetricsDiskFree = diskFree
        }

-- | Helper function to collect resource metrics
collectResourceMetrics :: MonadIO m => m ResourceMetrics
collectResourceMetrics = do
    -- Collect connection metrics
    dbConns <- getDBConnections
    activeConns <- getActiveConnections

    -- Collect request metrics
    reqCount <- getRequestCount
    reqLatency <- getRequestLatency

    -- Collect error metrics
    errorCount <- getErrorCount
    errorRate <- calculateErrorRate reqCount errorCount

    return ResourceMetrics
        { resourceMetricsDBConnections = dbConns
        , resourceMetricsActiveConnections = activeConns
        , resourceMetricsRequestCount = reqCount
        , resourceMetricsRequestLatency = reqLatency
        , resourceMetricsErrorCount = errorCount
        , resourceMetricsErrorRate = errorRate
        }

-- | Helper function to collect performance metrics
collectPerformanceMetrics :: MonadIO m => m PerformanceMetrics
collectPerformanceMetrics = do
    -- Collect API metrics
    apiLatency <- getAPILatency
    apiThroughput <- getAPIThroughput

    -- Collect database metrics
    dbLatency <- getDBLatency
    dbThroughput <- getDBThroughput

    -- Collect cache metrics
    cacheHitRate <- getCacheHitRate
    cacheMissRate <- getCacheMissRate

    return PerformanceMetrics
        { performanceMetricsAPILatency = apiLatency
        , performanceMetricsAPIThroughput = apiThroughput
        , performanceMetricsDBLatency = dbLatency
        , performanceMetricsDBThroughput = dbThroughput
        , performanceMetricsCacheHitRate = cacheHitRate
        , performanceMetricsCacheMissRate = cacheMissRate
        }

-- | Helper function to store metrics
storeMetrics :: MonadIO m
             => SystemMetrics
             -> ResourceMetrics
             -> PerformanceMetrics
             -> m ()
storeMetrics system resource performance = do
    now <- liftIO getCurrentTime

    -- Store system metrics
    void $ recordSystemMetrics system

    -- Store resource metrics
    void $ recordResourceMetrics resource

    -- Store performance metrics
    void $ recordPerformanceMetrics performance

-- | Helper function to combine metrics
combineMetrics :: SystemMetrics -> ResourceMetrics -> PerformanceMetrics -> Metrics
combineMetrics system resource performance =
    Metrics
        { metricsTimestamp = getCurrentTime
        , metricsSystem = system
        , metricsResource = resource
        , metricsPerformance = performance
        }

-- | Helper functions to check thresholds
checkThreshold :: Double -> Double -> Bool
checkThreshold value threshold = value > threshold

checkLatencyThreshold :: Double -> Bool
checkLatencyThreshold latency = latency > 1000  -- 1 second

checkErrorRateThreshold :: Double -> Bool
checkErrorRateThreshold rate = rate > 0.05  -- 5% error rate
