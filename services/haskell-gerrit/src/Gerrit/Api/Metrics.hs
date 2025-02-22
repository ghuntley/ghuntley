{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Metrics
    ( -- * Metrics
      Metrics(..)
    , initMetrics
    , withMetrics
      -- * Request metrics
    , incrementRequests
    , observeRequestDuration
    , incrementEndpointRequests
    , observeEndpointDuration
      -- * Error metrics
    , incrementErrors
    , observeResponseSize
    , incrementRateLimitExceeded
    , incrementValidationErrors
      -- * Database metrics
    , setActiveConnections
    , setDatabaseConnections
    , incrementDatabaseQueries
    , observeDatabaseQueryDuration
    , incrementDatabaseErrors
      -- * Git metrics
    , incrementGitOperations
    , incrementGitErrors
      -- * Cache metrics
    , incrementCacheHits
    , incrementCacheMisses
    , setCacheSize
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Text (Text)
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import Network.HTTP.Types (Status(..))
import Network.Wai (Middleware, Request, Response, responseStatus, pathInfo)
import System.Metrics (Store, createStore, registerGauge, registerCounter)
import System.Remote.Monitoring.Prometheus (Server, serverMetricStore, exportMetricsAsText)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified System.Metrics.Counter as Counter
import qualified System.Metrics.Gauge as Gauge

-- | Application metrics
data Metrics = Metrics
    { -- Request metrics
      requestsTotal :: Counter.Counter        -- ^ Total number of requests
    , requestDuration :: Gauge.Gauge          -- ^ Request duration in milliseconds
    , activeConnections :: Gauge.Gauge        -- ^ Current number of active connections
    , responseSize :: Gauge.Gauge             -- ^ Response size in bytes
      -- Endpoint metrics
    , endpointRequests :: Map.Map Text Counter.Counter  -- ^ Requests per endpoint
    , endpointDuration :: Map.Map Text Gauge.Gauge      -- ^ Duration per endpoint
      -- Error metrics
    , errorsTotal :: Counter.Counter          -- ^ Total number of errors
    , rateLimitExceeded :: Counter.Counter    -- ^ Number of rate limit violations
    , validationErrors :: Counter.Counter     -- ^ Number of validation errors
      -- Database metrics
    , dbConnections :: Gauge.Gauge            -- ^ Current number of database connections
    , dbQueriesTotal :: Counter.Counter       -- ^ Total number of database queries
    , dbQueryDuration :: Gauge.Gauge          -- ^ Database query duration in milliseconds
    , dbErrors :: Counter.Counter             -- ^ Database operation errors
      -- Git metrics
    , gitOperationsTotal :: Counter.Counter   -- ^ Total number of Git operations
    , gitOperationErrors :: Counter.Counter   -- ^ Number of Git operation errors
      -- Cache metrics
    , cacheHits :: Counter.Counter            -- ^ Number of cache hits
    , cacheMisses :: Counter.Counter          -- ^ Number of cache misses
    , cacheSize :: Gauge.Gauge                -- ^ Current cache size in bytes
    }

-- | Initialize metrics
initMetrics :: IO (Store, Metrics)
initMetrics = do
    store <- createStore

    -- Create basic metrics
    requestsTotal' <- Counter.new
    requestDuration' <- Gauge.new
    activeConnections' <- Gauge.new
    responseSize' <- Gauge.new
    errorsTotal' <- Counter.new
    rateLimitExceeded' <- Counter.new
    validationErrors' <- Counter.new
    dbConnections' <- Gauge.new
    dbQueriesTotal' <- Counter.new
    dbQueryDuration' <- Gauge.new
    dbErrors' <- Counter.new
    gitOperationsTotal' <- Counter.new
    gitOperationErrors' <- Counter.new
    cacheHits' <- Counter.new
    cacheMisses' <- Counter.new
    cacheSize' <- Gauge.new

    -- Create endpoint-specific metrics
    endpointRequests' <- createEndpointCounters store
    endpointDuration' <- createEndpointGauges store

    -- Register basic metrics
    registerCounter "gerrit_requests_total" requestsTotal' store
    registerGauge "gerrit_request_duration_ms" requestDuration' store
    registerGauge "gerrit_active_connections" activeConnections' store
    registerGauge "gerrit_response_size_bytes" responseSize' store
    registerCounter "gerrit_errors_total" errorsTotal' store
    registerCounter "gerrit_rate_limit_exceeded_total" rateLimitExceeded' store
    registerCounter "gerrit_validation_errors_total" validationErrors' store
    registerGauge "gerrit_db_connections" dbConnections' store
    registerCounter "gerrit_db_queries_total" dbQueriesTotal' store
    registerGauge "gerrit_db_query_duration_ms" dbQueryDuration' store
    registerCounter "gerrit_db_errors_total" dbErrors' store
    registerCounter "gerrit_git_operations_total" gitOperationsTotal' store
    registerCounter "gerrit_git_operation_errors_total" gitOperationErrors' store
    registerCounter "gerrit_cache_hits_total" cacheHits' store
    registerCounter "gerrit_cache_misses_total" cacheMisses' store
    registerGauge "gerrit_cache_size_bytes" cacheSize' store

    let metrics = Metrics
            { requestsTotal = requestsTotal'
            , requestDuration = requestDuration'
            , activeConnections = activeConnections'
            , responseSize = responseSize'
            , endpointRequests = endpointRequests'
            , endpointDuration = endpointDuration'
            , errorsTotal = errorsTotal'
            , rateLimitExceeded = rateLimitExceeded'
            , validationErrors = validationErrors'
            , dbConnections = dbConnections'
            , dbQueriesTotal = dbQueriesTotal'
            , dbQueryDuration = dbQueryDuration'
            , dbErrors = dbErrors'
            , gitOperationsTotal = gitOperationsTotal'
            , gitOperationErrors = gitOperationErrors'
            , cacheHits = cacheHits'
            , cacheMisses = cacheMisses'
            , cacheSize = cacheSize'
            }

    return (store, metrics)

-- | Create endpoint-specific counters
createEndpointCounters :: Store -> IO (Map.Map Text Counter.Counter)
createEndpointCounters store = do
    let endpoints =
            [ "changes_list", "changes_create", "changes_get", "changes_update"
            , "revisions_list", "revisions_create", "revisions_get"
            , "comments_list", "comments_create", "comments_get", "comments_update"
            , "votes_list", "votes_create", "votes_get", "votes_submit"
            ]
    counters <- mapM (\endpoint -> do
        counter <- Counter.new
        registerCounter ("gerrit_endpoint_" <> endpoint <> "_requests_total") counter store
        return (endpoint, counter)
        ) endpoints
    return $ Map.fromList counters

-- | Create endpoint-specific gauges
createEndpointGauges :: Store -> IO (Map.Map Text Gauge.Gauge)
createEndpointGauges store = do
    let endpoints =
            [ "changes_list", "changes_create", "changes_get", "changes_update"
            , "revisions_list", "revisions_create", "revisions_get"
            , "comments_list", "comments_create", "comments_get", "comments_update"
            , "votes_list", "votes_create", "votes_get", "votes_submit"
            ]
    gauges <- mapM (\endpoint -> do
        gauge <- Gauge.new
        registerGauge ("gerrit_endpoint_" <> endpoint <> "_duration_ms") gauge store
        return (endpoint, gauge)
        ) endpoints
    return $ Map.fromList gauges

-- | Metrics middleware
withMetrics :: Metrics -> Middleware
withMetrics metrics app req respond = do
    -- Record start time
    startTime <- getCurrentTime

    -- Increment request counter
    incrementRequests metrics

    -- Get endpoint name
    let endpoint = getEndpointName $ pathInfo req

    -- Increment endpoint-specific counter
    incrementEndpointRequests metrics endpoint

    -- Update active connections
    Gauge.inc (activeConnections metrics)

    -- Wrap the response to collect metrics
    let respond' res = do
        -- Record end time and calculate duration
        endTime <- getCurrentTime
        let duration = realToFrac $ diffUTCTime endTime startTime * 1000  -- Convert to milliseconds

        -- Record durations
        observeRequestDuration metrics duration
        observeEndpointDuration metrics endpoint duration

        -- Record response size
        let size = maybe 0 id $ lookup "Content-Length" $ responseHeaders res
        observeResponseSize metrics (read $ Text.unpack size)

        -- Update error metrics if needed
        let status = statusCode $ responseStatus res
        when (status >= 400) $
            incrementErrors metrics

        -- Decrement active connections
        Gauge.dec (activeConnections metrics)

        -- Send response
        respond res

    app req respond'

-- | Get endpoint name from path
getEndpointName :: [Text] -> Text
getEndpointName path = case path of
    ["api", "v1", "changes"] -> "changes_list"
    ["api", "v1", "changes", _] -> "changes_get"
    ["api", "v1", "changes", _, "status"] -> "changes_update"
    ["api", "v1", "changes", _, "revisions"] -> "revisions_list"
    ["api", "v1", "changes", _, "revisions", _] -> "revisions_get"
    ["api", "v1", "changes", _, "revisions", _, "comments"] -> "comments_list"
    ["api", "v1", "changes", _, "revisions", _, "comments", _] -> "comments_get"
    ["api", "v1", "changes", _, "revisions", _, "votes"] -> "votes_list"
    ["api", "v1", "changes", _, "revisions", _, "votes", "submit-check"] -> "votes_submit"
    _ -> "unknown"

-- | Increment total requests counter
incrementRequests :: MonadIO m => Metrics -> m ()
incrementRequests metrics =
    liftIO $ Counter.inc (requestsTotal metrics)

-- | Record request duration
observeRequestDuration :: MonadIO m => Metrics -> Double -> m ()
observeRequestDuration metrics duration =
    liftIO $ Gauge.set (requestDuration metrics) duration

-- | Increment endpoint-specific request counter
incrementEndpointRequests :: MonadIO m => Metrics -> Text -> m ()
incrementEndpointRequests metrics endpoint =
    liftIO $ case Map.lookup endpoint (endpointRequests metrics) of
        Just counter -> Counter.inc counter
        Nothing -> return ()

-- | Record endpoint-specific duration
observeEndpointDuration :: MonadIO m => Metrics -> Text -> Double -> m ()
observeEndpointDuration metrics endpoint duration =
    liftIO $ case Map.lookup endpoint (endpointDuration metrics) of
        Just gauge -> Gauge.set gauge duration
        Nothing -> return ()

-- | Increment error counter
incrementErrors :: MonadIO m => Metrics -> m ()
incrementErrors metrics =
    liftIO $ Counter.inc (errorsTotal metrics)

-- | Record response size
observeResponseSize :: MonadIO m => Metrics -> Int -> m ()
observeResponseSize metrics size =
    liftIO $ Gauge.set (responseSize metrics) (fromIntegral size)

-- | Increment rate limit exceeded counter
incrementRateLimitExceeded :: MonadIO m => Metrics -> m ()
incrementRateLimitExceeded metrics =
    liftIO $ Counter.inc (rateLimitExceeded metrics)

-- | Increment validation errors counter
incrementValidationErrors :: MonadIO m => Metrics -> m ()
incrementValidationErrors metrics =
    liftIO $ Counter.inc (validationErrors metrics)

-- | Set number of active connections
setActiveConnections :: MonadIO m => Metrics -> Int -> m ()
setActiveConnections metrics count =
    liftIO $ Gauge.set (activeConnections metrics) (fromIntegral count)

-- | Set number of database connections
setDatabaseConnections :: MonadIO m => Metrics -> Int -> m ()
setDatabaseConnections metrics count =
    liftIO $ Gauge.set (dbConnections metrics) (fromIntegral count)

-- | Increment database queries counter
incrementDatabaseQueries :: MonadIO m => Metrics -> m ()
incrementDatabaseQueries metrics =
    liftIO $ Counter.inc (dbQueriesTotal metrics)

-- | Record database query duration
observeDatabaseQueryDuration :: MonadIO m => Metrics -> Double -> m ()
observeDatabaseQueryDuration metrics duration =
    liftIO $ Gauge.set (dbQueryDuration metrics) duration

-- | Increment database errors counter
incrementDatabaseErrors :: MonadIO m => Metrics -> m ()
incrementDatabaseErrors metrics =
    liftIO $ Counter.inc (dbErrors metrics)

-- | Increment Git operations counter
incrementGitOperations :: MonadIO m => Metrics -> m ()
incrementGitOperations metrics =
    liftIO $ Counter.inc (gitOperationsTotal metrics)

-- | Increment Git errors counter
incrementGitErrors :: MonadIO m => Metrics -> m ()
incrementGitErrors metrics =
    liftIO $ Counter.inc (gitOperationErrors metrics)

-- | Increment cache hits counter
incrementCacheHits :: MonadIO m => Metrics -> m ()
incrementCacheHits metrics =
    liftIO $ Counter.inc (cacheHits metrics)

-- | Increment cache misses counter
incrementCacheMisses :: MonadIO m => Metrics -> m ()
incrementCacheMisses metrics =
    liftIO $ Counter.inc (cacheMisses metrics)

-- | Set cache size
setCacheSize :: MonadIO m => Metrics -> Int -> m ()
setCacheSize metrics size =
    liftIO $ Gauge.set (cacheSize metrics) (fromIntegral size)
