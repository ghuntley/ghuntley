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

module Gerrit.Models.IntegrationConfig
    ( -- * Types
      IntegrationType(..)
    , AuthType(..)
    , SyncDirection(..)
    , IntegrationConfig(..)
    , IntegrationConfigId
    , IntegrationAuth(..)
    , IntegrationAuthId
    , IntegrationSync(..)
    , IntegrationSyncId
      -- * Operations
    , createIntegrationConfig
    , updateIntegrationConfig
    , getIntegrationConfigById
    , listIntegrationConfigs
    , createIntegrationAuth
    , updateIntegrationAuth
    , getIntegrationAuthById
    , createIntegrationSync
    , updateIntegrationSync
    , getIntegrationSyncById
    , listIntegrationSyncs
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.User (User)

-- | Integration type
data IntegrationType
    = JiraIntegration
    | GitHubIntegration
    | GitLabIntegration
    | BitbucketIntegration
    | JenkinsIntegration
    | SonarQubeIntegration
    | CustomIntegration Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "IntegrationType"

-- | Authentication type
data AuthType
    = BasicAuth
    | OAuth2
    | ApiKey
    | TokenAuth
    | CustomAuth Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "AuthType"

-- | Sync direction
data SyncDirection
    = ImportOnly
    | ExportOnly
    | Bidirectional
    deriving (Show, Read, Eq, Generic)
derivePersistField "SyncDirection"

-- | Define the integration configuration entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
IntegrationConfig
    configId Text
    name Text
    description Text Maybe
    integrationType IntegrationType
    baseUrl Text
    enabled Bool
    syncEnabled Bool
    webhookEnabled Bool
    webhookUrl Text Maybe
    webhookSecret Text Maybe
    customFields Value Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueConfigId configId
    UniqueName name
    deriving Show Eq Generic

IntegrationAuth
    authId Text
    configId Text
    authType AuthType
    username Text Maybe
    password Text Maybe
    token Text Maybe
    clientId Text Maybe
    clientSecret Text Maybe
    refreshToken Text Maybe
    tokenExpiry UTCTime Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueAuthId authId
    UniqueConfigAuth configId
    Foreign IntegrationConfig configId References integrationConfigs OnDeleteCascade
    deriving Show Eq Generic

IntegrationSync
    syncId Text
    configId Text
    direction SyncDirection
    lastSync UTCTime Maybe
    nextSync UTCTime Maybe
    syncInterval Int  -- In minutes
    syncFilter Value Maybe
    syncMapping Value Maybe
    errorCount Int default=0
    lastError Text Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueSyncId syncId
    UniqueConfigSync configId
    Foreign IntegrationConfig configId References integrationConfigs OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create integration configuration
createIntegrationConfig :: MonadIO m
                       => Text  -- ^ Name
                       -> Maybe Text  -- ^ Description
                       -> IntegrationType  -- ^ Integration type
                       -> Text  -- ^ Base URL
                       -> Bool  -- ^ Enabled
                       -> Bool  -- ^ Sync enabled
                       -> Bool  -- ^ Webhook enabled
                       -> Maybe Text  -- ^ Webhook URL
                       -> Maybe Text  -- ^ Webhook secret
                       -> Maybe Value  -- ^ Custom fields
                       -> Maybe Value  -- ^ Additional metadata
                       -> m (Entity IntegrationConfig)
createIntegrationConfig name description iType baseUrl enabled syncEnabled webhookEnabled webhookUrl webhookSecret customFields metadata = do
    now <- liftIO getCurrentTime
    let configId = generateConfigId name now
    let config = IntegrationConfig
            { integrationConfigConfigId = configId
            , integrationConfigName = name
            , integrationConfigDescription = description
            , integrationConfigIntegrationType = iType
            , integrationConfigBaseUrl = baseUrl
            , integrationConfigEnabled = enabled
            , integrationConfigSyncEnabled = syncEnabled
            , integrationConfigWebhookEnabled = webhookEnabled
            , integrationConfigWebhookUrl = webhookUrl
            , integrationConfigWebhookSecret = webhookSecret
            , integrationConfigCustomFields = customFields
            , integrationConfigMetadata = metadata
            , integrationConfigCreated = now
            , integrationConfigUpdated = now
            }
    runDB $ insertEntity config

-- | Update integration configuration
updateIntegrationConfig :: MonadIO m
                       => Entity IntegrationConfig
                       -> Text  -- ^ Name
                       -> Maybe Text  -- ^ Description
                       -> IntegrationType  -- ^ Integration type
                       -> Text  -- ^ Base URL
                       -> Bool  -- ^ Enabled
                       -> Bool  -- ^ Sync enabled
                       -> Bool  -- ^ Webhook enabled
                       -> Maybe Text  -- ^ Webhook URL
                       -> Maybe Text  -- ^ Webhook secret
                       -> Maybe Value  -- ^ Custom fields
                       -> Maybe Value  -- ^ Additional metadata
                       -> m (Entity IntegrationConfig)
updateIntegrationConfig (Entity key config) name description iType baseUrl enabled syncEnabled webhookEnabled webhookUrl webhookSecret customFields metadata = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { integrationConfigName = name
            , integrationConfigDescription = description
            , integrationConfigIntegrationType = iType
            , integrationConfigBaseUrl = baseUrl
            , integrationConfigEnabled = enabled
            , integrationConfigSyncEnabled = syncEnabled
            , integrationConfigWebhookEnabled = webhookEnabled
            , integrationConfigWebhookUrl = webhookUrl
            , integrationConfigWebhookSecret = webhookSecret
            , integrationConfigCustomFields = customFields
            , integrationConfigMetadata = metadata
            , integrationConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Get integration configuration by ID
getIntegrationConfigById :: MonadIO m
                        => Text  -- ^ Config ID
                        -> m (Maybe (Entity IntegrationConfig))
getIntegrationConfigById configId =
    runDB $ getBy $ UniqueConfigId configId

-- | List integration configurations
listIntegrationConfigs :: MonadIO m
                      => Maybe IntegrationType  -- ^ Integration type filter
                      -> Bool  -- ^ Only enabled configs
                      -> Int  -- ^ Offset
                      -> Int  -- ^ Limit
                      -> m [Entity IntegrationConfig]
listIntegrationConfigs mType onlyEnabled offset limit = do
    let filters = catMaybes
            [ (IntegrationConfigIntegrationType ==.) <$> mType
            ] ++ [IntegrationConfigEnabled ==. True | onlyEnabled]
    runDB $ selectList filters [Asc IntegrationConfigName, OffsetBy offset, LimitTo limit]

-- | Create integration authentication
createIntegrationAuth :: MonadIO m
                     => Text  -- ^ Config ID
                     -> AuthType  -- ^ Authentication type
                     -> Maybe Text  -- ^ Username
                     -> Maybe Text  -- ^ Password
                     -> Maybe Text  -- ^ Token
                     -> Maybe Text  -- ^ Client ID
                     -> Maybe Text  -- ^ Client secret
                     -> Maybe Text  -- ^ Refresh token
                     -> Maybe UTCTime  -- ^ Token expiry
                     -> Maybe Value  -- ^ Additional metadata
                     -> m (Entity IntegrationAuth)
createIntegrationAuth configId authType username password token clientId clientSecret refreshToken expiry metadata = do
    now <- liftIO getCurrentTime
    let authId = generateAuthId configId now
    let auth = IntegrationAuth
            { integrationAuthAuthId = authId
            , integrationAuthConfigId = configId
            , integrationAuthAuthType = authType
            , integrationAuthUsername = username
            , integrationAuthPassword = password
            , integrationAuthToken = token
            , integrationAuthClientId = clientId
            , integrationAuthClientSecret = clientSecret
            , integrationAuthRefreshToken = refreshToken
            , integrationAuthTokenExpiry = expiry
            , integrationAuthMetadata = metadata
            , integrationAuthCreated = now
            , integrationAuthUpdated = now
            }
    runDB $ insertEntity auth

-- | Update integration authentication
updateIntegrationAuth :: MonadIO m
                     => Entity IntegrationAuth
                     -> AuthType  -- ^ Authentication type
                     -> Maybe Text  -- ^ Username
                     -> Maybe Text  -- ^ Password
                     -> Maybe Text  -- ^ Token
                     -> Maybe Text  -- ^ Client ID
                     -> Maybe Text  -- ^ Client secret
                     -> Maybe Text  -- ^ Refresh token
                     -> Maybe UTCTime  -- ^ Token expiry
                     -> Maybe Value  -- ^ Additional metadata
                     -> m (Entity IntegrationAuth)
updateIntegrationAuth (Entity key auth) authType username password token clientId clientSecret refreshToken expiry metadata = do
    now <- liftIO getCurrentTime
    let updatedAuth = auth
            { integrationAuthAuthType = authType
            , integrationAuthUsername = username
            , integrationAuthPassword = password
            , integrationAuthToken = token
            , integrationAuthClientId = clientId
            , integrationAuthClientSecret = clientSecret
            , integrationAuthRefreshToken = refreshToken
            , integrationAuthTokenExpiry = expiry
            , integrationAuthMetadata = metadata
            , integrationAuthUpdated = now
            }
    runDB $ replace key updatedAuth
    return $ Entity key updatedAuth

-- | Get integration authentication by ID
getIntegrationAuthById :: MonadIO m
                      => Text  -- ^ Auth ID
                      -> m (Maybe (Entity IntegrationAuth))
getIntegrationAuthById authId =
    runDB $ getBy $ UniqueAuthId authId

-- | Create integration sync configuration
createIntegrationSync :: MonadIO m
                     => Text  -- ^ Config ID
                     -> SyncDirection  -- ^ Sync direction
                     -> Int  -- ^ Sync interval in minutes
                     -> Maybe Value  -- ^ Sync filter
                     -> Maybe Value  -- ^ Sync mapping
                     -> Maybe Value  -- ^ Additional metadata
                     -> m (Entity IntegrationSync)
createIntegrationSync configId direction interval filter mapping metadata = do
    now <- liftIO getCurrentTime
    let syncId = generateSyncId configId now
    let sync = IntegrationSync
            { integrationSyncSyncId = syncId
            , integrationSyncConfigId = configId
            , integrationSyncDirection = direction
            , integrationSyncLastSync = Nothing
            , integrationSyncNextSync = Nothing
            , integrationSyncSyncInterval = interval
            , integrationSyncSyncFilter = filter
            , integrationSyncSyncMapping = mapping
            , integrationSyncErrorCount = 0
            , integrationSyncLastError = Nothing
            , integrationSyncMetadata = metadata
            , integrationSyncCreated = now
            , integrationSyncUpdated = now
            }
    runDB $ insertEntity sync

-- | Update integration sync configuration
updateIntegrationSync :: MonadIO m
                     => Entity IntegrationSync
                     -> SyncDirection  -- ^ Sync direction
                     -> Int  -- ^ Sync interval in minutes
                     -> Maybe Value  -- ^ Sync filter
                     -> Maybe Value  -- ^ Sync mapping
                     -> Maybe Value  -- ^ Additional metadata
                     -> m (Entity IntegrationSync)
updateIntegrationSync (Entity key sync) direction interval filter mapping metadata = do
    now <- liftIO getCurrentTime
    let updatedSync = sync
            { integrationSyncDirection = direction
            , integrationSyncSyncInterval = interval
            , integrationSyncSyncFilter = filter
            , integrationSyncSyncMapping = mapping
            , integrationSyncMetadata = metadata
            , integrationSyncUpdated = now
            }
    runDB $ replace key updatedSync
    return $ Entity key updatedSync

-- | Get integration sync configuration by ID
getIntegrationSyncById :: MonadIO m
                      => Text  -- ^ Sync ID
                      -> m (Maybe (Entity IntegrationSync))
getIntegrationSyncById syncId =
    runDB $ getBy $ UniqueSyncId syncId

-- | List integration sync configurations
listIntegrationSyncs :: MonadIO m
                    => Text  -- ^ Config ID
                    -> Maybe SyncDirection  -- ^ Direction filter
                    -> Int  -- ^ Offset
                    -> Int  -- ^ Limit
                    -> m [Entity IntegrationSync]
listIntegrationSyncs configId mDirection offset limit = do
    let filters = (IntegrationSyncConfigId ==. configId) :
                 maybe [] (\dir -> [IntegrationSyncDirection ==. dir]) mDirection
    runDB $ selectList filters [Desc IntegrationSyncLastSync, OffsetBy offset, LimitTo limit]

-- Helper functions for generating IDs
generateConfigId :: Text -> UTCTime -> Text
generateConfigId name timestamp =
    "ic_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateAuthId :: Text -> UTCTime -> Text
generateAuthId configId timestamp =
    "ia_" <> Text.filter isAllowed configId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateSyncId :: Text -> UTCTime -> Text
generateSyncId configId timestamp =
    "is_" <> Text.filter isAllowed configId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
