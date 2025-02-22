-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

module Gerrit.Services.EnterpriseMetrics
    ( -- * Types
      EnterpriseMetrics(..)
    , EnterpriseMetricsConfig(..)
      -- * Service
    , initEnterpriseMetrics
    , startEnterpriseMetrics
    , stopEnterpriseMetrics
      -- * Metrics Operations
    , recordApiUsage
    , recordResourceUsage
    , recordFeatureUsage
    , getEnterpriseMetrics
    , analyzeUsagePatterns
    , generateMetricsReport
    ) where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Monad (forever, void)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist.Sql (ConnectionPool)

import Gerrit.Models.Enterprise
import Gerrit.Models.Types
import Gerrit.VCS.Notification (NotificationSystem)

-- | Enterprise metrics configuration
data EnterpriseMetricsConfig = EnterpriseMetricsConfig
    { metricsCollectionInterval :: Int  -- ^ Interval in seconds between metrics collection
    , metricsRetentionDays :: Int      -- ^ Number of days to retain metrics
    , metricsBatchSize :: Int          -- ^ Maximum number of metrics to process in one batch
    }

-- | Enterprise metrics service state
data EnterpriseMetrics = EnterpriseMetrics
    { metricsConfig :: EnterpriseMetricsConfig
    , metricsPool :: ConnectionPool
    , metricsNotifier :: NotificationSystem
    , metricsThread :: Maybe ThreadId
    }

-- | Initialize the enterprise metrics service
initEnterpriseMetrics :: ConnectionPool -> NotificationSystem -> EnterpriseMetricsConfig -> IO EnterpriseMetrics
initEnterpriseMetrics pool notifier config = do
    return EnterpriseMetrics
        { metricsConfig = config
        , metricsPool = pool
        , metricsNotifier = notifier
        , metricsThread = Nothing
        }

-- | Start the enterprise metrics service
startEnterpriseMetrics :: EnterpriseMetrics -> IO EnterpriseMetrics
startEnterpriseMetrics metrics = do
    threadId <- forkIO $ metricsServiceLoop metrics
    return metrics { metricsThread = Just threadId }

-- | Stop the enterprise metrics service
stopEnterpriseMetrics :: EnterpriseMetrics -> IO ()
stopEnterpriseMetrics EnterpriseMetrics{..} =
    mapM_ killThread metricsThread

-- | Main metrics service loop
metricsServiceLoop :: EnterpriseMetrics -> IO ()
metricsServiceLoop metrics@EnterpriseMetrics{..} = forever $ do
    -- Collect metrics
    void $ collectEnterpriseMetrics metrics

    -- Clean up old metrics
    void $ cleanupOldMetrics metrics

    -- Wait for next collection interval
    threadDelay $ metricsCollectionInterval metricsConfig * 1000000

-- | Record API usage for an enterprise
recordApiUsage :: MonadIO m
               => EnterpriseMetrics
               -> Text  -- ^ Enterprise ID
               -> Text  -- ^ API endpoint
               -> Int   -- ^ Response time (ms)
               -> Bool  -- ^ Success status
               -> Value  -- ^ Additional metadata
               -> m ()
recordApiUsage EnterpriseMetrics{..} enterpriseId endpoint responseTime success metadata = do
    now <- liftIO getCurrentTime
    void $ runDB $ insert EnterpriseApiMetric
        { enterpriseApiMetricEnterpriseId = enterpriseId
        , enterpriseApiMetricEndpoint = endpoint
        , enterpriseApiMetricResponseTime = responseTime
        , enterpriseApiMetricSuccess = success
        , enterpriseApiMetricMetadata = metadata
        , enterpriseApiMetricTimestamp = now
        }

-- | Record resource usage for an enterprise
recordResourceUsage :: MonadIO m
                   => EnterpriseMetrics
                   -> Text  -- ^ Enterprise ID
                   -> Text  -- ^ Resource type
                   -> Int64  -- ^ Usage amount
                   -> Value  -- ^ Usage details
                   -> m ()
recordResourceUsage EnterpriseMetrics{..} enterpriseId resourceType amount details = do
    now <- liftIO getCurrentTime
    void $ runDB $ insert EnterpriseResourceMetric
        { enterpriseResourceMetricEnterpriseId = enterpriseId
        , enterpriseResourceMetricResourceType = resourceType
        , enterpriseResourceMetricAmount = amount
        , enterpriseResourceMetricDetails = details
        , enterpriseResourceMetricTimestamp = now
        }

-- | Record feature usage for an enterprise
recordFeatureUsage :: MonadIO m
                   => EnterpriseMetrics
                   -> Text  -- ^ Enterprise ID
                   -> Text  -- ^ Feature name
                   -> Value  -- ^ Usage details
                   -> m ()
recordFeatureUsage EnterpriseMetrics{..} enterpriseId feature details = do
    now <- liftIO getCurrentTime
    void $ runDB $ insert EnterpriseFeatureMetric
        { enterpriseFeatureMetricEnterpriseId = enterpriseId
        , enterpriseFeatureMetricFeature = feature
        , enterpriseFeatureMetricDetails = details
        , enterpriseFeatureMetricTimestamp = now
        }

