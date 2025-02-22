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

module Gerrit.Models.MetricsConfig
    ( -- * Types
      MetricsConfig(..)
    , MetricsConfigId
    , MetricType(..)
    , CollectionStrategy(..)
    , AggregationMethod(..)
      -- * Operations
    , createMetricsConfig
    , updateMetricsConfig
    , getMetricsConfigById
    , listMetricsConfigs
    , enableMetricsConfig
    , disableMetricsConfig
    , deleteMetricsConfig
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, NominalDiffTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Metric type
data MetricType
    = Counter
        { name :: Text
        , labels :: [Text]
        }
    | Gauge
        { name :: Text
        , labels :: [Text]
        }
    | Histogram
        { name :: Text
        , labels :: [Text]
        , buckets :: [Double]
        }
    deriving (Show, Read, Eq, Generic)
derivePersistField "MetricType"

-- | Collection strategy
data CollectionStrategy
    = RealTime
        { interval :: NominalDiffTime
        }
    | Batched
        { batchSize :: Int
        , flushInterval :: NominalDiffTime
        }
    | OnDemand
    deriving (Show, Read, Eq, Generic)
derivePersistField "CollectionStrategy"

-- | Aggregation method
data AggregationMethod
    = Sum
    | Average
    | Percentile Double
    | Rate NominalDiffTime
    | Custom Text Value
    deriving (Show, Read, Eq, Generic)
derivePersistField "AggregationMethod"

-- | Define the metrics configuration entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
MetricsConfig
    configId Text
    name Text
    description Text
    metricType MetricType
    collectionStrategy CollectionStrategy
    aggregationMethods [AggregationMethod]
    retentionPeriod NominalDiffTime
    enabled Bool
    alertThresholds Value Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueMetricsConfigId configId
    UniqueMetricsConfigName name
    deriving Show Eq Generic
|]

-- | Create metrics configuration
createMetricsConfig :: MonadIO m
                   => Text  -- ^ Name
                   -> Text  -- ^ Description
                   -> MetricType  -- ^ Metric type
                   -> CollectionStrategy  -- ^ Collection strategy
                   -> [AggregationMethod]  -- ^ Aggregation methods
                   -> NominalDiffTime  -- ^ Retention period
                   -> Maybe Value  -- ^ Alert thresholds
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity MetricsConfig)
createMetricsConfig name description mType strategy methods retention thresholds metadata = do
    now <- liftIO getCurrentTime
    let configId = generateConfigId name now
    let config = MetricsConfig
            { metricsConfigConfigId = configId
            , metricsConfigName = name
            , metricsConfigDescription = description
            , metricsConfigMetricType = mType
            , metricsConfigCollectionStrategy = strategy
            , metricsConfigAggregationMethods = methods
            , metricsConfigRetentionPeriod = retention
            , metricsConfigEnabled = True
            , metricsConfigAlertThresholds = thresholds
            , metricsConfigMetadata = metadata
            , metricsConfigCreated = now
            , metricsConfigUpdated = now
            }
    runDB $ insertEntity config

-- | Update metrics configuration
updateMetricsConfig :: MonadIO m
                   => Entity MetricsConfig
                   -> Text  -- ^ Name
                   -> Text  -- ^ Description
                   -> MetricType  -- ^ Metric type
                   -> CollectionStrategy  -- ^ Collection strategy
                   -> [AggregationMethod]  -- ^ Aggregation methods
                   -> NominalDiffTime  -- ^ Retention period
                   -> Maybe Value  -- ^ Alert thresholds
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity MetricsConfig)
updateMetricsConfig (Entity key config) name description mType strategy methods retention thresholds metadata = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { metricsConfigName = name
            , metricsConfigDescription = description
            , metricsConfigMetricType = mType
            , metricsConfigCollectionStrategy = strategy
            , metricsConfigAggregationMethods = methods
            , metricsConfigRetentionPeriod = retention
            , metricsConfigAlertThresholds = thresholds
            , metricsConfigMetadata = metadata
            , metricsConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Get metrics configuration by ID
getMetricsConfigById :: MonadIO m
                    => Text  -- ^ Config ID
                    -> m (Maybe (Entity MetricsConfig))
getMetricsConfigById configId =
    runDB $ getBy $ UniqueMetricsConfigId configId

-- | List metrics configurations
listMetricsConfigs :: MonadIO m
                  => Bool  -- ^ Only enabled configs
                  -> Int   -- ^ Offset
                  -> Int   -- ^ Limit
                  -> m [Entity MetricsConfig]
listMetricsConfigs onlyEnabled offset limit = do
    let filters = [MetricsConfigEnabled ==. True | onlyEnabled]
    runDB $ selectList filters [Asc MetricsConfigName, OffsetBy offset, LimitTo limit]

-- | Enable metrics configuration
enableMetricsConfig :: MonadIO m
                   => Entity MetricsConfig
                   -> m (Entity MetricsConfig)
enableMetricsConfig (Entity key config) = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { metricsConfigEnabled = True
            , metricsConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Disable metrics configuration
disableMetricsConfig :: MonadIO m
                    => Entity MetricsConfig
                    -> m (Entity MetricsConfig)
disableMetricsConfig (Entity key config) = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { metricsConfigEnabled = False
            , metricsConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Delete metrics configuration
deleteMetricsConfig :: MonadIO m
                   => Entity MetricsConfig
                   -> m ()
deleteMetricsConfig (Entity key _) =
    runDB $ delete key

-- Helper functions for generating IDs
generateConfigId :: Text -> UTCTime -> Text
generateConfigId name timestamp =
    "mc_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
