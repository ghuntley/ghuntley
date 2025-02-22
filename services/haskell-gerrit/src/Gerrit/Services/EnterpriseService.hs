{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.EnterpriseService
    ( -- * Types
      EnterpriseService(..)
    , EnterpriseError(..)
      -- * Service Creation
    , initEnterpriseService
      -- * Core Operations
    , createEnterprise
    , updateEnterprise
    , getEnterprise
    , listEnterprises
      -- * Plan Management
    , updateEnterprisePlan
    , checkEnterpriseLimits
      -- * Branding
    , updateEnterpriseBranding
    , getEnterpriseBranding
      -- * Settings
    , updateEnterpriseSettings
    , getEnterpriseSettings
    ) where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Monad (forever, void, when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=), FromJSON, ToJSON)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist.Sql (ConnectionPool, Entity)

import Gerrit.Models.Enterprise
import Gerrit.Models.Organization
import Gerrit.Models.Billing
import Gerrit.Models.Types
import Gerrit.VCS.Notification (NotificationSystem)
import Gerrit.Services.EnterpriseMetrics (EnterpriseMetrics)
import qualified Gerrit.Services.EnterpriseMetrics as Metrics
import Gerrit.Services.NotificationService (NotificationService)
import Gerrit.Services.MetricsService (MetricsService)
import Gerrit.Services.BillingService (BillingService)

-- | Enterprise service errors
data EnterpriseError
    = EnterpriseNotFound Text
    | DomainTaken Text
    | InvalidPlan Text
    | LimitExceeded Text
    | ValidationError Text
    | DatabaseError Text
    | BillingError Text
    deriving (Show, Eq)

-- | Enterprise service
data EnterpriseService = EnterpriseService
    { esConnPool :: ConnectionPool
    , esNotificationService :: NotificationService
    , esMetricsService :: MetricsService
    , esBillingService :: BillingService
    }

-- | Initialize the enterprise service
initEnterpriseService :: ConnectionPool
                     -> NotificationService
                     -> MetricsService
                     -> BillingService
                     -> EnterpriseService
initEnterpriseService pool notifService metricsService billingService =
    EnterpriseService
        { esConnPool = pool
        , esNotificationService = notifService
        , esMetricsService = metricsService
        , esBillingService = billingService
        }

-- | Create a new enterprise
createEnterprise :: MonadIO m
                => EnterpriseService
                -> Text  -- ^ Name
                -> Text  -- ^ Domain
                -> EnterprisePlan  -- ^ Plan
                -> Maybe Int  -- ^ Max users
                -> Maybe Int  -- ^ Max projects
                -> Maybe Int  -- ^ Max storage
                -> Maybe BrandingConfig  -- ^ Branding config
                -> Value  -- ^ Settings
                -> Maybe Value  -- ^ Additional metadata
                -> m (Either EnterpriseError (Entity Enterprise))
createEnterprise EnterpriseService{..} name domain plan maxUsers maxProjects maxStorage branding settings metadata = do
    -- Check if domain is available
    existing <- getEnterpriseByDomain esConnPool domain
    case existing of
        Just _ -> return $ Left $ DomainTaken domain
        Nothing -> do
            -- Set up trial period if applicable
            trialEnds <- case plan of
                FreePlan -> return Nothing
                _ -> do
                    now <- liftIO getCurrentTime
                    return $ Just $ addUTCTime (30 * 24 * 3600) now  -- 30 days trial

            -- Create enterprise
            result <- createEnterprise esConnPool
                name
                domain
                plan
                maxUsers
                maxProjects
                maxStorage
                branding
                settings
                metadata
                trialEnds

            -- Record metrics
            recordEnterpriseCreation esMetricsService result

            -- Send notifications
            notifyEnterpriseCreated esNotificationService result

            return $ Right result

-- | Update an enterprise
updateEnterprise :: MonadIO m
                => EnterpriseService
                -> Text  -- ^ Enterprise ID
                -> Text  -- ^ Name
                -> Text  -- ^ Domain
                -> EnterpriseStatus  -- ^ Status
                -> Maybe Int  -- ^ Max users
                -> Maybe Int  -- ^ Max projects
                -> Maybe Int  -- ^ Max storage
                -> Value  -- ^ Settings
                -> Maybe Value  -- ^ Metadata
                -> m (Either EnterpriseError (Entity Enterprise))
