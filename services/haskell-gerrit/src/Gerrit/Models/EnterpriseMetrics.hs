{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

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

module Gerrit.Models.EnterpriseMetrics
    ( -- * Types
      EnterpriseMetric(..)
    , MetricId
    , MetricType(..)
      -- * Operations
    , recordMetric
    , getMetricById
    , getEnterpriseMetrics
    , getMetricsByType
    , aggregateMetrics
    , pruneOldMetrics
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Enterprise (Enterprise)

-- | Metric types
data MetricType
    = UserCount
    | ProjectCount
    | StorageUsage
    | ApiUsage
    | ReviewCount
    | MergeCount
    | BuildTime
    | ResponseTime
    | ErrorRate
    | CustomMetric Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "MetricType"

-- | Define the EnterpriseMetric entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
EnterpriseMetric
    metricId Text
    enterpriseId Text
    metricType MetricType
    value Int
    timestamp UTCTime
    UniqueMetricId metricId
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Record a new metric
recordMetric :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Enterprise ID
             -> MetricType  -- ^ Metric type
             -> Int  -- ^ Value
             -> m (Entity EnterpriseMetric)
recordMetric pool enterpriseId' metricType' value' = do
    now <- liftIO getCurrentTime
    let metricId' = generateMetricId enterpriseId' metricType' now
    let metric = EnterpriseMetric
            { enterpriseMetricMetricId = metricId'
            , enterpriseMetricEnterpriseId = enterpriseId'
            , enterpriseMetricMetricType = metricType'
            , enterpriseMetricValue = value'
            , enterpriseMetricTimestamp = now
            }
    runSqlPool (insertEntity metric) pool

-- | Get a metric by ID
getMetricById :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Metric ID
              -> m (Maybe (Entity EnterpriseMetric))
getMetricById pool metricId' =
    runSqlPool (getBy $ UniqueMetricId metricId') pool

-- | Get metrics for an enterprise
getEnterpriseMetrics :: MonadIO m
                    => ConnectionPool
                    -> Text  -- ^ Enterprise ID
                    -> Maybe UTCTime  -- ^ Start time
                    -> Maybe UTCTime  -- ^ End time
                    -> m [Entity EnterpriseMetric]
getEnterpriseMetrics pool enterpriseId' mStart mEnd = do
    let filters = (EnterpriseMetricEnterpriseId ==. enterpriseId') :
                 maybe [] (\start -> [EnterpriseMetricTimestamp >=. start]) mStart ++
                 maybe [] (\end -> [EnterpriseMetricTimestamp <=. end]) mEnd
    runSqlPool (selectList filters [Asc EnterpriseMetricTimestamp]) pool

-- | Get metrics by type
getMetricsByType :: MonadIO m
                 => ConnectionPool
                 -> MetricType  -- ^ Metric type
                 -> Maybe UTCTime  -- ^ Start time
                 -> Maybe UTCTime  -- ^ End time
                 -> m [Entity EnterpriseMetric]
getMetricsByType pool metricType' mStart mEnd = do
    let filters = (EnterpriseMetricMetricType ==. metricType') :
                 maybe [] (\start -> [EnterpriseMetricTimestamp >=. start]) mStart ++
                 maybe [] (\end -> [EnterpriseMetricTimestamp <=. end]) mEnd
    runSqlPool (selectList filters [Asc EnterpriseMetricTimestamp]) pool

-- | Aggregate metrics by type
aggregateMetrics :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Enterprise ID
                 -> MetricType  -- ^ Metric type
                 -> UTCTime  -- ^ Start time
                 -> UTCTime  -- ^ End time
                 -> m [(UTCTime, Int)]  -- ^ List of (timestamp, sum) tuples
aggregateMetrics pool enterpriseId' metricType' start end = do
    metrics <- getEnterpriseMetrics pool enterpriseId' (Just start) (Just end)
    let filtered = filter (\(Entity _ m) -> enterpriseMetricMetricType m == metricType') metrics
    return $ map (\(Entity _ m) -> (enterpriseMetricTimestamp m, enterpriseMetricValue m)) filtered

-- | Prune old metrics
pruneOldMetrics :: MonadIO m
                => ConnectionPool
                -> UTCTime  -- ^ Cutoff time
                -> m Int  -- ^ Number of metrics deleted
pruneOldMetrics pool cutoff =
    runSqlPool (deleteWhere [EnterpriseMetricTimestamp <=. cutoff]) pool

-- Helper functions for generating IDs
generateMetricId :: Text -> MetricType -> UTCTime -> Text
generateMetricId enterpriseId metricType timestamp =
    "metric_" <> Text.filter isAllowed enterpriseId <> "_" <>
    metricTypeStr metricType <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
    metricTypeStr = Text.pack . show
    formatTime = Text.pack . show
