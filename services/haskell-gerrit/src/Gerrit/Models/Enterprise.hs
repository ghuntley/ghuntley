{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

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

module Gerrit.Models.Enterprise
    ( -- * Types
      Enterprise(..)
    , EnterprisePlan(..)
    , EnterpriseStatus(..)
    , BrandingConfig(..)
    , EnterpriseBilling(..)
    , EnterpriseMetric(..)
    , EnterpriseAuditLog(..)
    , EnterpriseFeature(..)
    , EnterpriseApiKey(..)
    , EnterpriseWebhook(..)
    , EnterpriseIntegration(..)
      -- * Operations
    , createEnterprise
    , updateEnterprise
    , getEnterpriseById
    , listEnterprises
    , updateEnterprisePlan
    , updateBranding
    , updateSettings
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Enterprise plan types
data EnterprisePlan
    = FreePlan
    | StarterPlan
    | ProPlan
    | EnterprisePlan
    | CustomPlan Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "EnterprisePlan"

-- | Enterprise status
data EnterpriseStatus
    = Active
    | Suspended
    | Deactivated
    | TrialPeriod
    | PendingPayment
    deriving (Show, Read, Eq, Generic)
derivePersistField "EnterpriseStatus"

-- | Branding configuration
data BrandingConfig = BrandingConfig
    { logoUrl :: Maybe Text
    , primaryColor :: Maybe Text
    , secondaryColor :: Maybe Text
    , customCss :: Maybe Text
    } deriving (Show, Eq, Generic)
instance ToJSON BrandingConfig
instance FromJSON BrandingConfig

-- | Define the Enterprise entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Enterprise
    enterpriseId Text
    name Text
    domain Text
    plan EnterprisePlan
    status EnterpriseStatus default=Active
    maxUsers Int Maybe
    maxProjects Int Maybe
    maxStorage Int Maybe
    branding Value Maybe
    settings Value
    metadata Value Maybe
    trialEndsAt UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueEnterpriseId enterpriseId
    UniqueDomain domain
    deriving Show Eq Generic

EnterpriseBilling
    billingId Text
    enterpriseId Text
    planId Text
    amount Rational
    currency Text
    billingCycle Text
    nextBillingDate UTCTime
    paymentMethod Value Maybe
    billingAddress Value Maybe
    taxInfo Value Maybe
    created UTCTime
    updated UTCTime
    UniqueBillingId billingId
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    deriving Show Eq Generic

EnterpriseMetric
    metricId Text
    enterpriseId Text
    metricType Text
    value Int
    timestamp UTCTime
    UniqueMetricId metricId
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    deriving Show Eq Generic

EnterpriseAuditLog
    logId Text
    enterpriseId Text
    action Text
    actorId Text
    details Value
    ipAddress Text Maybe
    userAgent Text Maybe
    created UTCTime
    UniqueLogId logId
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    deriving Show Eq Generic

EnterpriseFeature
    featureId Text
    enterpriseId Text
    featureName Text
    enabled Bool default=True
    configuration Value Maybe
    created UTCTime
    updated UTCTime
    UniqueFeatureId featureId
    UniqueEnterpriseFeature enterpriseId featureName
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    deriving Show Eq Generic

EnterpriseApiKey
    keyId Text
    enterpriseId Text
    name Text
    keyHash Text
    scopes [Text]
    expiresAt UTCTime Maybe
    lastUsedAt UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueKeyId keyId
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    deriving Show Eq Generic

EnterpriseWebhook
    webhookId Text
    enterpriseId Text
    url Text
    events [Text]
    secretHash Text
    active Bool default=True
    sslVerify Bool default=True
    created UTCTime
    updated UTCTime
    UniqueWebhookId webhookId
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    deriving Show Eq Generic

EnterpriseIntegration
    integrationId Text
    enterpriseId Text
    integrationType Text
    configuration Value
    credentials Value Maybe
    active Bool default=True
    healthStatus Text Maybe
    lastSyncAt UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueIntegrationId integrationId
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new enterprise
createEnterprise :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Name
                -> Text  -- ^ Domain
                -> EnterprisePlan  -- ^ Plan
                -> Maybe Int  -- ^ Max users
                -> Maybe Int  -- ^ Max projects
                -> Maybe Int  -- ^ Max storage
                -> Value  -- ^ Settings
                -> Maybe Value  -- ^ Metadata
                -> Maybe UTCTime  -- ^ Trial end date
                -> m (Entity Enterprise)
createEnterprise pool name domain plan maxUsers maxProjects maxStorage settings metadata trialEndsAt = do
    now <- liftIO getCurrentTime
    let enterpriseId = generateEnterpriseId name domain now
    let enterprise = Enterprise
            { enterpriseEnterpriseId = enterpriseId
            , enterpriseName = name
            , enterpriseDomain = domain
            , enterprisePlan = plan
            , enterpriseStatus = Active
            , enterpriseMaxUsers = maxUsers
            , enterpriseMaxProjects = maxProjects
            , enterpriseMaxStorage = maxStorage
            , enterpriseBranding = Nothing
            , enterpriseSettings = settings
            , enterpriseMetadata = metadata
            , enterpriseTrialEndsAt = trialEndsAt
            , enterpriseCreated = now
            , enterpriseUpdated = now
            }
    runSqlPool (insertEntity enterprise) pool

-- | Update an enterprise
updateEnterprise :: MonadIO m
                => ConnectionPool
                -> Entity Enterprise
                -> Text  -- ^ Name
                -> Text  -- ^ Domain
                -> EnterpriseStatus  -- ^ Status
                -> Value  -- ^ Settings
                -> Maybe Value  -- ^ Metadata
                -> m (Entity Enterprise)
updateEnterprise pool (Entity key enterprise) name domain status settings metadata = do
    now <- liftIO getCurrentTime
    let updatedEnterprise = enterprise
            { enterpriseName = name
            , enterpriseDomain = domain
            , enterpriseStatus = status
            , enterpriseSettings = settings
            , enterpriseMetadata = metadata
            , enterpriseUpdated = now
            }
    runSqlPool (replace key updatedEnterprise) pool
    return $ Entity key updatedEnterprise

-- | Get enterprise by ID
getEnterpriseById :: MonadIO m
                  => ConnectionPool
                  -> Text  -- ^ Enterprise ID
                  -> m (Maybe (Entity Enterprise))
getEnterpriseById pool enterpriseId =
    runSqlPool (getBy $ UniqueEnterpriseId enterpriseId) pool

-- | List enterprises with filtering
listEnterprises :: MonadIO m
                => ConnectionPool
                -> Maybe EnterprisePlan  -- ^ Filter by plan
                -> Maybe EnterpriseStatus  -- ^ Filter by status
                -> Int  -- ^ Offset
                -> Int  -- ^ Limit
                -> m [Entity Enterprise]
listEnterprises pool mPlan mStatus offset limit = do
    let filters = concat
            [ maybe [] (\plan -> [EnterprisePlan ==. plan]) mPlan
            , maybe [] (\status -> [EnterpriseStatus ==. status]) mStatus
            ]
    runSqlPool (selectList filters [Desc EnterpriseCreated, OffsetBy offset, LimitTo limit]) pool

-- | Update enterprise plan
updateEnterprisePlan :: MonadIO m
                    => ConnectionPool
                    -> Entity Enterprise
                    -> EnterprisePlan  -- ^ New plan
                    -> Maybe Int  -- ^ New max users
                    -> Maybe Int  -- ^ New max projects
                    -> Maybe Int  -- ^ New max storage
                    -> m (Entity Enterprise)
updateEnterprisePlan pool (Entity key enterprise) plan maxUsers maxProjects maxStorage = do
    now <- liftIO getCurrentTime
    let updatedEnterprise = enterprise
            { enterprisePlan = plan
            , enterpriseMaxUsers = maxUsers
            , enterpriseMaxProjects = maxProjects
            , enterpriseMaxStorage = maxStorage
            , enterpriseUpdated = now
            }
    runSqlPool (replace key updatedEnterprise) pool
    return $ Entity key updatedEnterprise

-- | Update enterprise branding
updateBranding :: MonadIO m
               => ConnectionPool
               -> Entity Enterprise
               -> Maybe Value  -- ^ New branding config
               -> m (Entity Enterprise)
updateBranding pool (Entity key enterprise) branding = do
    now <- liftIO getCurrentTime
    let updatedEnterprise = enterprise
            { enterpriseBranding = branding
            , enterpriseUpdated = now
            }
    runSqlPool (replace key updatedEnterprise) pool
    return $ Entity key updatedEnterprise

-- | Update enterprise settings
updateSettings :: MonadIO m
               => ConnectionPool
               -> Entity Enterprise
               -> Value  -- ^ New settings
               -> m (Entity Enterprise)
updateSettings pool (Entity key enterprise) settings = do
    now <- liftIO getCurrentTime
    let updatedEnterprise = enterprise
            { enterpriseSettings = settings
            , enterpriseUpdated = now
            }
    runSqlPool (replace key updatedEnterprise) pool
    return $ Entity key updatedEnterprise

-- Helper functions for generating IDs
generateEnterpriseId :: Text -> Text -> UTCTime -> Text
generateEnterpriseId name domain timestamp =
    "ent_" <> Text.filter isAllowed name <> "_" <> Text.filter isAllowed domain <>
    "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
    formatTime = Text.pack . show