updateEnterprise EnterpriseService{..} enterpriseId name domain status maxUsers maxProjects maxStorage settings metadata = do
    -- Get enterprise
    mEnterprise <- getEnterpriseById esConnPool enterpriseId
    case mEnterprise of
        Nothing -> return $ Left $ EnterpriseNotFound enterpriseId
        Just enterprise -> do
            -- Check if new domain is available (if changed)
            when (domain /= enterpriseDomain (entityVal enterprise)) $ do
                existing <- getEnterpriseByDomain esConnPool domain
                case existing of
                    Just _ -> return $ Left $ DomainTaken domain
                    Nothing -> return ()

            -- Update enterprise
            result <- updateEnterprise esConnPool
                enterprise
                name
                domain
                status
                maxUsers
                maxProjects
                maxStorage
                settings
                metadata

            -- Record metrics
            recordEnterpriseUpdate esMetricsService result

            -- Send notifications
            notifyEnterpriseUpdated esNotificationService result

            return $ Right result

-- | Get an enterprise by ID
getEnterprise :: MonadIO m
              => EnterpriseService
              -> Text  -- ^ Enterprise ID
              -> m (Either EnterpriseError (Entity Enterprise))
getEnterprise EnterpriseService{..} enterpriseId = do
    result <- getEnterpriseById esConnPool enterpriseId
    case result of
        Nothing -> return $ Left $ EnterpriseNotFound enterpriseId
        Just enterprise -> return $ Right enterprise

-- | List enterprises with filtering
listEnterprises :: MonadIO m
                => EnterpriseService
                -> Maybe EnterprisePlan  -- ^ Filter by plan
                -> Maybe EnterpriseStatus  -- ^ Filter by status
                -> Int  -- ^ Offset
                -> Int  -- ^ Limit
                -> m [Entity Enterprise]
listEnterprises EnterpriseService{..} plan status =
    listEnterprises esConnPool plan status

-- | Update enterprise plan
updateEnterprisePlan :: MonadIO m
                    => EnterpriseService
                    -> Text  -- ^ Enterprise ID
                    -> EnterprisePlan  -- ^ New plan
                    -> Maybe Int  -- ^ New max users
                    -> Maybe Int  -- ^ New max projects
                    -> Maybe Int  -- ^ New max storage
                    -> m (Either EnterpriseError (Entity Enterprise))
updateEnterprisePlan EnterpriseService{..} enterpriseId plan maxUsers maxProjects maxStorage = do
    -- Get enterprise
    mEnterprise <- getEnterpriseById esConnPool enterpriseId
    case mEnterprise of
        Nothing -> return $ Left $ EnterpriseNotFound enterpriseId
        Just enterprise -> do
            -- Update plan
            result <- updatePlan esConnPool
                enterprise
                plan
                maxUsers
                maxProjects
                maxStorage

            -- Record metrics
            recordEnterprisePlanUpdate esMetricsService result plan

            -- Send notifications
            notifyEnterprisePlanUpdated esNotificationService result plan

            return $ Right result

-- | Check enterprise limits
checkEnterpriseLimits :: MonadIO m
                     => EnterpriseService
                     -> Text  -- ^ Enterprise ID
                     -> m (Either EnterpriseError Value)
checkEnterpriseLimits EnterpriseService{..} enterpriseId = do
    -- Get enterprise
    mEnterprise <- getEnterpriseById esConnPool enterpriseId
    case mEnterprise of
        Nothing -> return $ Left $ EnterpriseNotFound enterpriseId
        Just enterprise -> do
            -- Check various limits
            -- TODO: Implement actual limit checking
            return $ Right $ object
                [ "users" .= object
                    [ "current" .= (0 :: Int)
                    , "limit" .= enterpriseMaxUsers (entityVal enterprise)
                    ]
                , "projects" .= object
                    [ "current" .= (0 :: Int)
                    , "limit" .= enterpriseMaxProjects (entityVal enterprise)
                    ]
                , "storage" .= object
                    [ "current" .= (0 :: Int)
                    , "limit" .= enterpriseMaxStorage (entityVal enterprise)
                    ]
                ]

-- | Update enterprise branding
updateEnterpriseBranding :: MonadIO m
                        => EnterpriseService
                        -> Text  -- ^ Enterprise ID
                        -> BrandingConfig  -- ^ New branding config
                        -> m (Either EnterpriseError (Entity Enterprise))
