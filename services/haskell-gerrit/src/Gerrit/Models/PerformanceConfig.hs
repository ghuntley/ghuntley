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

module Gerrit.Models.PerformanceConfig
    ( -- * Types
      PerformanceConfig(..)
    , PerformanceConfigId
    , CacheConfig(..)
    , InvalidationStrategy(..)
    , ResourceLimits(..)
      -- * Operations
    , createPerformanceConfig
    , updatePerformanceConfig
    , getPerformanceConfigById
    , listPerformanceConfigs
    , enablePerformanceConfig
    , disablePerformanceConfig
    , deletePerformanceConfig
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

-- | Cache configuration
data CacheConfig = CacheConfig
    { maxSize :: Int
    , ttl :: NominalDiffTime
    , invalidationStrategy :: InvalidationStrategy
    } deriving (Show, Read, Eq, Generic)
derivePersistField "CacheConfig"

-- | Cache invalidation strategy
data InvalidationStrategy
    = TimeBasedInvalidation NominalDiffTime
    | VersionBasedInvalidation
    | EventBasedInvalidation
    deriving (Show, Read, Eq, Generic)
derivePersistField "InvalidationStrategy"

-- | Resource limits configuration
data ResourceLimits = ResourceLimits
    { maxConnections :: Int
    , maxStatements :: Int
    , maxResultSetSize :: Int
    , maxQueryMemory :: Int
    , maxTempSpace :: Int
    } deriving (Show, Read, Eq, Generic)
derivePersistField "ResourceLimits"

-- | Define the performance configuration entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
PerformanceConfig
    configId Text
    name Text
    description Text
    dbPoolSize Int
    dbPoolIdleTimeout NominalDiffTime
    dbPoolMaxLifetime NominalDiffTime
    dbPoolStripes Int
    cacheConfig CacheConfig
    resourceLimits ResourceLimits
    queryTimeout NominalDiffTime
    enabled Bool
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniquePerformanceConfigId configId
    UniquePerformanceConfigName name
    deriving Show Eq Generic
|]

-- | Create performance configuration
createPerformanceConfig :: MonadIO m
                       => Text  -- ^ Name
                       -> Text  -- ^ Description
                       -> Int   -- ^ DB pool size
                       -> NominalDiffTime  -- ^ DB pool idle timeout
                       -> NominalDiffTime  -- ^ DB pool max lifetime
                       -> Int   -- ^ DB pool stripes
                       -> CacheConfig  -- ^ Cache configuration
                       -> ResourceLimits  -- ^ Resource limits
                       -> NominalDiffTime  -- ^ Query timeout
                       -> Maybe Value  -- ^ Additional metadata
                       -> m (Entity PerformanceConfig)
createPerformanceConfig name description poolSize idleTimeout maxLifetime stripes cache limits timeout metadata = do
    now <- liftIO getCurrentTime
    let configId = generateConfigId name now
    let config = PerformanceConfig
            { performanceConfigConfigId = configId
            , performanceConfigName = name
            , performanceConfigDescription = description
            , performanceConfigDbPoolSize = poolSize
            , performanceConfigDbPoolIdleTimeout = idleTimeout
            , performanceConfigDbPoolMaxLifetime = maxLifetime
            , performanceConfigDbPoolStripes = stripes
            , performanceConfigCacheConfig = cache
            , performanceConfigResourceLimits = limits
            , performanceConfigQueryTimeout = timeout
            , performanceConfigEnabled = True
            , performanceConfigMetadata = metadata
            , performanceConfigCreated = now
            , performanceConfigUpdated = now
            }
    runDB $ insertEntity config

-- | Update performance configuration
updatePerformanceConfig :: MonadIO m
                       => Entity PerformanceConfig
                       -> Text  -- ^ Name
                       -> Text  -- ^ Description
                       -> Int   -- ^ DB pool size
                       -> NominalDiffTime  -- ^ DB pool idle timeout
                       -> NominalDiffTime  -- ^ DB pool max lifetime
                       -> Int   -- ^ DB pool stripes
                       -> CacheConfig  -- ^ Cache configuration
                       -> ResourceLimits  -- ^ Resource limits
                       -> NominalDiffTime  -- ^ Query timeout
                       -> Maybe Value  -- ^ Additional metadata
                       -> m (Entity PerformanceConfig)
updatePerformanceConfig (Entity key config) name description poolSize idleTimeout maxLifetime stripes cache limits timeout metadata = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { performanceConfigName = name
            , performanceConfigDescription = description
            , performanceConfigDbPoolSize = poolSize
            , performanceConfigDbPoolIdleTimeout = idleTimeout
            , performanceConfigDbPoolMaxLifetime = maxLifetime
            , performanceConfigDbPoolStripes = stripes
            , performanceConfigCacheConfig = cache
            , performanceConfigResourceLimits = limits
            , performanceConfigQueryTimeout = timeout
            , performanceConfigMetadata = metadata
            , performanceConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Get performance configuration by ID
getPerformanceConfigById :: MonadIO m
                        => Text  -- ^ Config ID
                        -> m (Maybe (Entity PerformanceConfig))
getPerformanceConfigById configId =
    runDB $ getBy $ UniquePerformanceConfigId configId

-- | List performance configurations
listPerformanceConfigs :: MonadIO m
                      => Bool  -- ^ Only enabled configs
                      -> Int   -- ^ Offset
                      -> Int   -- ^ Limit
                      -> m [Entity PerformanceConfig]
listPerformanceConfigs onlyEnabled offset limit = do
    let filters = [PerformanceConfigEnabled ==. True | onlyEnabled]
    runDB $ selectList filters [Asc PerformanceConfigName, OffsetBy offset, LimitTo limit]

-- | Enable performance configuration
enablePerformanceConfig :: MonadIO m
                       => Entity PerformanceConfig
                       -> m (Entity PerformanceConfig)
enablePerformanceConfig (Entity key config) = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { performanceConfigEnabled = True
            , performanceConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Disable performance configuration
disablePerformanceConfig :: MonadIO m
                        => Entity PerformanceConfig
                        -> m (Entity PerformanceConfig)
disablePerformanceConfig (Entity key config) = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { performanceConfigEnabled = False
            , performanceConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Delete performance configuration
deletePerformanceConfig :: MonadIO m
                       => Entity PerformanceConfig
                       -> m ()
deletePerformanceConfig (Entity key _) =
    runDB $ delete key

-- Helper functions for generating IDs
generateConfigId :: Text -> UTCTime -> Text
generateConfigId name timestamp =
    "pc_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
