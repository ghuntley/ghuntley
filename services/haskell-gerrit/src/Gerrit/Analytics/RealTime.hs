-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Analytics.RealTime
    ( MetricUpdate(..)
    , MetricCache(..)
    , UpdatePriority(..)
    , CacheConfig(..)
    , initializeCache
    , updateMetrics
    , broadcastUpdate
    , invalidateCache
    , getCachedMetrics
    ) where

import Control.Concurrent.STM
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import qualified Network.WebSockets as WS
import Gerrit.Analytics.Types

-- | Metric update types
data MetricUpdate
    = ActivityUpdate ActivityMetrics
    | QualityUpdate QualityMetrics
    | ContributorUpdate ContributorMetrics
    deriving (Show)

-- | Update priority levels
data UpdatePriority
    = LowPriority      -- ^ Background updates, no urgency
    | NormalPriority   -- ^ Standard updates
    | HighPriority     -- ^ Important updates, process quickly
    | CriticalPriority -- ^ Critical updates, process immediately
    deriving (Show, Eq, Ord)

-- | Cache configuration
data CacheConfig = CacheConfig
    { ccMaxSize :: Int           -- ^ Maximum number of items in cache
    , ccTTL :: Int              -- ^ Time to live in seconds
    , ccUpdateInterval :: Int    -- ^ Update interval in seconds
    , ccPriorityThreshold :: UpdatePriority  -- ^ Minimum priority for immediate updates
    } deriving (Show)

-- | Default cache configuration
defaultCacheConfig :: CacheConfig
defaultCacheConfig = CacheConfig
    { ccMaxSize = 1000
    , ccTTL = 300  -- 5 minutes
    , ccUpdateInterval = 60  -- 1 minute
    , ccPriorityThreshold = HighPriority
    }

-- | Metric cache
data MetricCache = MetricCache
    { mcActivity :: TVar (Map Text (ActivityMetrics, UTCTime))
    , mcQuality :: TVar (Map Text (QualityMetrics, UTCTime))
    , mcContributor :: TVar (Map Text (ContributorMetrics, UTCTime))
    , mcConfig :: CacheConfig
    , mcClients :: TVar [WS.Connection]
    }

-- | Initialize a new metric cache
initializeCache :: MonadIO m => CacheConfig -> m MetricCache
initializeCache config = liftIO $ atomically $ do
    activity <- newTVar Map.empty
    quality <- newTVar Map.empty
    contributor <- newTVar Map.empty
    clients <- newTVar []
    return MetricCache
        { mcActivity = activity
        , mcQuality = quality
        , mcContributor = contributor
        , mcConfig = config
        , mcClients = clients
        }

-- | Update metrics in the cache
updateMetrics :: MonadIO m
              => MetricCache
              -> Text  -- ^ Metric key
              -> MetricUpdate
              -> UpdatePriority
              -> m ()
updateMetrics cache key update priority = liftIO $ do
    now <- getCurrentTime
    let shouldBroadcast = priority >= ccPriorityThreshold (mcConfig cache)

    atomically $ case update of
        ActivityUpdate metrics -> do
            modifyTVar' (mcActivity cache) $ Map.insert key (metrics, now)
        QualityUpdate metrics -> do
            modifyTVar' (mcQuality cache) $ Map.insert key (metrics, now)
        ContributorUpdate metrics -> do
            modifyTVar' (mcContributor cache) $ Map.insert key (metrics, now)

    when shouldBroadcast $ do
        broadcastUpdate cache key update

-- | Broadcast metric update to connected clients
broadcastUpdate :: MonadIO m
                => MetricCache
                -> Text  -- ^ Metric key
                -> MetricUpdate
                -> m ()
broadcastUpdate cache key update = liftIO $ do
    clients <- readTVarIO (mcClients cache)
    let message = encodeUpdate key update
    forM_ clients $ \conn ->
        WS.sendTextData conn message
  where
    encodeUpdate :: Text -> MetricUpdate -> Text
    encodeUpdate k = undefined  -- TODO: Implement JSON encoding

