{-|
Module      : Gerrit.Models.Admin
Description : Administrative models and functions
Copyright   : (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>
License     : Proprietary
Maintainer  : ghuntley@ghuntley.com
Stability   : experimental
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Models.Admin
    ( -- * Types
      SystemHealth(..)
    , SystemHealthId
    , SystemMetrics(..)
    , SystemMetricsId
    , SystemSettings(..)
    , SystemSettingsId
    , MaintenanceSchedule(..)
    , MaintenanceScheduleId
    , ResourceUsage(..)
    , ResourceUsageId
    , SecurityPolicy(..)
    , SecurityPolicyId
    , ApiKey(..)
    , ApiKeyId
    , RateLimitConfig(..)
    , RateLimitConfigId
    , IpAllowlist(..)
    , IpAllowlistId
    , FeatureFlag(..)
    , FeatureFlagId
    , ServiceConfig(..)
    , ServiceConfigId
    , EmailTemplate(..)
    , EmailTemplateId
    , WebhookConfig(..)
    , WebhookConfigId
    , AdminConfig(..)
    , AdminConfigId
    , AdminAction(..)
    , AdminAudit(..)
    , AdminAuditId
    -- * Operations
    , getSystemHealth
    , getSystemMetrics
    , getSystemSettings
    , updateSystemSettings
    , scheduleSystemMaintenance
    , getMaintenanceSchedule
    , getResourceUsage
    , getSecurityPolicies
    , updateSecurityPolicies
    , createApiKey
    , revokeApiKey
    , getRateLimitConfig
    , updateRateLimitConfig
    , getIpAllowlist
    , updateIpAllowlist
    , getFeatureFlags
    , updateFeatureFlags
    , getServiceConfigs
    , updateServiceConfig
    , getEmailTemplates
    , updateEmailTemplate
    , getWebhookConfigs
    , updateWebhookConfig
    , getConfig
    , updateConfig
    , getConfigValue
    , setConfigValue
    , listConfigHistory
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (ToJSON(..), FromJSON(..), Value, object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.AuditLog (logAdminAction)

-- | Define persistent entities
share [mkPersist sqlSettings, mkMigrate "migrateAdmin"] [persistLowerCase|
SystemHealth
    status Text
    checks Value
    lastUpdated UTCTime
    deriving Show Generic

SystemMetrics
    cpuUsage Double
    memoryUsage Double
    diskUsage Double
    networkStats Value
    timestamp UTCTime
    deriving Show Generic

SystemSettings
    maxUsers Int
    maxProjects Int
    maxStoragePerProject Int64
    backupSchedule Text
    emailSettings Value
    integrationSettings Value
    updated UTCTime
    UniqueSystemSettings
    deriving Show Generic

MaintenanceSchedule
    maintenanceType Text
    scheduledStart UTCTime
    estimatedDuration Int64
    affectedServices Value
    description Text
    created UTCTime
    deriving Show Generic

ResourceUsage
    storageUsage Int64
    databaseSize Int64
    cacheSize Int64
    activeJobs Int
    queuedJobs Int
    updated UTCTime
    deriving Show Generic

SecurityPolicy
    passwordPolicy Value
    sessionPolicy Value
    mfaPolicy Value
    accessPolicy Value
    updated UTCTime
    UniqueSecurityPolicy
    deriving Show Generic

ApiKey
    keyId Text
    name Text
    createdAt UTCTime
    lastUsed UTCTime Maybe
    permissions Value
    UniqueApiKeyId keyId
    deriving Show Generic

RateLimitConfig
    authEndpoints Int
    standardEndpoints Int
    webhookEndpoints Int
    customLimits Value
    updated UTCTime
    UniqueRateLimitConfig
    deriving Show Generic

IpAllowlist
    allowedIps Value
    allowedRanges Value
    exceptions Value
    updated UTCTime
    UniqueIpAllowlist
    deriving Show Generic

FeatureFlag
    name Text
    enabled Bool
    description Text
    conditions Value
    updated UTCTime
    UniqueFeatureFlagName name
    deriving Show Generic

ServiceConfig
    name Text
    serviceType Text
    config Value
    version Text
    updated UTCTime
    UniqueServiceConfigName name
    deriving Show Generic

EmailTemplate
    name Text
    subject Text
    body Text
    variables Value
    updated UTCTime
    UniqueEmailTemplateName name
    deriving Show Generic

WebhookConfig
    url Text
    events Value
    headers Value
    active Bool
    updated UTCTime
    UniqueWebhookUrl url
    deriving Show Generic

AdminConfig
    configId Text
    category Text
    key Text
    value Value
    description Text Maybe
    isSecret Bool default=false
    isSystem Bool default=false
    created UTCTime
    updated UTCTime
    UniqueConfigId configId
    UniqueConfigKey category key
    deriving Show Eq Generic

AdminAudit
    auditId Text
    action AdminAction
    category Text
    key Text
    oldValue Value Maybe
    newValue Value Maybe
    details Value
    performedBy Text
    timestamp UTCTime
    UniqueAdminAuditId auditId
    deriving Show Eq Generic
|]

-- | Get current system health status
getSystemHealth :: MonadIO m
                => ConnectionPool
                -> m (Entity SystemHealth)
getSystemHealth pool = do
    now <- liftIO getCurrentTime
    let health = SystemHealth
            { systemHealthStatus = "healthy"
            , systemHealthChecks = toJSON []
            , systemHealthLastUpdated = now
            }
    runSqlPool (insertEntity health) pool

-- | Get system performance metrics
getSystemMetrics :: MonadIO m
                 => ConnectionPool
                 -> m (Entity SystemMetrics)
getSystemMetrics pool = do
    now <- liftIO getCurrentTime
    let metrics = SystemMetrics
            { systemMetricsCpuUsage = 0.0
            , systemMetricsMemoryUsage = 0.0
            , systemMetricsDiskUsage = 0.0
            , systemMetricsNetworkStats = toJSON []
            , systemMetricsTimestamp = now
            }
    runSqlPool (insertEntity metrics) pool

-- | Get system-wide settings
getSystemSettings :: MonadIO m
                  => ConnectionPool
                  -> m (Maybe (Entity SystemSettings))
getSystemSettings pool =
    runSqlPool (getBy UniqueSystemSettings) pool

-- | Update system-wide settings
updateSystemSettings :: MonadIO m
                    => ConnectionPool
                    -> SystemSettings
                    -> m (Entity SystemSettings)
updateSystemSettings pool settings = do
    now <- liftIO getCurrentTime
    let updatedSettings = settings { systemSettingsUpdated = now }
    runSqlPool (upsert updatedSettings [SystemSettingsUpdated =. now]) pool

-- | Schedule system maintenance
scheduleSystemMaintenance :: MonadIO m
                         => ConnectionPool
                         -> Text  -- ^ Maintenance type
                         -> UTCTime  -- ^ Scheduled start
                         -> Int64  -- ^ Estimated duration
                         -> [Text]  -- ^ Affected services
                         -> Text  -- ^ Description
                         -> m (Entity MaintenanceSchedule)
scheduleSystemMaintenance pool mType start duration services desc = do
    now <- liftIO getCurrentTime
    let schedule = MaintenanceSchedule
            { maintenanceScheduleMaintenanceType = mType
            , maintenanceScheduleScheduledStart = start
            , maintenanceScheduleEstimatedDuration = duration
            , maintenanceScheduleAffectedServices = toJSON services
            , maintenanceScheduleDescription = desc
            , maintenanceScheduleCreated = now
            }
    runSqlPool (insertEntity schedule) pool

-- | Get maintenance schedule
getMaintenanceSchedule :: MonadIO m
                       => ConnectionPool
                       -> m [Entity MaintenanceSchedule]
getMaintenanceSchedule pool =
    runSqlPool (selectList [] [Asc MaintenanceScheduleScheduledStart]) pool

-- | Get resource usage statistics
getResourceUsage :: MonadIO m
                 => ConnectionPool
                 -> m (Maybe (Entity ResourceUsage))
getResourceUsage pool =
    runSqlPool (selectFirst [] [Desc ResourceUsageUpdated]) pool

-- | Get security policies
getSecurityPolicies :: MonadIO m
                    => ConnectionPool
                    -> m (Maybe (Entity SecurityPolicy))
getSecurityPolicies pool =
    runSqlPool (getBy UniqueSecurityPolicy) pool

-- | Update security policies
updateSecurityPolicies :: MonadIO m
                      => ConnectionPool
                      -> SecurityPolicy
                      -> m (Entity SecurityPolicy)
updateSecurityPolicies pool policy = do
    now <- liftIO getCurrentTime
    let updatedPolicy = policy { securityPolicyUpdated = now }
    runSqlPool (upsert updatedPolicy [SecurityPolicyUpdated =. now]) pool

-- | Create new API key
createApiKey :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Key name
             -> [Text]  -- ^ Permissions
             -> m (Entity ApiKey)
createApiKey pool name perms = do
    now <- liftIO getCurrentTime
    let key = ApiKey
            { apiKeyKeyId = generateKeyId name now
            , apiKeyName = name
            , apiKeyCreatedAt = now
            , apiKeyLastUsed = Nothing
            , apiKeyPermissions = toJSON perms
            }
    runSqlPool (insertEntity key) pool

-- | Revoke API key
revokeApiKey :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Key ID
             -> m ()
revokeApiKey pool keyId =
    runSqlPool (deleteBy $ UniqueApiKeyId keyId) pool

-- | Get rate limit configuration
getRateLimitConfig :: MonadIO m
                   => ConnectionPool
                   -> m (Maybe (Entity RateLimitConfig))
getRateLimitConfig pool =
    runSqlPool (getBy UniqueRateLimitConfig) pool

-- | Update rate limit configuration
updateRateLimitConfig :: MonadIO m
                     => ConnectionPool
                     -> RateLimitConfig
                     -> m (Entity RateLimitConfig)
updateRateLimitConfig pool config = do
    now <- liftIO getCurrentTime
    let updatedConfig = config { rateLimitConfigUpdated = now }
    runSqlPool (upsert updatedConfig [RateLimitConfigUpdated =. now]) pool

-- | Get IP allowlist configuration
getIpAllowlist :: MonadIO m
                => ConnectionPool
                -> m (Maybe (Entity IpAllowlist))
getIpAllowlist pool =
    runSqlPool (getBy UniqueIpAllowlist) pool

-- | Update IP allowlist configuration
updateIpAllowlist :: MonadIO m
                  => ConnectionPool
                  -> IpAllowlist
                  -> m (Entity IpAllowlist)
updateIpAllowlist pool allowlist = do
    now <- liftIO getCurrentTime
    let updatedAllowlist = allowlist { ipAllowlistUpdated = now }
    runSqlPool (upsert updatedAllowlist [IpAllowlistUpdated =. now]) pool

-- | Get feature flags
getFeatureFlags :: MonadIO m
                => ConnectionPool
                -> m [Entity FeatureFlag]
getFeatureFlags pool =
    runSqlPool (selectList [] [Asc FeatureFlagName]) pool

-- | Update feature flags
updateFeatureFlags :: MonadIO m
                   => ConnectionPool
                   -> [FeatureFlag]
                   -> m [Entity FeatureFlag]
updateFeatureFlags pool flags = do
    now <- liftIO getCurrentTime
    let updatedFlags = map (\f -> f { featureFlagUpdated = now }) flags
    runSqlPool (mapM (\f -> upsert f [FeatureFlagUpdated =. now]) updatedFlags) pool

-- | Get service configurations
getServiceConfigs :: MonadIO m
                  => ConnectionPool
                  -> m [Entity ServiceConfig]
getServiceConfigs pool =
    runSqlPool (selectList [] [Asc ServiceConfigName]) pool

-- | Update service configuration
updateServiceConfig :: MonadIO m
                    => ConnectionPool
                    -> ServiceConfig
                    -> m (Entity ServiceConfig)
updateServiceConfig pool config = do
    now <- liftIO getCurrentTime
    let updatedConfig = config { serviceConfigUpdated = now }
    runSqlPool (upsert updatedConfig [ServiceConfigUpdated =. now]) pool

-- | Get email templates
getEmailTemplates :: MonadIO m
                  => ConnectionPool
                  -> m [Entity EmailTemplate]
getEmailTemplates pool =
    runSqlPool (selectList [] [Asc EmailTemplateName]) pool

-- | Update email template
updateEmailTemplate :: MonadIO m
                    => ConnectionPool
                    -> EmailTemplate
                    -> m (Entity EmailTemplate)
updateEmailTemplate pool template = do
    now <- liftIO getCurrentTime
    let updatedTemplate = template { emailTemplateUpdated = now }
    runSqlPool (upsert updatedTemplate [EmailTemplateUpdated =. now]) pool

-- | Get webhook configurations
getWebhookConfigs :: MonadIO m
                  => ConnectionPool
                  -> m [Entity WebhookConfig]
getWebhookConfigs pool =
    runSqlPool (selectList [] [Asc WebhookConfigUrl]) pool

-- | Update webhook configuration
updateWebhookConfig :: MonadIO m
                    => ConnectionPool
                    -> WebhookConfig
                    -> m (Entity WebhookConfig)
updateWebhookConfig pool config = do
    now <- liftIO getCurrentTime
    let updatedConfig = config { webhookConfigUpdated = now }
    runSqlPool (upsert updatedConfig [WebhookConfigUpdated =. now]) pool

-- | Helper function to generate a unique key ID
generateKeyId :: Text -> UTCTime -> Text
generateKeyId name timestamp =
    "key-" <> name <> "-" <> Text.pack (show timestamp)

-- | Get configuration by category and key
getConfig :: MonadIO m
          => ConnectionPool
          -> Text  -- ^ Category
          -> Text  -- ^ Key
          -> m (Maybe (Entity AdminConfig))
getConfig pool category key =
    runSqlPool (getBy $ UniqueConfigKey category key) pool

-- | Update configuration
updateConfig :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Category
             -> Text  -- ^ Key
             -> Value  -- ^ New value
             -> Maybe Text  -- ^ New description
             -> Bool  -- ^ Is secret
             -> Bool  -- ^ Is system config
             -> Text  -- ^ Performed by user ID
             -> m (Entity AdminConfig)
updateConfig pool category key newValue mDescription isSecret isSystem performedBy = do
    now <- liftIO getCurrentTime
    maybeConfig <- getConfig pool category key

    case maybeConfig of
        Just (Entity _ config) -> do
            let configId = adminConfigConfigId config
            let updatedConfig = config
                    { adminConfigValue = newValue
                    , adminConfigDescription = mDescription
                    , adminConfigIsSecret = isSecret
                    , adminConfigIsSystem = isSystem
                    , adminConfigUpdated = now
                    }

            -- Create audit entry
            let auditId = generateAuditId category key now
            let audit = AdminAudit
                    { adminAuditAuditId = auditId
                    , adminAuditAction = ConfigUpdate
                    , adminAuditCategory = category
                    , adminAuditKey = key
                    , adminAuditOldValue = Just $ adminConfigValue config
                    , adminAuditNewValue = Just newValue
                    , adminAuditDetails = object
                        [ "description_changed" .= (mDescription /= adminConfigDescription config)
                        , "secret_changed" .= (isSecret /= adminConfigIsSecret config)
                        , "system_changed" .= (isSystem /= adminConfigIsSystem config)
                        ]
                    , adminAuditPerformedBy = performedBy
                    , adminAuditTimestamp = now
                    }

            runSqlPool (do
                updateWhere
                    [AdminConfigConfigId ==. configId]
                    [ AdminConfigValue =. newValue
                    , AdminConfigDescription =. mDescription
                    , AdminConfigIsSecret =. isSecret
                    , AdminConfigIsSystem =. isSystem
                    , AdminConfigUpdated =. now
                    ]
                insertEntity audit
                getEntity configId) pool

        Nothing -> do
            let configId = generateConfigId category key
            let newConfig = AdminConfig
                    { adminConfigConfigId = configId
                    , adminConfigCategory = category
                    , adminConfigKey = key
                    , adminConfigValue = newValue
                    , adminConfigDescription = mDescription
                    , adminConfigIsSecret = isSecret
                    , adminConfigIsSystem = isSystem
                    , adminConfigCreated = now
                    , adminConfigUpdated = now
                    }

            -- Create audit entry for new config
            let auditId = generateAuditId category key now
            let audit = AdminAudit
                    { adminAuditAuditId = auditId
                    , adminAuditAction = ConfigUpdate
                    , adminAuditCategory = category
                    , adminAuditKey = key
                    , adminAuditOldValue = Nothing
                    , adminAuditNewValue = Just newValue
                    , adminAuditDetails = object
                        [ "created" .= True
                        , "is_secret" .= isSecret
                        , "is_system" .= isSystem
                        ]
                    , adminAuditPerformedBy = performedBy
                    , adminAuditTimestamp = now
                    }

            runSqlPool (do
                configEntity <- insertEntity newConfig
                insertEntity audit
                return configEntity) pool

-- | Get configuration value
getConfigValue :: MonadIO m
               => ConnectionPool
               -> Text  -- ^ Category
               -> Text  -- ^ Key
               -> m (Maybe Value)
getConfigValue pool category key = do
    maybeConfig <- getConfig pool category key
    return $ adminConfigValue . entityVal <$> maybeConfig

-- | Set configuration value
setConfigValue :: MonadIO m
               => ConnectionPool
               -> Text  -- ^ Category
               -> Text  -- ^ Key
               -> Value  -- ^ New value
               -> Text  -- ^ Performed by user ID
               -> m ()
setConfigValue pool category key newValue performedBy = do
    maybeConfig <- getConfig pool category key
    now <- liftIO getCurrentTime

    case maybeConfig of
        Just (Entity _ config) -> do
            let auditId = generateAuditId category key now
            let audit = AdminAudit
                    { adminAuditAuditId = auditId
                    , adminAuditAction = ConfigUpdate
                    , adminAuditCategory = category
                    , adminAuditKey = key
                    , adminAuditOldValue = Just $ adminConfigValue config
                    , adminAuditNewValue = Just newValue
                    , adminAuditDetails = object []
                    , adminAuditPerformedBy = performedBy
                    , adminAuditTimestamp = now
                    }

            runSqlPool (do
                updateWhere
                    [AdminConfigCategory ==. category, AdminConfigKey ==. key]
                    [AdminConfigValue =. newValue, AdminConfigUpdated =. now]
                insertEntity audit) pool

        Nothing -> do
            let configId = generateConfigId category key
            let newConfig = AdminConfig
                    { adminConfigConfigId = configId
                    , adminConfigCategory = category
                    , adminConfigKey = key
                    , adminConfigValue = newValue
                    , adminConfigDescription = Nothing
                    , adminConfigIsSecret = False
                    , adminConfigIsSystem = False
                    , adminConfigCreated = now
                    , adminConfigUpdated = now
                    }

            let auditId = generateAuditId category key now
            let audit = AdminAudit
                    { adminAuditAuditId = auditId
                    , adminAuditAction = ConfigUpdate
                    , adminAuditCategory = category
                    , adminAuditKey = key
                    , adminAuditOldValue = Nothing
                    , adminAuditNewValue = Just newValue
                    , adminAuditDetails = object ["created" .= True]
                    , adminAuditPerformedBy = performedBy
                    , adminAuditTimestamp = now
                    }

            runSqlPool (do
                insertEntity newConfig
                insertEntity audit) pool

-- | List configuration history
listConfigHistory :: MonadIO m
                  => ConnectionPool
                  -> Text  -- ^ Category
                  -> Text  -- ^ Key
                  -> Int  -- ^ Limit
                  -> Int  -- ^ Offset
                  -> m [Entity AdminAudit]
listConfigHistory pool category key limit offset =
    runSqlPool (selectList
        [AdminAuditCategory ==. category, AdminAuditKey ==. key]
        [Desc AdminAuditTimestamp, LimitTo limit, OffsetBy offset]) pool

-- Helper functions for generating IDs
generateConfigId :: Text -> Text -> Text
generateConfigId category key =
    "cfg_" <> Text.filter isAllowed category <> "_" <> Text.filter isAllowed key
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateAuditId :: Text -> Text -> UTCTime -> Text
generateAuditId category key timestamp =
    "audit_" <> Text.filter isAllowed category <> "_" <> Text.filter isAllowed key <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
