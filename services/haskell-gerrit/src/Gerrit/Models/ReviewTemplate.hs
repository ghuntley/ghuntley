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

module Gerrit.Models.ReviewTemplate
    ( -- * Types
      ReviewTemplate(..)
    , TemplateId
    , TemplateScope(..)
    , TemplateType(..)
    , TemplateRule(..)
    , RuleType(..)
    , RuleSeverity(..)
      -- * Operations
    , createTemplate
    , updateTemplate
    , deleteTemplate
    , getTemplateById
    , listTemplates
    , addTemplateRule
    , updateTemplateRule
    , removeTemplateRule
    , getTemplateRules
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

-- | Template scope
data TemplateScope
    = GlobalScope      -- ^ Available to all users
    | OrganizationScope Text  -- ^ Available within an organization
    | ProjectScope Text       -- ^ Available within a project
    | TeamScope Text         -- ^ Available within a team
    deriving (Show, Read, Eq, Generic)
derivePersistField "TemplateScope"

-- | Template type
data TemplateType
    = StandardTemplate    -- ^ Standard review template
    | SecurityTemplate    -- ^ Security-focused review template
    | PerformanceTemplate -- ^ Performance-focused review template
    | DocumentationTemplate -- ^ Documentation-focused review template
    | CustomTemplate Text  -- ^ Custom template type
    deriving (Show, Read, Eq, Generic)
derivePersistField "TemplateType"

-- | Rule type
data RuleType
    = ManualCheck Text    -- ^ Manual check with description
    | AutomatedCheck Text -- ^ Automated check with script/command
    | RequiredLabel Text  -- ^ Required review label
    | BlockingLabel Text  -- ^ Blocking review label
    | CustomRule Text     -- ^ Custom rule type
    deriving (Show, Read, Eq, Generic)
derivePersistField "RuleType"

-- | Rule severity
data RuleSeverity
    = Critical   -- ^ Must be addressed
    | Major      -- ^ Should be addressed
    | Minor      -- ^ Nice to address
    | Suggestion -- ^ Optional to address
    deriving (Show, Read, Eq, Ord, Generic)
derivePersistField "RuleSeverity"

-- | Define the ReviewTemplate entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
ReviewTemplate
    templateId Text
    name Text
    description Text Maybe
    scope TemplateScope
    templateType TemplateType
    ownerId Text
    isDefault Bool default=false
    isEnabled Bool default=true
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueTemplateId templateId
    UniqueTemplateName name scope
    deriving Show Eq Generic

TemplateRule
    ruleId Text
    templateId Text
    name Text
    description Text
    ruleType RuleType
    severity RuleSeverity
    isRequired Bool default=false
    isEnabled Bool default=true
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueRuleId ruleId
    Foreign ReviewTemplate templateId References reviewTemplates OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new review template
createTemplate :: MonadIO m
               => Text  -- ^ Name
               -> Maybe Text  -- ^ Description
               -> TemplateScope  -- ^ Scope
               -> TemplateType  -- ^ Template type
               -> Text  -- ^ Owner ID
               -> Bool  -- ^ Is default
               -> Maybe Value  -- ^ Additional metadata
               -> m (Entity ReviewTemplate)
createTemplate name desc scope templateType ownerId isDefault metadata = do
    now <- liftIO getCurrentTime
    let templateId = generateTemplateId name scope now
    let template = ReviewTemplate
            { reviewTemplateTemplateId = templateId
            , reviewTemplateName = name
            , reviewTemplateDescription = desc
            , reviewTemplateScope = scope
            , reviewTemplateTemplateType = templateType
            , reviewTemplateOwnerId = ownerId
            , reviewTemplateIsDefault = isDefault
            , reviewTemplateIsEnabled = True
            , reviewTemplateMetadata = metadata
            , reviewTemplateCreated = now
            , reviewTemplateUpdated = now
            }
    runDB $ insertEntity template

-- | Update a review template
updateTemplate :: MonadIO m
               => Entity ReviewTemplate
               -> Text  -- ^ Name
               -> Maybe Text  -- ^ Description
               -> TemplateType  -- ^ Template type
               -> Bool  -- ^ Is default
               -> Bool  -- ^ Is enabled
               -> Maybe Value  -- ^ Additional metadata
               -> m (Entity ReviewTemplate)
updateTemplate (Entity key template) name desc templateType isDefault isEnabled metadata = do
    now <- liftIO getCurrentTime
    let updatedTemplate = template
            { reviewTemplateName = name
            , reviewTemplateDescription = desc
            , reviewTemplateTemplateType = templateType
            , reviewTemplateIsDefault = isDefault
            , reviewTemplateIsEnabled = isEnabled
            , reviewTemplateMetadata = metadata
            , reviewTemplateUpdated = now
            }
    runDB $ replace key updatedTemplate
    return $ Entity key updatedTemplate

-- | Delete a review template
deleteTemplate :: MonadIO m
               => Entity ReviewTemplate
               -> m ()
deleteTemplate (Entity key _) =
    runDB $ delete key

-- | Get template by ID
getTemplateById :: MonadIO m
                => Text  -- ^ Template ID
                -> m (Maybe (Entity ReviewTemplate))
getTemplateById templateId =
    runDB $ getBy $ UniqueTemplateId templateId

-- | List templates with filtering
listTemplates :: MonadIO m
              => Maybe TemplateScope  -- ^ Filter by scope
              -> Maybe TemplateType   -- ^ Filter by type
              -> Bool                 -- ^ Only enabled templates
              -> Int                  -- ^ Offset
              -> Int                  -- ^ Limit
              -> m [Entity ReviewTemplate]
listTemplates mScope mType onlyEnabled offset limit = do
    let filters = concat
            [ maybe [] (\s -> [ReviewTemplateScope ==. s]) mScope
            , maybe [] (\t -> [ReviewTemplateTemplateType ==. t]) mType
            , [ReviewTemplateIsEnabled ==. True | onlyEnabled]
            ]
    runDB $ selectList filters [Asc ReviewTemplateName, OffsetBy offset, LimitTo limit]

-- | Add a rule to a template
addTemplateRule :: MonadIO m
                => Text  -- ^ Template ID
                -> Text  -- ^ Rule name
                -> Text  -- ^ Rule description
                -> RuleType  -- ^ Rule type
                -> RuleSeverity  -- ^ Rule severity
                -> Bool  -- ^ Is required
                -> Maybe Value  -- ^ Additional metadata
                -> m (Entity TemplateRule)
addTemplateRule templateId name desc ruleType severity isRequired metadata = do
    now <- liftIO getCurrentTime
    let ruleId = generateRuleId templateId name now
    let rule = TemplateRule
            { templateRuleRuleId = ruleId
            , templateRuleTemplateId = templateId
            , templateRuleName = name
            , templateRuleDescription = desc
            , templateRuleRuleType = ruleType
            , templateRuleSeverity = severity
            , templateRuleIsRequired = isRequired
            , templateRuleIsEnabled = True
            , templateRuleMetadata = metadata
            , templateRuleCreated = now
            , templateRuleUpdated = now
            }
    runDB $ insertEntity rule

-- | Update a template rule
updateTemplateRule :: MonadIO m
                   => Entity TemplateRule
                   -> Text  -- ^ Rule name
                   -> Text  -- ^ Rule description
                   -> RuleType  -- ^ Rule type
                   -> RuleSeverity  -- ^ Rule severity
                   -> Bool  -- ^ Is required
                   -> Bool  -- ^ Is enabled
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity TemplateRule)
updateTemplateRule (Entity key rule) name desc ruleType severity isRequired isEnabled metadata = do
    now <- liftIO getCurrentTime
    let updatedRule = rule
            { templateRuleName = name
            , templateRuleDescription = desc
            , templateRuleRuleType = ruleType
            , templateRuleSeverity = severity
            , templateRuleIsRequired = isRequired
            , templateRuleIsEnabled = isEnabled
            , templateRuleMetadata = metadata
            , templateRuleUpdated = now
            }
    runDB $ replace key updatedRule
    return $ Entity key updatedRule

-- | Remove a rule from a template
removeTemplateRule :: MonadIO m
                   => Entity TemplateRule
                   -> m ()
removeTemplateRule (Entity key _) =
    runDB $ delete key

-- | Get rules for a template
getTemplateRules :: MonadIO m
                 => Text  -- ^ Template ID
                 -> m [Entity TemplateRule]
getTemplateRules templateId =
    runDB $ selectList [TemplateRuleTemplateId ==. templateId] [Asc TemplateRuleSeverity]

-- Helper functions for generating IDs
generateTemplateId :: Text -> TemplateScope -> UTCTime -> Text
generateTemplateId name scope timestamp =
    "tmpl_" <> Text.filter isAllowed name <> "_" <> scopeStr <> "_" <> formatTime timestamp
  where
    scopeStr = case scope of
        GlobalScope -> "global"
        OrganizationScope orgId -> "org_" <> orgId
        ProjectScope projId -> "proj_" <> projId
        TeamScope teamId -> "team_" <> teamId
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateRuleId :: Text -> Text -> UTCTime -> Text
generateRuleId templateId name timestamp =
    "rule_" <> Text.filter isAllowed templateId <> "_" <> Text.filter isAllowed name <>
    "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
