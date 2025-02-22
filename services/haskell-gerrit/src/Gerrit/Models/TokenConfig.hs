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

module Gerrit.Models.TokenConfig
    ( -- * Types
      TokenConfig(..)
    , TokenConfigId
    , TokenType(..)
    , TokenTypeConfig(..)
    , SecurityPolicy(..)
    , RotationPolicy(..)
      -- * Operations
    , createTokenConfig
    , updateTokenConfig
    , getTokenConfigById
    , listTokenConfigs
    , enableTokenConfig
    , disableTokenConfig
    , deleteTokenConfig
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

-- | Token type
data TokenType
    = AccessToken
    | RefreshToken
    | ApiKey
    deriving (Show, Read, Eq, Generic)
derivePersistField "TokenType"

-- | Rotation policy
data RotationPolicy
    = OnRefresh
    | OnUse
    | Manual
    deriving (Show, Read, Eq, Generic)
derivePersistField "RotationPolicy"

-- | Token type configuration
data TokenTypeConfig = TokenTypeConfig
    { expiration :: Maybe NominalDiffTime
    , refreshAllowed :: Bool
    , scope :: [Text]
    , rotationPolicy :: RotationPolicy
    } deriving (Show, Read, Eq, Generic)
derivePersistField "TokenTypeConfig"

-- | Security policy
data SecurityPolicy = SecurityPolicy
    { maxActiveTokens :: Int
    , maxRefreshCount :: Int
    , requireRotation :: Bool
    , ipBinding :: Bool
    , deviceBinding :: Bool
    } deriving (Show, Read, Eq, Generic)
derivePersistField "SecurityPolicy"

-- | Define the token configuration entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
TokenConfig
    configId Text
    name Text
    description Text
    tokenType TokenType
    typeConfig TokenTypeConfig
    securityPolicy SecurityPolicy
    enabled Bool
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueTokenConfigId configId
    UniqueTokenConfigName name
    deriving Show Eq Generic
|]

-- | Create token configuration
createTokenConfig :: MonadIO m
                 => Text  -- ^ Name
                 -> Text  -- ^ Description
                 -> TokenType  -- ^ Token type
                 -> TokenTypeConfig  -- ^ Type configuration
                 -> SecurityPolicy  -- ^ Security policy
                 -> Maybe Value  -- ^ Additional metadata
                 -> m (Entity TokenConfig)
createTokenConfig name description tType tConfig sPolicy metadata = do
    now <- liftIO getCurrentTime
    let configId = generateConfigId name now
    let config = TokenConfig
            { tokenConfigConfigId = configId
            , tokenConfigName = name
            , tokenConfigDescription = description
            , tokenConfigTokenType = tType
            , tokenConfigTypeConfig = tConfig
            , tokenConfigSecurityPolicy = sPolicy
            , tokenConfigEnabled = True
            , tokenConfigMetadata = metadata
            , tokenConfigCreated = now
            , tokenConfigUpdated = now
            }
    runDB $ insertEntity config

-- | Update token configuration
updateTokenConfig :: MonadIO m
                 => Entity TokenConfig
                 -> Text  -- ^ Name
                 -> Text  -- ^ Description
                 -> TokenType  -- ^ Token type
                 -> TokenTypeConfig  -- ^ Type configuration
                 -> SecurityPolicy  -- ^ Security policy
                 -> Maybe Value  -- ^ Additional metadata
                 -> m (Entity TokenConfig)
updateTokenConfig (Entity key config) name description tType tConfig sPolicy metadata = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { tokenConfigName = name
            , tokenConfigDescription = description
            , tokenConfigTokenType = tType
            , tokenConfigTypeConfig = tConfig
            , tokenConfigSecurityPolicy = sPolicy
            , tokenConfigMetadata = metadata
            , tokenConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Get token configuration by ID
getTokenConfigById :: MonadIO m
                  => Text  -- ^ Config ID
                  -> m (Maybe (Entity TokenConfig))
getTokenConfigById configId =
    runDB $ getBy $ UniqueTokenConfigId configId

-- | List token configurations
listTokenConfigs :: MonadIO m
                => Bool  -- ^ Only enabled configs
                -> Int   -- ^ Offset
                -> Int   -- ^ Limit
                -> m [Entity TokenConfig]
listTokenConfigs onlyEnabled offset limit = do
    let filters = [TokenConfigEnabled ==. True | onlyEnabled]
    runDB $ selectList filters [Asc TokenConfigName, OffsetBy offset, LimitTo limit]

-- | Enable token configuration
enableTokenConfig :: MonadIO m
                 => Entity TokenConfig
                 -> m (Entity TokenConfig)
enableTokenConfig (Entity key config) = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { tokenConfigEnabled = True
            , tokenConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Disable token configuration
disableTokenConfig :: MonadIO m
                  => Entity TokenConfig
                  -> m (Entity TokenConfig)
disableTokenConfig (Entity key config) = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { tokenConfigEnabled = False
            , tokenConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Delete token configuration
deleteTokenConfig :: MonadIO m
                 => Entity TokenConfig
                 -> m ()
deleteTokenConfig (Entity key _) =
    runDB $ delete key

-- Helper functions for generating IDs
generateConfigId :: Text -> UTCTime -> Text
generateConfigId name timestamp =
    "tc_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
