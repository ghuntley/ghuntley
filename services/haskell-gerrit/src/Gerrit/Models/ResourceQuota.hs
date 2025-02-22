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

module Gerrit.Models.ResourceQuota
    ( -- * Types
      ResourceType(..)
    , QuotaStatus(..)
    , AlertLevel(..)
    , ResourceQuota(..)
    , ResourceQuotaId
    , QuotaUsage(..)
    , QuotaUsageId
    , QuotaAlert(..)
    , QuotaAlertId
      -- * Operations
    , createResourceQuota
    , updateResourceQuota
    , getResourceQuotaById
    , listResourceQuotas
    , recordQuotaUsage
    , getQuotaUsageById
    , listQuotaUsage
    , createQuotaAlert
    , updateQuotaAlert
    , getQuotaAlertById
    , listQuotaAlerts
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
import Gerrit.Models.Organization (Organization)

-- | Resource type
data ResourceType
    = StorageQuota
    | BandwidthQuota
    | ComputeQuota
    | UserQuota
    | ProjectQuota
    | ApiQuota
    | CustomQuota Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "ResourceType"

-- | Quota status
data QuotaStatus
    = Active
    | Warning
    | Critical
    | Exceeded
    | Suspended
    deriving (Show, Read, Eq, Generic)
derivePersistField "QuotaStatus"

-- | Alert level
data AlertLevel
    = Info
    | Warning
    | Error
    | Critical
    deriving (Show, Read, Eq, Generic)
derivePersistField "AlertLevel"

-- | Define the resource quota entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
ResourceQuota
    quotaId Text
    orgId Text
    resourceType ResourceType
    name Text
    description Text Maybe
    softLimit Int64
    hardLimit Int64
    currentUsage Int64
    status QuotaStatus
    alertThreshold Int  -- Percentage
    enabled Bool
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueQuotaId quotaId
    UniqueOrgResource orgId resourceType
    Foreign Organization orgId References organizations OnDeleteCascade
    deriving Show Eq Generic

QuotaUsage
    usageId Text
    quotaId Text
    amount Int64
    operation Text
    userId Text Maybe
    projectId Text Maybe
    metadata Value Maybe
    timestamp UTCTime
    UniqueUsageId usageId
    Foreign ResourceQuota quotaId References resourceQuotas OnDeleteCascade
    deriving Show Eq Generic

QuotaAlert
    alertId Text
    quotaId Text
    level AlertLevel
    message Text
    threshold Int64
    currentValue Int64
    acknowledged Bool
    acknowledgedBy Text Maybe
    acknowledgedAt UTCTime Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueAlertId alertId
    Foreign ResourceQuota quotaId References resourceQuotas OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create resource quota
createResourceQuota :: MonadIO m
                   => Text  -- ^ Organization ID
                   -> ResourceType  -- ^ Resource type
                   -> Text  -- ^ Name
                   -> Maybe Text  -- ^ Description
                   -> Int64  -- ^ Soft limit
                   -> Int64  -- ^ Hard limit
                   -> Int  -- ^ Alert threshold percentage
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity ResourceQuota)
createResourceQuota orgId rType name description softLimit hardLimit threshold metadata = do
    now <- liftIO getCurrentTime
    let quotaId = generateQuotaId orgId rType now
    let quota = ResourceQuota
            { resourceQuotaQuotaId = quotaId
            , resourceQuotaOrgId = orgId
            , resourceQuotaResourceType = rType
            , resourceQuotaName = name
            , resourceQuotaDescription = description
            , resourceQuotaSoftLimit = softLimit
            , resourceQuotaHardLimit = hardLimit
            , resourceQuotaCurrentUsage = 0
            , resourceQuotaStatus = Active
            , resourceQuotaAlertThreshold = threshold
            , resourceQuotaEnabled = True
            , resourceQuotaMetadata = metadata
            , resourceQuotaCreated = now
            , resourceQuotaUpdated = now
            }
    runDB $ insertEntity quota

