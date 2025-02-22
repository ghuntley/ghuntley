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

module Gerrit.Models.DatabaseConfig where

import Data.Aeson
import Data.Text (Text)
import Data.Time
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

-- | Log level for database operations
data LogLevel = LevelDebug | LevelInfo | LevelWarn | LevelError
    deriving (Show, Eq, Generic)

instance ToJSON LogLevel
instance FromJSON LogLevel

-- | SSL mode for database connections
data SSLMode = SSLDisable | SSLAllow | SSLPrefer | SSLRequire | SSLVerifyCA | SSLVerifyFull
    deriving (Show, Eq, Generic)

instance ToJSON SSLMode
instance FromJSON SSLMode

-- | Connection pool configuration
data PoolConfig = PoolConfig
    { poolSize :: Int
    , poolIdleTimeout :: NominalDiffTime
    , poolMaxLifetime :: NominalDiffTime
    , poolStripes :: Int
    } deriving (Show, Eq, Generic)

instance ToJSON PoolConfig
instance FromJSON PoolConfig

-- | Persistent models for database configuration
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
DatabaseConfig
    configId Text
    host Text
    port Int
    name Text
    user Text
    password Text
    poolConfig PoolConfig
    logLevel LogLevel
    enableSSL Bool
    sslMode SSLMode
    sslCert Text Maybe
    sslKey Text Maybe
    sslRootCert Text Maybe
    lastUpdated UTCTime
    updatedBy Text
    UniqueDatabaseConfigId configId
    deriving Show Eq Generic

ConfigHistory
    configId Text
    changeType Text
    oldValue Value Maybe
    newValue Value
    changedBy Text
    timestamp UTCTime
    Foreign DatabaseConfig configId References databaseConfigs OnDeleteCascade
    deriving Show Eq Generic

ConfigAudit
    auditId Text
    configId Text
    action Text
    details Value
    performedBy Text
    timestamp UTCTime
    Foreign DatabaseConfig configId References databaseConfigs OnDeleteCascade
    UniqueConfigAuditId auditId
    deriving Show Eq Generic
|]

-- | Helper functions for database configuration management
createDatabaseConfig :: MonadIO m
                    => Text  -- ^ Config ID
                    -> Text  -- ^ Host
                    -> Int   -- ^ Port
                    -> Text  -- ^ Database name
                    -> Text  -- ^ User
                    -> Text  -- ^ Password
                    -> PoolConfig  -- ^ Pool configuration
                    -> LogLevel  -- ^ Log level
                    -> Bool  -- ^ Enable SSL
                    -> SSLMode  -- ^ SSL mode
                    -> Maybe Text  -- ^ SSL cert path
                    -> Maybe Text  -- ^ SSL key path
                    -> Maybe Text  -- ^ SSL root cert path
                    -> Text  -- ^ Created by
                    -> m (Either Text ())
createDatabaseConfig configId host port name user password poolCfg logLevel enableSSL sslMode sslCert sslKey sslRootCert createdBy = do
    now <- getCurrentTime
    runDB $ do
        -- Create new config
        insert_ DatabaseConfig
            { databaseConfigConfigId = configId
            , databaseConfigHost = host
            , databaseConfigPort = port
            , databaseConfigName = name
            , databaseConfigUser = user
            , databaseConfigPassword = password
            , databaseConfigPoolConfig = poolCfg
            , databaseConfigLogLevel = logLevel
            , databaseConfigEnableSSL = enableSSL
            , databaseConfigSslMode = sslMode
            , databaseConfigSslCert = sslCert
            , databaseConfigSslKey = sslKey
            , databaseConfigSslRootCert = sslRootCert
            , databaseConfigLastUpdated = now
            , databaseConfigUpdatedBy = createdBy
            }
        -- Log creation in history
        insert_ ConfigHistory
            { configHistoryConfigId = configId
            , configHistoryChangeType = "create"
            , configHistoryOldValue = Nothing
            , configHistoryNewValue = toJSON $ object
                [ "host" .= host
                , "port" .= port
                , "name" .= name
                , "user" .= user
                , "poolConfig" .= poolCfg
                , "logLevel" .= logLevel
                , "enableSSL" .= enableSSL
                , "sslMode" .= sslMode
                ]
            , configHistoryChangedBy = createdBy
            , configHistoryTimestamp = now
            }
    return $ Right ()

