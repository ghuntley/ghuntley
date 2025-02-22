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

module Gerrit.Models.SecurityConfig where

import Data.Aeson
import Data.Text (Text)
import Data.Time
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

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

-- | Persistent models for security configuration
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
DatabaseSecurityConfig
    configId Text
    enableSSL Bool
    sslMode SSLMode
    sslCert Text Maybe
    sslKey Text Maybe
    sslRootCert Text Maybe
    poolConfig PoolConfig
    lastUpdated UTCTime
    updatedBy Text
    UniqueDatabaseSecurityConfigId configId
    deriving Show Eq Generic

SecurityAudit
    auditId Text
    configId Text
    action Text
    details Value
    performedBy Text
    timestamp UTCTime
    Foreign DatabaseSecurityConfig configId References databaseSecurityConfigs OnDeleteCascade
    UniqueSecurityAuditId auditId
    deriving Show Eq Generic

ConnectionError
    errorId Text
    configId Text Maybe
    errorType Text
    errorMessage Text
    errorDetails Value Maybe
    occurredAt UTCTime
    UniqueConnectionErrorId errorId
    deriving Show Eq Generic
|]

-- | Helper functions for security configuration management
updateDatabaseConfig :: MonadIO m
                    => Text  -- ^ Config ID
                    -> Bool  -- ^ Enable SSL
                    -> SSLMode  -- ^ SSL mode
                    -> Maybe Text  -- ^ SSL cert path
                    -> Maybe Text  -- ^ SSL key path
                    -> Maybe Text  -- ^ SSL root cert path
                    -> PoolConfig  -- ^ Pool configuration
                    -> Text  -- ^ Updated by
                    -> m (Either Text ())
updateDatabaseConfig configId enableSSL sslMode sslCert sslKey sslRootCert poolCfg updatedBy = do
    now <- getCurrentTime
    runDB $ do
        -- Check if config exists
        existing <- selectFirst [DatabaseSecurityConfigConfigId ==. configId] []
        case existing of
            Just _ -> do
                -- Update existing config
                updateWhere
                    [DatabaseSecurityConfigConfigId ==. configId]
                    [ DatabaseSecurityConfigEnableSSL =. enableSSL
                    , DatabaseSecurityConfigSslMode =. sslMode
                    , DatabaseSecurityConfigSslCert =. sslCert
                    , DatabaseSecurityConfigSslKey =. sslKey
                    , DatabaseSecurityConfigSslRootCert =. sslRootCert
                    , DatabaseSecurityConfigPoolConfig =. poolCfg
                    , DatabaseSecurityConfigLastUpdated =. now
                    , DatabaseSecurityConfigUpdatedBy =. updatedBy
                    ]
            Nothing -> do
                -- Create new config
                insert_ DatabaseSecurityConfig
                    { databaseSecurityConfigConfigId = configId
                    , databaseSecurityConfigEnableSSL = enableSSL
                    , databaseSecurityConfigSslMode = sslMode
                    , databaseSecurityConfigSslCert = sslCert
                    , databaseSecurityConfigSslKey = sslKey
                    , databaseSecurityConfigSslRootCert = sslRootCert
                    , databaseSecurityConfigPoolConfig = poolCfg
                    , databaseSecurityConfigLastUpdated = now
                    , databaseSecurityConfigUpdatedBy = updatedBy
                    }
    return $ Right ()

logSecurityAudit :: MonadIO m
                 => Text  -- ^ Config ID
                 -> Text  -- ^ Action
                 -> Value  -- ^ Details
                 -> Text  -- ^ Performed by
                 -> m (Either Text ())
logSecurityAudit configId action details performedBy = do
    auditId <- generateAuditId
    now <- getCurrentTime
    runDB $ insert_ SecurityAudit
        { securityAuditAuditId = auditId
        , securityAuditConfigId = configId
        , securityAuditAction = action
        , securityAuditDetails = details
        , securityAuditPerformedBy = performedBy
        , securityAuditTimestamp = now
        }
    return $ Right ()
  where
    generateAuditId = undefined -- Replace with actual ID generation in implementation

logConnectionError :: MonadIO m
                   => Text  -- ^ Error type
                   -> Text  -- ^ Error message
                   -> Maybe Value  -- ^ Error details
                   -> Maybe Text  -- ^ Config ID
                   -> m (Either Text ())
logConnectionError errorType errorMsg errorDetails configId = do
    errorId <- generateErrorId
    now <- getCurrentTime
    runDB $ insert_ ConnectionError
        { connectionErrorErrorId = errorId
        , connectionErrorConfigId = configId
        , connectionErrorErrorType = errorType
        , connectionErrorErrorMessage = errorMsg
        , connectionErrorErrorDetails = errorDetails
        , connectionErrorOccurredAt = now
        }
    return $ Right ()
  where
    generateErrorId = undefined -- Replace with actual ID generation in implementation

getSecurityConfig :: MonadIO m
                  => Text  -- ^ Config ID
                  -> m (Maybe (Entity DatabaseSecurityConfig))
getSecurityConfig configId =
    runDB $ selectFirst [DatabaseSecurityConfigConfigId ==. configId] []

getSecurityAuditLog :: MonadIO m
                    => Text  -- ^ Config ID
                    -> UTCTime  -- ^ Start time
                    -> UTCTime  -- ^ End time
                    -> m [Entity SecurityAudit]
getSecurityAuditLog configId start end =
    runDB $ selectList
        [ SecurityAuditConfigId ==. configId
        , SecurityAuditTimestamp >=. start
        , SecurityAuditTimestamp <=. end
        ]
        [Desc SecurityAuditTimestamp]

getConnectionErrors :: MonadIO m
                    => Maybe Text  -- ^ Config ID
                    -> UTCTime  -- ^ Start time
                    -> UTCTime  -- ^ End time
                    -> m [Entity ConnectionError]
getConnectionErrors configId start end =
    runDB $ selectList
        ([ ConnectionErrorOccurredAt >=. start
         , ConnectionErrorOccurredAt <=. end
         ] ++ maybe [] (\cid -> [ConnectionErrorConfigId ==. Just cid]) configId)
        [Desc ConnectionErrorOccurredAt]
