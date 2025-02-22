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

module Gerrit.Models.TokenAnalytics
    ( -- * Types
      TokenUsage(..)
    , TokenUsageId
    , TokenUsageScope(..)
    , SecurityEvent(..)
    , TokenRotation(..)
    , TokenHealthMetrics(..)
      -- * Operations
    , recordTokenUsage
    , recordScopeUsage
    , recordSecurityEvent
    , recordTokenRotation
    , updateHealthMetrics
    , getTokenUsage
    , getTokenHealth
    , getSecurityEvents
    , getRotationHistory
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.TokenConfig (TokenConfig)

-- | Define the token analytics entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
TokenUsage
    tokenValue Text
    endpoint Text
    ipAddress Text
    userAgent Text
    status Text default="success"
    timestamp UTCTime
    responseTime Int Maybe
    Foreign TokenConfig tokenValue References tokenConfigs OnDeleteCascade
    deriving Show Eq Generic

TokenUsageScope
    tokenValue Text
    scope Text
    timestamp UTCTime
    lastUsed UTCTime
    Foreign TokenConfig tokenValue References tokenConfigs OnDeleteCascade
    deriving Show Eq Generic

SecurityEvent
    eventId Text
    tokenValue Text
    eventType Text
    severity Text
    details Value
    timestamp UTCTime
    UniqueSecurityEventId eventId
    Foreign TokenConfig tokenValue References tokenConfigs OnDeleteCascade
    deriving Show Eq Generic

TokenRotation
    rotationId Text
    oldTokenValue Text
    newTokenValue Text
    rotationType Text
    reason Text Maybe
    timestamp UTCTime
    UniqueTokenRotationId rotationId
    Foreign TokenConfig oldTokenValue References tokenConfigs OnDeleteCascade
    Foreign TokenConfig newTokenValue References tokenConfigs OnDeleteCascade
    deriving Show Eq Generic

TokenHealthMetrics
    tokenValue Text
    overallScore Double
    rotationScore Double
    scopeScore Double
    errorRate Double
    securityScore Double
    timestamp UTCTime
    Foreign TokenConfig tokenValue References tokenConfigs OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Record token usage
recordTokenUsage :: MonadIO m
                 => Text  -- ^ Token value
                 -> Text  -- ^ Endpoint
                 -> Text  -- ^ IP address
                 -> Text  -- ^ User agent
                 -> Text  -- ^ Status
                 -> Maybe Int  -- ^ Response time in milliseconds
                 -> m (Entity TokenUsage)
recordTokenUsage token endpoint ip agent status respTime = do
    now <- liftIO getCurrentTime
    let usage = TokenUsage
            { tokenUsageTokenValue = token
            , tokenUsageEndpoint = endpoint
            , tokenUsageIpAddress = ip
            , tokenUsageUserAgent = agent
            , tokenUsageStatus = status
            , tokenUsageTimestamp = now
            , tokenUsageResponseTime = respTime
            }
    runDB $ insertEntity usage

-- | Record scope usage
recordScopeUsage :: MonadIO m
                 => Text  -- ^ Token value
                 -> Text  -- ^ Scope
                 -> m (Entity TokenUsageScope)
recordScopeUsage token scope = do
    now <- liftIO getCurrentTime
    let scopeUsage = TokenUsageScope
            { tokenUsageScopeTokenValue = token
            , tokenUsageScopeScope = scope
            , tokenUsageScopeTimestamp = now
            , tokenUsageScopeLastUsed = now
            }
    runDB $ insertEntity scopeUsage

-- | Record security event
recordSecurityEvent :: MonadIO m
                    => Text  -- ^ Token value
                    -> Text  -- ^ Event type
                    -> Text  -- ^ Severity
                    -> Value  -- ^ Event details
                    -> m (Entity SecurityEvent)
recordSecurityEvent token eventType severity details = do
    now <- liftIO getCurrentTime
    let eventId = generateEventId token now
    let event = SecurityEvent
            { securityEventEventId = eventId
            , securityEventTokenValue = token
            , securityEventEventType = eventType
            , securityEventSeverity = severity
            , securityEventDetails = details
            , securityEventTimestamp = now
            }
    runDB $ insertEntity event

-- | Record token rotation
recordTokenRotation :: MonadIO m
                    => Text  -- ^ Old token value
                    -> Text  -- ^ New token value
                    -> Text  -- ^ Rotation type
                    -> Maybe Text  -- ^ Reason
                    -> m (Entity TokenRotation)
recordTokenRotation oldToken newToken rotType reason = do
    now <- liftIO getCurrentTime
    let rotationId = generateRotationId oldToken newToken now
    let rotation = TokenRotation
            { tokenRotationRotationId = rotationId
            , tokenRotationOldTokenValue = oldToken
            , tokenRotationNewTokenValue = newToken
            , tokenRotationRotationType = rotType
            , tokenRotationReason = reason
            , tokenRotationTimestamp = now
            }
    runDB $ insertEntity rotation

-- | Update token health metrics
updateHealthMetrics :: MonadIO m
                    => Text  -- ^ Token value
                    -> Double  -- ^ Overall score
                    -> Double  -- ^ Rotation score
                    -> Double  -- ^ Scope score
                    -> Double  -- ^ Error rate
                    -> Double  -- ^ Security score
                    -> m (Entity TokenHealthMetrics)
updateHealthMetrics token overall rotation scope error security = do
    now <- liftIO getCurrentTime
    let metrics = TokenHealthMetrics
            { tokenHealthMetricsTokenValue = token
            , tokenHealthMetricsOverallScore = overall
            , tokenHealthMetricsRotationScore = rotation
            , tokenHealthMetricsScopeScore = scope
            , tokenHealthMetricsErrorRate = error
            , tokenHealthMetricsSecurityScore = security
            , tokenHealthMetricsTimestamp = now
            }
    runDB $ insertEntity metrics

-- | Get token usage statistics
getTokenUsage :: MonadIO m
              => Text  -- ^ Token value
              -> UTCTime  -- ^ Start time
              -> UTCTime  -- ^ End time
              -> m [Entity TokenUsage]
getTokenUsage token start end =
    runDB $ selectList
        [ TokenUsageTokenValue ==. token
        , TokenUsageTimestamp >=. start
        , TokenUsageTimestamp <=. end
        ]
        [Asc TokenUsageTimestamp]

-- | Get token health metrics
getTokenHealth :: MonadIO m
               => Text  -- ^ Token value
               -> m (Maybe (Entity TokenHealthMetrics))
getTokenHealth token =
    runDB $ selectFirst
        [TokenHealthMetricsTokenValue ==. token]
        [Desc TokenHealthMetricsTimestamp]

-- | Get security events
getSecurityEvents :: MonadIO m
                  => Text  -- ^ Token value
                  -> UTCTime  -- ^ Start time
                  -> UTCTime  -- ^ End time
                  -> m [Entity SecurityEvent]
getSecurityEvents token start end =
    runDB $ selectList
        [ SecurityEventTokenValue ==. token
        , SecurityEventTimestamp >=. start
        , SecurityEventTimestamp <=. end
        ]
        [Desc SecurityEventTimestamp]

-- | Get rotation history
getRotationHistory :: MonadIO m
                   => Text  -- ^ Token value
                   -> m [Entity TokenRotation]
getRotationHistory token =
    runDB $ selectList
        [TokenRotationOldTokenValue ==. token ||. TokenRotationNewTokenValue ==. token]
        [Desc TokenRotationTimestamp]

-- Helper functions for generating IDs
generateEventId :: Text -> UTCTime -> Text
generateEventId token timestamp =
    "evt_" <> Text.filter isAllowed token <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateRotationId :: Text -> Text -> UTCTime -> Text
generateRotationId oldToken newToken timestamp =
    "rot_" <> Text.filter isAllowed (oldToken <> "_" <> newToken) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
