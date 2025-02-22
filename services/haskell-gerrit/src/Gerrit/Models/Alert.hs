{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Models.Alert
    ( -- * Types
      Alert(..)
    , AlertId
    , AlertSeverity(..)
    , AlertStatus(..)
    , AlertRule(..)
    , AlertRuleId
      -- * Operations
    , createAlert
    , updateAlert
    , getAlertById
    , listAlerts
    , acknowledgeAlert
    , createAlertRule
    , updateAlertRule
    , getAlertRuleById
    , listAlertRules
    , evaluateAlertRule
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

-- | Alert severity levels
data AlertSeverity
    = Info
    | Warning
    | Error
    | Critical
    deriving (Show, Read, Eq, Ord, Generic)
derivePersistField "AlertSeverity"

-- | Alert status
data AlertStatus
    = New
    | Acknowledged
    | Resolved
    | AutoResolved
    deriving (Show, Read, Eq, Generic)
derivePersistField "AlertStatus"

-- | Define the Alert and AlertRule entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Alert
    alertId Text
    title Text
    message Text
    severity AlertSeverity
    status AlertStatus
    source Text
    timestamp UTCTime
    acknowledgedBy Text Maybe
    acknowledgedAt UTCTime Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueAlertId alertId
    deriving Show Eq Generic

AlertRule
    ruleId Text
    name Text
    description Text
    enabled Bool
    thresholds Value
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueAlertRuleId ruleId
    UniqueAlertRuleName name
    deriving Show Eq Generic
|]

-- | Create a new alert
createAlert :: MonadIO m
            => Text  -- ^ Title
            -> Text  -- ^ Message
            -> AlertSeverity  -- ^ Severity
            -> Text  -- ^ Source
            -> Maybe Value  -- ^ Metadata
            -> m (Entity Alert)
createAlert title' message' severity' source' metadata' = do
    now <- liftIO getCurrentTime
    let alertId' = generateAlertId title' now
    let alert = Alert
            { alertAlertId = alertId'
            , alertTitle = title'
            , alertMessage = message'
            , alertSeverity = severity'
            , alertStatus = New
            , alertSource = source'
            , alertTimestamp = now
            , alertAcknowledgedBy = Nothing
            , alertAcknowledgedAt = Nothing
            , alertMetadata = metadata'
            , alertCreated = now
            , alertUpdated = now
            }
    runDB $ insertEntity alert

-- | Update alert details
updateAlert :: MonadIO m
            => Entity Alert
            -> Text  -- ^ New title
            -> Text  -- ^ New message
            -> AlertSeverity  -- ^ New severity
            -> AlertStatus  -- ^ New status
            -> Maybe Value  -- ^ New metadata
            -> m (Entity Alert)
updateAlert (Entity key alert) title' message' severity' status' metadata' = do
    now <- liftIO getCurrentTime
    let updatedAlert = alert
            { alertTitle = title'
            , alertMessage = message'
            , alertSeverity = severity'
            , alertStatus = status'
            , alertMetadata = metadata'
            , alertUpdated = now
            }
    runDB $ replace key updatedAlert
    return $ Entity key updatedAlert

-- | Get alert by ID
getAlertById :: MonadIO m
             => Text  -- ^ Alert ID
             -> m (Maybe (Entity Alert))
getAlertById alertId' =
    runDB $ getBy $ UniqueAlertId alertId'

-- | List alerts with filtering
listAlerts :: MonadIO m
           => Maybe AlertSeverity  -- ^ Filter by severity
           -> Maybe AlertStatus  -- ^ Filter by status
           -> Maybe Text  -- ^ Filter by source
           -> Int  -- ^ Offset
           -> Int  -- ^ Limit
           -> m [Entity Alert]
listAlerts severity status source offset limit = do
    let filters = catMaybes
            [ (AlertSeverity ==.) <$> severity
            , (AlertStatus ==.) <$> status
            , (AlertSource ==.) <$> source
            ]
    runDB $ selectList filters [Desc AlertTimestamp, OffsetBy offset, LimitTo limit]

-- | Acknowledge an alert
acknowledgeAlert :: MonadIO m
                => Entity Alert
                -> Text  -- ^ Acknowledged by
                -> m (Entity Alert)
acknowledgeAlert (Entity key alert) acknowledgedBy' = do
    now <- liftIO getCurrentTime
    let updatedAlert = alert
            { alertStatus = Acknowledged
            , alertAcknowledgedBy = Just acknowledgedBy'
            , alertAcknowledgedAt = Just now
            , alertUpdated = now
            }
    runDB $ replace key updatedAlert
    return $ Entity key updatedAlert

-- | Create a new alert rule
createAlertRule :: MonadIO m
                => Text  -- ^ Name
                -> Text  -- ^ Description
                -> Value  -- ^ Thresholds
                -> Maybe Value  -- ^ Metadata
                -> m (Entity AlertRule)
createAlertRule name' description' thresholds' metadata' = do
    now <- liftIO getCurrentTime
    let ruleId' = generateRuleId name' now
    let rule = AlertRule
            { alertRuleRuleId = ruleId'
            , alertRuleName = name'
            , alertRuleDescription = description'
            , alertRuleEnabled = True
            , alertRuleThresholds = thresholds'
            , alertRuleMetadata = metadata'
            , alertRuleCreated = now
            , alertRuleUpdated = now
            }
    runDB $ insertEntity rule

-- | Update alert rule
updateAlertRule :: MonadIO m
                => Entity AlertRule
                -> Text  -- ^ New name
                -> Text  -- ^ New description
                -> Value  -- ^ New thresholds
                -> Maybe Value  -- ^ New metadata
                -> m (Entity AlertRule)
updateAlertRule (Entity key rule) name' description' thresholds' metadata' = do
    now <- liftIO getCurrentTime
    let updatedRule = rule
            { alertRuleName = name'
            , alertRuleDescription = description'
            , alertRuleThresholds = thresholds'
            , alertRuleMetadata = metadata'
            , alertRuleUpdated = now
            }
    runDB $ replace key updatedRule
    return $ Entity key updatedRule

-- | Get alert rule by ID
getAlertRuleById :: MonadIO m
                 => Text  -- ^ Rule ID
                 -> m (Maybe (Entity AlertRule))
getAlertRuleById ruleId' =
    runDB $ getBy $ UniqueAlertRuleId ruleId'

-- | List alert rules
listAlertRules :: MonadIO m
               => Bool  -- ^ Only enabled rules
               -> Int  -- ^ Offset
               -> Int  -- ^ Limit
               -> m [Entity AlertRule]
listAlertRules onlyEnabled offset limit = do
    let filters = [AlertRuleEnabled ==. True | onlyEnabled]
    runDB $ selectList filters [Asc AlertRuleName, OffsetBy offset, LimitTo limit]

-- | Evaluate an alert rule against provided metrics
evaluateAlertRule :: MonadIO m
                  => Entity AlertRule
                  -> Value  -- ^ Metrics to evaluate
                  -> m (Maybe (Entity Alert))
evaluateAlertRule (Entity _ rule) metrics = do
    -- This is a placeholder implementation
    -- In a real system, this would:
    -- 1. Parse the rule thresholds
    -- 2. Compare metrics against thresholds
    -- 3. Generate alerts if thresholds are exceeded
    let shouldAlert = False  -- Replace with actual evaluation logic
    if shouldAlert
        then do
            let alertTitle = "Alert Rule: " <> alertRuleName rule
                alertMessage = "Threshold exceeded for " <> alertRuleName rule
                alertMetadata = object
                    [ "rule_id" .= alertRuleRuleId rule
                    , "metrics" .= metrics
                    , "thresholds" .= alertRuleThresholds rule
                    ]
            createAlert alertTitle alertMessage Warning "alert_rule" (Just alertMetadata)
        else return Nothing

-- Helper functions for generating IDs
generateAlertId :: Text -> UTCTime -> Text
generateAlertId title timestamp =
    "alt_" <> Text.filter isAllowed title <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateRuleId :: Text -> UTCTime -> Text
generateRuleId name timestamp =
    "alr_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
