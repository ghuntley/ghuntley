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

module Gerrit.Models.AlertRule
    ( -- * Types
      AlertRule(..)
    , AlertRuleId
    , AlertCondition(..)
    , AlertAction(..)
    , AlertTarget(..)
      -- * Operations
    , createAlertRule
    , updateAlertRule
    , getAlertRuleById
    , listAlertRules
    , enableAlertRule
    , disableAlertRule
    , deleteAlertRule
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
import Gerrit.Models.Alert (Alert)

-- | Alert condition type
data AlertCondition
    = ThresholdCondition
        { metric :: Text
        , operator :: Text
        , threshold :: Double
        }
    | PatternCondition
        { pattern :: Text
        , matchType :: Text
        }
    | CompositeCondition
        { conditions :: [AlertCondition]
        , combinator :: Text
        }
    deriving (Show, Read, Eq, Generic)
derivePersistField "AlertCondition"

-- | Alert action type
data AlertAction
    = NotifyAction
        { channels :: [Text]
        , template :: Text
        }
    | WebhookAction
        { url :: Text
        , method :: Text
        , headers :: Value
        }
    | AutomatedAction
        { actionType :: Text
        , parameters :: Value
        }
    deriving (Show, Read, Eq, Generic)
derivePersistField "AlertAction"

-- | Alert target type
data AlertTarget
    = GlobalTarget
    | OrganizationTarget Text
    | ProjectTarget Text
    | UserTarget Text
    | CustomTarget Text Value
    deriving (Show, Read, Eq, Generic)
derivePersistField "AlertTarget"

-- | Define the alert rule entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
AlertRule
    ruleId Text
    name Text
    description Text
    condition AlertCondition
    actions [AlertAction]
    target AlertTarget
    enabled Bool
    severity Text
    cooldown Int  -- Cooldown period in seconds
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueAlertRuleId ruleId
    UniqueAlertRuleName name
    deriving Show Eq Generic
|]

-- | Create alert rule
createAlertRule :: MonadIO m
                => Text  -- ^ Name
                -> Text  -- ^ Description
                -> AlertCondition  -- ^ Condition
                -> [AlertAction]  -- ^ Actions
                -> AlertTarget  -- ^ Target
                -> Text  -- ^ Severity
                -> Int  -- ^ Cooldown period
                -> Maybe Value  -- ^ Additional metadata
                -> m (Entity AlertRule)
createAlertRule name description condition actions target severity cooldown metadata = do
    now <- liftIO getCurrentTime
    let ruleId = generateRuleId name now
    let rule = AlertRule
            { alertRuleRuleId = ruleId
            , alertRuleName = name
            , alertRuleDescription = description
            , alertRuleCondition = condition
            , alertRuleActions = actions
            , alertRuleTarget = target
            , alertRuleEnabled = True
            , alertRuleSeverity = severity
            , alertRuleCooldown = cooldown
            , alertRuleMetadata = metadata
            , alertRuleCreated = now
            , alertRuleUpdated = now
            }
    runDB $ insertEntity rule

-- | Update alert rule
updateAlertRule :: MonadIO m
                => Entity AlertRule
                -> Text  -- ^ Name
                -> Text  -- ^ Description
                -> AlertCondition  -- ^ Condition
                -> [AlertAction]  -- ^ Actions
                -> AlertTarget  -- ^ Target
                -> Text  -- ^ Severity
                -> Int  -- ^ Cooldown period
                -> Maybe Value  -- ^ Additional metadata
                -> m (Entity AlertRule)
updateAlertRule (Entity key rule) name description condition actions target severity cooldown metadata = do
    now <- liftIO getCurrentTime
    let updatedRule = rule
            { alertRuleName = name
            , alertRuleDescription = description
            , alertRuleCondition = condition
            , alertRuleActions = actions
            , alertRuleTarget = target
            , alertRuleSeverity = severity
            , alertRuleCooldown = cooldown
            , alertRuleMetadata = metadata
            , alertRuleUpdated = now
            }
    runDB $ replace key updatedRule
    return $ Entity key updatedRule

-- | Get alert rule by ID
getAlertRuleById :: MonadIO m
                 => Text  -- ^ Rule ID
                 -> m (Maybe (Entity AlertRule))
getAlertRuleById ruleId =
    runDB $ getBy $ UniqueAlertRuleId ruleId

-- | List alert rules
listAlertRules :: MonadIO m
               => Maybe Text  -- ^ Target filter
               -> Maybe Text  -- ^ Severity filter
               -> Bool  -- ^ Only enabled rules
               -> Int  -- ^ Offset
               -> Int  -- ^ Limit
               -> m [Entity AlertRule]
listAlertRules mTarget mSeverity onlyEnabled offset limit = do
    let filters = [AlertRuleEnabled ==. True | onlyEnabled] ++
                 maybe [] (\s -> [AlertRuleSeverity ==. s]) mSeverity
    runDB $ selectList filters [Asc AlertRuleName, OffsetBy offset, LimitTo limit]

-- | Enable alert rule
enableAlertRule :: MonadIO m
                => Entity AlertRule
                -> m (Entity AlertRule)
enableAlertRule (Entity key rule) = do
    now <- liftIO getCurrentTime
    let updatedRule = rule
            { alertRuleEnabled = True
            , alertRuleUpdated = now
            }
    runDB $ replace key updatedRule
    return $ Entity key updatedRule

-- | Disable alert rule
disableAlertRule :: MonadIO m
                 => Entity AlertRule
                 -> m (Entity AlertRule)
disableAlertRule (Entity key rule) = do
    now <- liftIO getCurrentTime
    let updatedRule = rule
            { alertRuleEnabled = False
            , alertRuleUpdated = now
            }
    runDB $ replace key updatedRule
    return $ Entity key updatedRule

-- | Delete alert rule
deleteAlertRule :: MonadIO m
                => Entity AlertRule
                -> m ()
deleteAlertRule (Entity key _) =
    runDB $ delete key

-- Helper functions for generating IDs
generateRuleId :: Text -> UTCTime -> Text
generateRuleId name timestamp =
    "ar_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
