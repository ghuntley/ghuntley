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

module Gerrit.Models.ProjectTemplate where

import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Template visibility level
data TemplateVisibility =
    GlobalTemplate       -- ^ Available to all organizations
  | EnterpriseTemplate  -- ^ Available within an enterprise
  | OrganizationTemplate -- ^ Available within an organization
  deriving (Show, Read, Eq, Generic)

derivePersistField "TemplateVisibility"

instance ToJSON TemplateVisibility
instance FromJSON TemplateVisibility

-- | Template configuration options
data TemplateConfig = TemplateConfig
  { branchProtectionRules :: Value  -- ^ Default branch protection settings
  , submissionRules :: Value        -- ^ Default submission requirements
  , reviewLabels :: Value          -- ^ Default review labels and voting ranges
  , webhookConfigs :: Value        -- ^ Default webhook configurations
  , cicdConfig :: Value           -- ^ Default CI/CD settings
  , accessControl :: Value        -- ^ Default access control settings
  } deriving (Show, Generic)

instance ToJSON TemplateConfig
instance FromJSON TemplateConfig

derivePersistField "TemplateConfig"

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
ProjectTemplate
    templateId Text
    name Text
    description Text Maybe
    visibility TemplateVisibility
    enterpriseId Text Maybe        -- ^ For enterprise-specific templates
    organizationId Text Maybe      -- ^ For organization-specific templates
    config TemplateConfig
    parentTemplateId Text Maybe    -- ^ For template inheritance
    isDefault Bool default=false
    metadata Value Maybe
    createdBy Text
    created UTCTime
    updated UTCTime
    UniqueTemplateId templateId
    UniqueTemplateName name visibility enterpriseId organizationId
    deriving Show Eq Generic
|]

instance ToJSON (Entity ProjectTemplate)
instance ToJSON ProjectTemplate
instance FromJSON ProjectTemplate