updateEnterpriseBranding EnterpriseService{..} enterpriseId branding = do
    -- Get enterprise
    mEnterprise <- getEnterpriseById esConnPool enterpriseId
    case mEnterprise of
        Nothing -> return $ Left $ EnterpriseNotFound enterpriseId
        Just enterprise -> do
            -- Update branding
            result <- updateBranding esConnPool enterprise branding

            -- Record metrics
            recordEnterpriseBrandingUpdate esMetricsService result

            -- Send notifications
            notifyEnterpriseBrandingUpdated esNotificationService result

            return $ Right result

-- | Get enterprise branding
getEnterpriseBranding :: MonadIO m
                     => EnterpriseService
                     -> Text  -- ^ Enterprise ID
                     -> m (Either EnterpriseError (Maybe BrandingConfig))
getEnterpriseBranding EnterpriseService{..} enterpriseId = do
    -- Get enterprise
    mEnterprise <- getEnterpriseById esConnPool enterpriseId
    case mEnterprise of
        Nothing -> return $ Left $ EnterpriseNotFound enterpriseId
        Just enterprise -> return $ Right $ enterpriseBranding $ entityVal enterprise

-- | Update enterprise settings
updateEnterpriseSettings :: MonadIO m
                        => EnterpriseService
                        -> Text  -- ^ Enterprise ID
                        -> Value  -- ^ New settings
                        -> m (Either EnterpriseError (Entity Enterprise))
updateEnterpriseSettings service enterpriseId settings = do
    -- Get current enterprise
    result <- getEnterprise service enterpriseId
    case result of
        Left err -> return $ Left err
        Right (Entity key enterprise) -> do
            -- Update settings
            let updatedEnterprise = enterprise { enterpriseSettings = settings }
            now <- liftIO getCurrentTime
            runSqlPool (replace key updatedEnterprise) (esConnPool service)
            return $ Right $ Entity key updatedEnterprise

-- | Get enterprise settings
getEnterpriseSettings :: MonadIO m
                     => EnterpriseService
                     -> Text  -- ^ Enterprise ID
                     -> m (Either EnterpriseError Value)
getEnterpriseSettings service enterpriseId = do
    result <- getEnterprise service enterpriseId
    case result of
        Left err -> return $ Left err
        Right enterprise -> return $ Right $ enterpriseSettings $ entityVal enterprise

-- Helper functions for notifications
notifyEnterpriseCreated :: MonadIO m
                       => NotificationService
                       -> Entity Enterprise
                       -> m ()
notifyEnterpriseCreated notifService enterprise = do
    -- TODO: Implement notification
    return ()

notifyEnterpriseUpdated :: MonadIO m
                       => NotificationService
                       -> Entity Enterprise
                       -> m ()
notifyEnterpriseUpdated notifService enterprise = do
    -- TODO: Implement notification
    return ()

notifyEnterprisePlanUpdated :: MonadIO m
                           => NotificationService
                           -> Entity Enterprise
                           -> EnterprisePlan
                           -> m ()
notifyEnterprisePlanUpdated notifService enterprise plan = do
    -- TODO: Implement notification
    return ()

notifyEnterpriseBrandingUpdated :: MonadIO m
                               => NotificationService
                               -> Entity Enterprise
                               -> m ()
notifyEnterpriseBrandingUpdated notifService enterprise = do
    -- TODO: Implement notification
    return ()

-- Helper functions for metrics
recordEnterpriseCreation :: MonadIO m
                        => MetricsService
                        -> Entity Enterprise
                        -> m ()
recordEnterpriseCreation metricsService enterprise = do
    -- TODO: Implement metrics recording
    return ()

recordEnterpriseUpdate :: MonadIO m
                      => MetricsService
                      -> Entity Enterprise
                      -> m ()
recordEnterpriseUpdate metricsService enterprise = do
    -- TODO: Implement metrics recording
    return ()

recordEnterprisePlanUpdate :: MonadIO m
                          => MetricsService
                          -> Entity Enterprise
                          -> EnterprisePlan
                          -> m ()
recordEnterprisePlanUpdate metricsService enterprise plan = do
    -- TODO: Implement metrics recording
    return ()

recordEnterpriseBrandingUpdate :: MonadIO m
                              => MetricsService
                              -> Entity Enterprise
                              -> m ()
recordEnterpriseBrandingUpdate metricsService enterprise = do
    -- TODO: Implement metrics recording
    return ()