-- | Update resource quota
updateResourceQuota :: MonadIO m
                   => Entity ResourceQuota
                   -> Text  -- ^ Name
                   -> Maybe Text  -- ^ Description
                   -> Int64  -- ^ Soft limit
                   -> Int64  -- ^ Hard limit
                   -> Int  -- ^ Alert threshold percentage
                   -> Bool  -- ^ Enabled
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity ResourceQuota)
updateResourceQuota (Entity key quota) name description softLimit hardLimit threshold enabled metadata = do
    now <- liftIO getCurrentTime
    let updatedQuota = quota
            { resourceQuotaName = name
            , resourceQuotaDescription = description
            , resourceQuotaSoftLimit = softLimit
            , resourceQuotaHardLimit = hardLimit
            , resourceQuotaAlertThreshold = threshold
            , resourceQuotaEnabled = enabled
            , resourceQuotaMetadata = metadata
            , resourceQuotaUpdated = now
            }
    runDB $ replace key updatedQuota
    return $ Entity key updatedQuota

-- | Get resource quota by ID
getResourceQuotaById :: MonadIO m
                    => Text  -- ^ Quota ID
                    -> m (Maybe (Entity ResourceQuota))
getResourceQuotaById quotaId =
    runDB $ getBy $ UniqueQuotaId quotaId

-- | List resource quotas
listResourceQuotas :: MonadIO m
                   => Text  -- ^ Organization ID
                   -> Maybe ResourceType  -- ^ Resource type filter
                   -> Maybe QuotaStatus  -- ^ Status filter
                   -> Bool  -- ^ Only enabled quotas
                   -> Int  -- ^ Offset
                   -> Int  -- ^ Limit
                   -> m [Entity ResourceQuota]
listResourceQuotas orgId mType mStatus onlyEnabled offset limit = do
    let filters = (ResourceQuotaOrgId ==. orgId) :
                 maybe [] (\t -> [ResourceQuotaResourceType ==. t]) mType ++
                 maybe [] (\s -> [ResourceQuotaStatus ==. s]) mStatus ++
                 [ResourceQuotaEnabled ==. True | onlyEnabled]
    runDB $ selectList filters [Asc ResourceQuotaName, OffsetBy offset, LimitTo limit]

-- | Record quota usage
recordQuotaUsage :: MonadIO m
                 => Text  -- ^ Quota ID
                 -> Int64  -- ^ Amount
                 -> Text  -- ^ Operation
                 -> Maybe Text  -- ^ User ID
                 -> Maybe Text  -- ^ Project ID
                 -> Maybe Value  -- ^ Additional metadata
                 -> m (Entity QuotaUsage)
recordQuotaUsage quotaId amount operation userId projectId metadata = do
    now <- liftIO getCurrentTime
    let usageId = generateUsageId quotaId now
    let usage = QuotaUsage
            { quotaUsageUsageId = usageId
            , quotaUsageQuotaId = quotaId
            , quotaUsageAmount = amount
            , quotaUsageOperation = operation
            , quotaUsageUserId = userId
            , quotaUsageProjectId = projectId
            , quotaUsageMetadata = metadata
            , quotaUsageTimestamp = now
            }
    runDB $ insertEntity usage

-- | Get quota usage by ID
getQuotaUsageById :: MonadIO m
                  => Text  -- ^ Usage ID
                  -> m (Maybe (Entity QuotaUsage))
getQuotaUsageById usageId =
    runDB $ getBy $ UniqueUsageId usageId

-- | List quota usage
listQuotaUsage :: MonadIO m
               => Text  -- ^ Quota ID
               -> Maybe Text  -- ^ User ID filter
               -> Maybe Text  -- ^ Project ID filter
               -> UTCTime  -- ^ Start time
               -> UTCTime  -- ^ End time
               -> Int  -- ^ Offset
               -> Int  -- ^ Limit
               -> m [Entity QuotaUsage]
