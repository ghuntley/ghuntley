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

module Gerrit.Models.LDAPConfig
    ( -- * Types
      LDAPConfig(..)
    , LDAPConfigId
    , LDAPSecurityMode(..)
    , LDAPSyncMode(..)
    , LDAPGroupMapping(..)
      -- * Operations
    , createLDAPConfig
    , updateLDAPConfig
    , getLDAPConfigById
    , listLDAPConfigs
    , enableLDAPConfig
    , disableLDAPConfig
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

-- | LDAP security mode
data LDAPSecurityMode
    = None
    | StartTLS
    | LDAPS
    deriving (Show, Read, Eq, Generic)
derivePersistField "LDAPSecurityMode"

-- | LDAP sync mode
data LDAPSyncMode
    = OnDemand
    | Scheduled
    | RealTime
    deriving (Show, Read, Eq, Generic)
derivePersistField "LDAPSyncMode"

-- | LDAP group mapping
data LDAPGroupMapping = LDAPGroupMapping
    { ldapGroup :: Text
    , gerritRole :: Text
    , attributes :: Value
    } deriving (Show, Read, Eq, Generic)
derivePersistField "LDAPGroupMapping"

-- | Define the LDAP configuration entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
LDAPConfig
    configId Text
    name Text
    description Text Maybe
    serverUrl Text
    bindDN Text
    bindPassword Text
    baseDN Text
    userFilter Text
    groupFilter Text Maybe
    securityMode LDAPSecurityMode
    syncMode LDAPSyncMode
    groupMappings [LDAPGroupMapping]
    syncInterval Int Maybe
    lastSync UTCTime Maybe
    enabled Bool
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueLDAPConfigId configId
    UniqueLDAPConfigName name
    deriving Show Eq Generic
|]

-- | Create LDAP configuration
createLDAPConfig :: MonadIO m
                => Text  -- ^ Name
                -> Maybe Text  -- ^ Description
                -> Text  -- ^ Server URL
                -> Text  -- ^ Bind DN
                -> Text  -- ^ Bind password
                -> Text  -- ^ Base DN
                -> Text  -- ^ User filter
                -> Maybe Text  -- ^ Group filter
                -> LDAPSecurityMode  -- ^ Security mode
                -> LDAPSyncMode  -- ^ Sync mode
                -> [LDAPGroupMapping]  -- ^ Group mappings
                -> Maybe Int  -- ^ Sync interval (in minutes)
                -> Maybe Value  -- ^ Additional metadata
                -> m (Entity LDAPConfig)
createLDAPConfig name desc serverUrl bindDN bindPw baseDN userFilter groupFilter secMode syncMode mappings interval metadata = do
    now <- liftIO getCurrentTime
    let configId = generateConfigId name now
    let config = LDAPConfig
            { ldapConfigConfigId = configId
            , ldapConfigName = name
            , ldapConfigDescription = desc
            , ldapConfigServerUrl = serverUrl
            , ldapConfigBindDN = bindDN
            , ldapConfigBindPassword = bindPw
            , ldapConfigBaseDN = baseDN
            , ldapConfigUserFilter = userFilter
            , ldapConfigGroupFilter = groupFilter
            , ldapConfigSecurityMode = secMode
            , ldapConfigSyncMode = syncMode
            , ldapConfigGroupMappings = mappings
            , ldapConfigSyncInterval = interval
            , ldapConfigLastSync = Nothing
            , ldapConfigEnabled = True
            , ldapConfigMetadata = metadata
            , ldapConfigCreated = now
            , ldapConfigUpdated = now
            }
    runDB $ insertEntity config

-- | Update LDAP configuration
updateLDAPConfig :: MonadIO m
                => Entity LDAPConfig
                -> Text  -- ^ Name
                -> Maybe Text  -- ^ Description
                -> Text  -- ^ Server URL
                -> Text  -- ^ Bind DN
                -> Text  -- ^ Bind password
                -> Text  -- ^ Base DN
                -> Text  -- ^ User filter
                -> Maybe Text  -- ^ Group filter
                -> LDAPSecurityMode  -- ^ Security mode
                -> LDAPSyncMode  -- ^ Sync mode
                -> [LDAPGroupMapping]  -- ^ Group mappings
                -> Maybe Int  -- ^ Sync interval
                -> Maybe Value  -- ^ Additional metadata
                -> m (Entity LDAPConfig)
updateLDAPConfig (Entity key config) name desc serverUrl bindDN bindPw baseDN userFilter groupFilter secMode syncMode mappings interval metadata = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { ldapConfigName = name
            , ldapConfigDescription = desc
            , ldapConfigServerUrl = serverUrl
            , ldapConfigBindDN = bindDN
            , ldapConfigBindPassword = bindPw
            , ldapConfigBaseDN = baseDN
            , ldapConfigUserFilter = userFilter
            , ldapConfigGroupFilter = groupFilter
            , ldapConfigSecurityMode = secMode
            , ldapConfigSyncMode = syncMode
            , ldapConfigGroupMappings = mappings
            , ldapConfigSyncInterval = interval
            , ldapConfigMetadata = metadata
            , ldapConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Get LDAP configuration by ID
getLDAPConfigById :: MonadIO m
                 => Text  -- ^ Config ID
                 -> m (Maybe (Entity LDAPConfig))
getLDAPConfigById configId =
    runDB $ getBy $ UniqueLDAPConfigId configId

-- | List LDAP configurations
listLDAPConfigs :: MonadIO m
                => Bool  -- ^ Only enabled configs
                -> Int   -- ^ Offset
                -> Int   -- ^ Limit
                -> m [Entity LDAPConfig]
listLDAPConfigs onlyEnabled offset limit = do
    let filters = [LDAPConfigEnabled ==. True | onlyEnabled]
    runDB $ selectList filters [Asc LDAPConfigName, OffsetBy offset, LimitTo limit]

-- | Enable LDAP configuration
enableLDAPConfig :: MonadIO m
                => Entity LDAPConfig
                -> m (Entity LDAPConfig)
enableLDAPConfig (Entity key config) = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { ldapConfigEnabled = True
            , ldapConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Disable LDAP configuration
disableLDAPConfig :: MonadIO m
                 => Entity LDAPConfig
                 -> m (Entity LDAPConfig)
disableLDAPConfig (Entity key config) = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { ldapConfigEnabled = False
            , ldapConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- Helper functions for generating IDs
generateConfigId :: Text -> UTCTime -> Text
generateConfigId name timestamp =
    "ldap_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