-- | Invalidate cached metrics
invalidateCache :: MonadIO m
                => MetricCache
                -> Text  -- ^ Metric key
                -> m ()
invalidateCache cache key = liftIO $ atomically $ do
    modifyTVar' (mcActivity cache) $ Map.delete key
    modifyTVar' (mcQuality cache) $ Map.delete key
    modifyTVar' (mcContributor cache) $ Map.delete key

-- | Get cached metrics
getCachedMetrics :: MonadIO m
                 => MetricCache
                 -> Text  -- ^ Metric key
                 -> m (Maybe MetricUpdate)
getCachedMetrics cache key = liftIO $ do
    now <- getCurrentTime
    let ttl = fromIntegral $ ccTTL (mcConfig cache)
    let expired = addUTCTime (-ttl) now

    atomically $ do
        -- Check activity metrics
        activity <- Map.lookup key <$> readTVar (mcActivity cache)
        case activity of
            Just (metrics, timestamp) | timestamp > expired ->
                return $ Just $ ActivityUpdate metrics
            _ -> do
                -- Check quality metrics
                quality <- Map.lookup key <$> readTVar (mcQuality cache)
                case quality of
                    Just (metrics, timestamp) | timestamp > expired ->
                        return $ Just $ QualityUpdate metrics
                    _ -> do
                        -- Check contributor metrics
                        contributor <- Map.lookup key <$> readTVar (mcContributor cache)
                        case contributor of
                            Just (metrics, timestamp) | timestamp > expired ->
                                return $ Just $ ContributorUpdate metrics
                            _ -> return Nothing

-- | Add a new WebSocket client
addClient :: MonadIO m => MetricCache -> WS.Connection -> m ()
addClient cache conn = liftIO $ atomically $
    modifyTVar' (mcClients cache) (conn:)

-- | Remove a WebSocket client
removeClient :: MonadIO m => MetricCache -> WS.Connection -> m ()
removeClient cache conn = liftIO $ atomically $
    modifyTVar' (mcClients cache) (filter (/= conn))

-- | Clean up expired cache entries
cleanupCache :: MonadIO m => MetricCache -> m ()
cleanupCache cache = liftIO $ do
    now <- getCurrentTime
    let ttl = fromIntegral $ ccTTL (mcConfig cache)
    let expired = addUTCTime (-ttl) now

    atomically $ do
        modifyTVar' (mcActivity cache) $ Map.filter ((> expired) . snd)
        modifyTVar' (mcQuality cache) $ Map.filter ((> expired) . snd)
        modifyTVar' (mcContributor cache) $ Map.filter ((> expired) . snd)

-- | Start the cache cleanup background task
startCacheCleanup :: MonadIO m => MetricCache -> m ()
startCacheCleanup cache = liftIO $ void $ forkIO $ forever $ do
    threadDelay $ ccUpdateInterval (mcConfig cache) * 1000000
    cleanupCache cache

-- | Start the metrics update background task
startMetricsUpdate :: MonadIO m => MetricCache -> m ()
startMetricsUpdate cache = liftIO $ void $ forkIO $ forever $ do
    threadDelay $ ccUpdateInterval (mcConfig cache) * 1000000
    updateAllMetrics cache

-- | Update all metrics in the cache
updateAllMetrics :: MonadIO m => MetricCache -> m ()
updateAllMetrics cache = liftIO $ do
    now <- getCurrentTime
    let start = addUTCTime (-86400) now  -- Last 24 hours

    -- Calculate new metrics
    activity <- calculateActivityMetrics start now
    quality <- calculateQualityMetrics start now
    contributor <- calculateContributorMetrics start now

    -- Update cache with new metrics
    updateMetrics cache "global" (ActivityUpdate activity) NormalPriority
    updateMetrics cache "global" (QualityUpdate quality) NormalPriority
    updateMetrics cache "global" (ContributorUpdate contributor) NormalPriority