-- | Get enterprise metrics for a specific time period
getEnterpriseMetrics :: MonadIO m
                     => EnterpriseMetrics
                     -> Text  -- ^ Enterprise ID
                     -> UTCTime  -- ^ Start time
                     -> UTCTime  -- ^ End time
                     -> m Value
getEnterpriseMetrics EnterpriseMetrics{..} enterpriseId start end = do
    -- Get API metrics
    apiMetrics <- runDB $ selectList
        [ EnterpriseApiMetricEnterpriseId ==. enterpriseId
        , EnterpriseApiMetricTimestamp >=. start
        , EnterpriseApiMetricTimestamp <=. end
        ]
        [Asc EnterpriseApiMetricTimestamp]

    -- Get resource metrics
    resourceMetrics <- runDB $ selectList
        [ EnterpriseResourceMetricEnterpriseId ==. enterpriseId
        , EnterpriseResourceMetricTimestamp >=. start
        , EnterpriseResourceMetricTimestamp <=. end
        ]
        [Asc EnterpriseResourceMetricTimestamp]

    -- Get feature metrics
    featureMetrics <- runDB $ selectList
        [ EnterpriseFeatureMetricEnterpriseId ==. enterpriseId
        , EnterpriseFeatureMetricTimestamp >=. start
        , EnterpriseFeatureMetricTimestamp <=. end
        ]
        [Asc EnterpriseFeatureMetricTimestamp]

    -- Analyze and return metrics
    return $ object
        [ "api_metrics" .= apiMetrics
        , "resource_metrics" .= resourceMetrics
        , "feature_metrics" .= featureMetrics
        ]

-- | Analyze usage patterns for an enterprise
analyzeUsagePatterns :: MonadIO m
                     => EnterpriseMetrics
                     -> Text  -- ^ Enterprise ID
                     -> UTCTime  -- ^ Analysis start time
                     -> UTCTime  -- ^ Analysis end time
                     -> m Value
analyzeUsagePatterns metrics enterpriseId start end = do
    -- Get metrics for the period
    rawMetrics <- getEnterpriseMetrics metrics enterpriseId start end

    -- Analyze patterns (implement your analysis logic here)
    return $ object
        [ "analysis_period" .= object
            [ "start" .= start
            , "end" .= end
            ]
        , "raw_metrics" .= rawMetrics
        -- Add more analysis results here
        ]

-- | Generate a metrics report for an enterprise
generateMetricsReport :: MonadIO m
                      => EnterpriseMetrics
                      -> Text  -- ^ Enterprise ID
                      -> UTCTime  -- ^ Report start time
                      -> UTCTime  -- ^ Report end time
                      -> m Value
generateMetricsReport metrics enterpriseId start end = do
    -- Get usage patterns
    patterns <- analyzeUsagePatterns metrics enterpriseId start end

    -- Generate report
    return $ object
        [ "enterprise_id" .= enterpriseId
        , "report_period" .= object
            [ "start" .= start
            , "end" .= end
            ]
        , "usage_patterns" .= patterns
        -- Add more report sections here
        ]

-- | Helper function to collect enterprise metrics
collectEnterpriseMetrics :: MonadIO m => EnterpriseMetrics -> m ()
collectEnterpriseMetrics metrics@EnterpriseMetrics{..} = do
    -- Get all active enterprises
    enterprises <- runDB $ selectList [EnterpriseStatus ==. Active] []

    -- Collect metrics for each enterprise
    mapM_ (collectMetricsForEnterprise metrics) enterprises

-- | Helper function to collect metrics for a single enterprise
collectMetricsForEnterprise :: MonadIO m
                           => EnterpriseMetrics
                           -> Entity Enterprise
                           -> m ()
collectMetricsForEnterprise metrics (Entity _ enterprise) = do
    now <- liftIO getCurrentTime
    let enterpriseId = enterpriseEnterpriseId enterprise

    -- Collect resource usage
    resourceUsage <- getEnterpriseResourceUsage enterpriseId
    void $ recordResourceUsage metrics enterpriseId "total" resourceUsage (object [])

    -- Collect feature usage
    featureUsage <- getEnterpriseFeatureUsage enterpriseId
    mapM_ (\(feature, usage) ->
        recordFeatureUsage metrics enterpriseId feature usage) featureUsage

-- | Helper function to clean up old metrics
cleanupOldMetrics :: MonadIO m => EnterpriseMetrics -> m ()
cleanupOldMetrics EnterpriseMetrics{..} = do
    now <- liftIO getCurrentTime
    let cutoff = addUTCTime (fromIntegral $ -86400 * metricsRetentionDays metricsConfig) now

    -- Clean up old metrics
    runDB $ do
        deleteWhere [EnterpriseApiMetricTimestamp <. cutoff]
        deleteWhere [EnterpriseResourceMetricTimestamp <. cutoff]
        deleteWhere [EnterpriseFeatureMetricTimestamp <. cutoff]
