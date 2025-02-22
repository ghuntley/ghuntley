{-|
Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Gerrit.Models.ReviewConfig where

import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Review label configuration
data ReviewLabel = ReviewLabel
  { labelName :: Text
  , description :: Maybe Text
  , values :: [(Int, Text)]  -- ^ Value and description pairs (e.g. -2="Do not submit")
  , copyScore :: Bool        -- ^ Whether to copy scores on new patch sets
  , defaultValue :: Int      -- ^ Default value for new reviews
  , function :: Maybe Text   -- ^ Optional function name for automated scoring
  } deriving (Show, Generic)

instance ToJSON ReviewLabel
instance FromJSON ReviewLabel

derivePersistField "ReviewLabel"

-- | Submit requirement type
data SubmitRequirement =
    LabelRequirement
      { labelName :: Text
      , minValue :: Int
      , maxValue :: Int
      }
  | CustomRequirement
      { name :: Text
      , description :: Text
      , function :: Text  -- ^ Function name to evaluate requirement
      , parameters :: Value  -- ^ Parameters for the function
      }
  deriving (Show, Generic)

instance ToJSON SubmitRequirement
instance FromJSON SubmitRequirement

derivePersistField "SubmitRequirement"

-- | Review workflow scope
data ReviewScope =
    ProjectScope Text      -- ^ Specific to a project
  | OrganizationScope Text -- ^ Applies to all projects in an organization
  | EnterpriseScope Text   -- ^ Applies to all projects in an enterprise
  | GlobalScope           -- ^ Global default configuration
  deriving (Show, Generic)

instance ToJSON ReviewScope
instance FromJSON ReviewScope

derivePersistField "ReviewScope"

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
ReviewConfig
    configId Text
    name Text
    description Text Maybe
    scope ReviewScope
    labels [ReviewLabel]
    submitRequirements [SubmitRequirement]
    autoSubmitConfig Value Maybe  -- ^ Configuration for automatic submission
    ciRequirements Value Maybe    -- ^ CI/CD requirements before submission
    reviewerSuggestions Value Maybe -- ^ Configuration for reviewer suggestions
    isDefault Bool default=false
    metadata Value Maybe
    createdBy Text
    created UTCTime
    updated UTCTime
    UniqueConfigId configId
    UniqueConfigName name scope
    deriving Show Eq Generic

ReviewConfigHistory
    historyId Text
    configId Text
    changeType Text  -- ^ Created, Updated, Deleted
    oldValue Value Maybe
    newValue Value
    reason Text Maybe
    changedBy Text
    timestamp UTCTime
    UniqueHistoryId historyId
    Foreign ReviewConfig configId References review_configs OnDeleteCascade
    deriving Show Eq Generic
|]

instance ToJSON (Entity ReviewConfig)
instance ToJSON ReviewConfig
instance FromJSON ReviewConfig

instance ToJSON (Entity ReviewConfigHistory)
instance ToJSON ReviewConfigHistory
instance FromJSON ReviewConfigHistory