updateDatabaseConfig :: MonadIO m
                    => Text  -- ^ Config ID
                    -> Text  -- ^ Host
                    -> Int   -- ^ Port
                    -> Text  -- ^ Database name
                    -> Text  -- ^ User
                    -> Text  -- ^ Password
                    -> PoolConfig  -- ^ Pool configuration
                    -> LogLevel  -- ^ Log level
                    -> Bool  -- ^ Enable SSL
                    -> SSLMode  -- ^ SSL mode
                    -> Maybe Text  -- ^ SSL cert path
                    -> Maybe Text  -- ^ SSL key path
                    -> Maybe Text  -- ^ SSL root cert path
                    -> Text  -- ^ Updated by
                    -> m (Either Text ())
updateDatabaseConfig configId host port name user password poolCfg logLevel enableSSL sslMode sslCert sslKey sslRootCert updatedBy = do
    now <- getCurrentTime
    runDB $ do
        -- Get old config for history
        oldConfig <- get (DatabaseConfigKey configId)
        -- Update config
        update (DatabaseConfigKey configId)
            [ DatabaseConfigHost =. host
            , DatabaseConfigPort =. port
            , DatabaseConfigName =. name
            , DatabaseConfigUser =. user
            , DatabaseConfigPassword =. password
            , DatabaseConfigPoolConfig =. poolCfg
            , DatabaseConfigLogLevel =. logLevel
            , DatabaseConfigEnableSSL =. enableSSL
            , DatabaseConfigSslMode =. sslMode
            , DatabaseConfigSslCert =. sslCert
            , DatabaseConfigSslKey =. sslKey
            , DatabaseConfigSslRootCert =. sslRootCert
            , DatabaseConfigLastUpdated =. now
            , DatabaseConfigUpdatedBy =. updatedBy
            ]
        -- Log update in history
        insert_ ConfigHistory
            { configHistoryConfigId = configId
            , configHistoryChangeType = "update"
            , configHistoryOldValue = Just $ toJSON oldConfig
            , configHistoryNewValue = toJSON $ object
                [ "host" .= host
                , "port" .= port
                , "name" .= name
                , "user" .= user
                , "poolConfig" .= poolCfg
                , "logLevel" .= logLevel
                , "enableSSL" .= enableSSL
                , "sslMode" .= sslMode
                ]
            , configHistoryChangedBy = updatedBy
            , configHistoryTimestamp = now
            }
    return $ Right ()

logConfigAudit :: MonadIO m
               => Text  -- ^ Config ID
               -> Text  -- ^ Action
               -> Value  -- ^ Details
               -> Text  -- ^ Performed by
               -> m (Either Text ())
logConfigAudit configId action details performedBy = do
    auditId <- generateAuditId
    now <- getCurrentTime
    runDB $ insert_ ConfigAudit
        { configAuditAuditId = auditId
        , configAuditConfigId = configId
        , configAuditAction = action
        , configAuditDetails = details
        , configAuditPerformedBy = performedBy
        , configAuditTimestamp = now
        }
    return $ Right ()
  where
    generateAuditId = undefined -- Replace with actual ID generation in implementation

getDatabaseConfig :: MonadIO m
                  => Text  -- ^ Config ID
                  -> m (Maybe (Entity DatabaseConfig))
getDatabaseConfig configId =
    runDB $ selectFirst [DatabaseConfigConfigId ==. configId] []

getConfigHistory :: MonadIO m
                 => Text  -- ^ Config ID
                 -> UTCTime  -- ^ Start time
                 -> UTCTime  -- ^ End time
                 -> m [Entity ConfigHistory]
getConfigHistory configId start end =
    runDB $ selectList
        [ ConfigHistoryConfigId ==. configId
        , ConfigHistoryTimestamp >=. start
        , ConfigHistoryTimestamp <=. end
        ]
        [Desc ConfigHistoryTimestamp]

getConfigAuditLog :: MonadIO m
                  => Text  -- ^ Config ID
                  -> UTCTime  -- ^ Start time
                  -> UTCTime  -- ^ End time
                  -> m [Entity ConfigAudit]
getConfigAuditLog configId start end =
    runDB $ selectList
        [ ConfigAuditConfigId ==. configId
        , ConfigAuditTimestamp >=. start
        , ConfigAuditTimestamp <=. end
        ]
        [Desc ConfigAuditTimestamp]