listQuotaUsage quotaId mUserId mProjectId start end offset limit = do
    let filters = [ QuotaUsageQuotaId ==. quotaId
                 , QuotaUsageTimestamp >=. start
                 , QuotaUsageTimestamp <=. end
                 ] ++
                 maybe [] (\uid -> [QuotaUsageUserId ==. Just uid]) mUserId ++
                 maybe [] (\pid -> [QuotaUsageProjectId ==. Just pid]) mProjectId
    runDB $ selectList filters [Desc QuotaUsageTimestamp, OffsetBy offset, LimitTo limit]

-- | Create quota alert
createQuotaAlert :: MonadIO m
                 => Text  -- ^ Quota ID
                 -> AlertLevel  -- ^ Alert level
                 -> Text  -- ^ Message
                 -> Int64  -- ^ Threshold
                 -> Int64  -- ^ Current value
                 -> Maybe Value  -- ^ Additional metadata
                 -> m (Entity QuotaAlert)
createQuotaAlert quotaId level message threshold currentValue metadata = do
    now <- liftIO getCurrentTime
    let alertId = generateAlertId quotaId now
    let alert = QuotaAlert
            { quotaAlertAlertId = alertId
            , quotaAlertQuotaId = quotaId
            , quotaAlertLevel = level
            , quotaAlertMessage = message
            , quotaAlertThreshold = threshold
            , quotaAlertCurrentValue = currentValue
            , quotaAlertAcknowledged = False
            , quotaAlertAcknowledgedBy = Nothing
            , quotaAlertAcknowledgedAt = Nothing
            , quotaAlertMetadata = metadata
            , quotaAlertCreated = now
            , quotaAlertUpdated = now
            }
    runDB $ insertEntity alert

-- | Update quota alert
updateQuotaAlert :: MonadIO m
                 => Entity QuotaAlert
                 -> Bool  -- ^ Acknowledged
                 -> Maybe Text  -- ^ Acknowledged by
                 -> Maybe Value  -- ^ Additional metadata
                 -> m (Entity QuotaAlert)
updateQuotaAlert (Entity key alert) acknowledged acknowledgedBy metadata = do
    now <- liftIO getCurrentTime
    let updatedAlert = alert
            { quotaAlertAcknowledged = acknowledged
            , quotaAlertAcknowledgedBy = acknowledgedBy
            , quotaAlertAcknowledgedAt = if acknowledged then Just now else Nothing
            , quotaAlertMetadata = metadata
            , quotaAlertUpdated = now
            }
    runDB $ replace key updatedAlert
    return $ Entity key updatedAlert

-- | Get quota alert by ID
getQuotaAlertById :: MonadIO m
                  => Text  -- ^ Alert ID
                  -> m (Maybe (Entity QuotaAlert))
getQuotaAlertById alertId =
    runDB $ getBy $ UniqueAlertId alertId

-- | List quota alerts
listQuotaAlerts :: MonadIO m
                => Text  -- ^ Quota ID
                -> Maybe AlertLevel  -- ^ Level filter
                -> Bool  -- ^ Only unacknowledged
                -> Int  -- ^ Offset
                -> Int  -- ^ Limit
                -> m [Entity QuotaAlert]
listQuotaAlerts quotaId mLevel onlyUnacknowledged offset limit = do
    let filters = (QuotaAlertQuotaId ==. quotaId) :
                 maybe [] (\l -> [QuotaAlertLevel ==. l]) mLevel ++
                 [QuotaAlertAcknowledged ==. False | onlyUnacknowledged]
    runDB $ selectList filters [Desc QuotaAlertCreated, OffsetBy offset, LimitTo limit]

-- Helper functions for generating IDs
generateQuotaId :: Text -> ResourceType -> UTCTime -> Text
generateQuotaId orgId rType timestamp =
    "rq_" <> Text.filter isAllowed orgId <> "_" <> Text.pack (show rType) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateUsageId :: Text -> UTCTime -> Text
generateUsageId quotaId timestamp =
    "qu_" <> Text.filter isAllowed quotaId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateAlertId :: Text -> UTCTime -> Text
generateAlertId quotaId timestamp =
    "qa_" <> Text.filter isAllowed quotaId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
