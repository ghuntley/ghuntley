{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Enterprise
    ( -- * Request Types
      CreateEnterpriseRequest(..)
    , UpdateEnterpriseRequest(..)
    , UpdateEnterprisePlanRequest(..)
    , UpdateEnterpriseBrandingRequest(..)
    , UpdateEnterpriseSettingsRequest(..)
      -- * Response Types
    , EnterpriseResponse(..)
    , EnterpriseLimitsResponse(..)
      -- * Handlers
    , handleCreateEnterprise
    , handleUpdateEnterprise
    , handleGetEnterprise
    , handleListEnterprises
    , handleUpdateEnterprisePlan
    , handleCheckEnterpriseLimits
    , handleUpdateEnterpriseBranding
    , handleGetEnterpriseBranding
    , handleUpdateEnterpriseSettings
    , handleGetEnterpriseSettings
    ) where

import Control.Monad.IO.Class (MonadIO)
import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime)
import Database.Persist.Sql (Entity)

import Gerrit.Models.Enterprise
import Gerrit.Services.EnterpriseService
import Gerrit.Api.Utils (requireUserId, handleServiceError)

-- | Request to create a new enterprise
data CreateEnterpriseRequest = CreateEnterpriseRequest
    { cerName :: Text
    , cerDomain :: Text
    , cerPlan :: EnterprisePlan
    , cerMaxUsers :: Maybe Int
    , cerMaxProjects :: Maybe Int
    , cerMaxStorage :: Maybe Int
    , cerBranding :: Maybe BrandingConfig
    , cerSettings :: Value
    , cerMetadata :: Maybe Value
    } deriving (Show)

instance FromJSON CreateEnterpriseRequest where
    parseJSON = withObject "CreateEnterpriseRequest" $ \v -> CreateEnterpriseRequest
        <$> v .: "name"
        <*> v .: "domain"
        <*> v .: "plan"
        <*> v .:? "max_users"
        <*> v .:? "max_projects"
        <*> v .:? "max_storage"
        <*> v .:? "branding"
        <*> v .: "settings"
        <*> v .:? "metadata"

-- | Request to update an enterprise
data UpdateEnterpriseRequest = UpdateEnterpriseRequest
    { uerName :: Text
    , uerDomain :: Text
    , uerStatus :: EnterpriseStatus
    , uerMaxUsers :: Maybe Int
    , uerMaxProjects :: Maybe Int
    , uerMaxStorage :: Maybe Int
    , uerSettings :: Value
    , uerMetadata :: Maybe Value
    } deriving (Show)

instance FromJSON UpdateEnterpriseRequest where
    parseJSON = withObject "UpdateEnterpriseRequest" $ \v -> UpdateEnterpriseRequest
        <$> v .: "name"
        <*> v .: "domain"
        <*> v .: "status"
        <*> v .:? "max_users"
        <*> v .:? "max_projects"
        <*> v .:? "max_storage"
        <*> v .: "settings"
        <*> v .:? "metadata"

-- | Request to update enterprise plan
data UpdateEnterprisePlanRequest = UpdateEnterprisePlanRequest
    { uprPlan :: EnterprisePlan
    , uprMaxUsers :: Maybe Int
    , uprMaxProjects :: Maybe Int
    , uprMaxStorage :: Maybe Int
    } deriving (Show)

instance FromJSON UpdateEnterprisePlanRequest where
    parseJSON = withObject "UpdateEnterprisePlanRequest" $ \v -> UpdateEnterprisePlanRequest
        <$> v .: "plan"
        <*> v .:? "max_users"
        <*> v .:? "max_projects"
        <*> v .:? "max_storage"

-- | Request to update enterprise branding
data UpdateEnterpriseBrandingRequest = UpdateEnterpriseBrandingRequest
    { ubrBranding :: BrandingConfig
    } deriving (Show)

instance FromJSON UpdateEnterpriseBrandingRequest where
    parseJSON = withObject "UpdateEnterpriseBrandingRequest" $ \v -> UpdateEnterpriseBrandingRequest
        <$> v .: "branding"

-- | Request to update enterprise settings
data UpdateEnterpriseSettingsRequest = UpdateEnterpriseSettingsRequest
    { usrSettings :: Value
    } deriving (Show)

instance FromJSON UpdateEnterpriseSettingsRequest where
    parseJSON = withObject "UpdateEnterpriseSettingsRequest" $ \v -> UpdateEnterpriseSettingsRequest
        <$> v .: "settings"

-- | Response for enterprise operations
data EnterpriseResponse = EnterpriseResponse
    { erEnterpriseId :: Text
    , erName :: Text
    , erDomain :: Text
    , erPlan :: EnterprisePlan
    , erStatus :: EnterpriseStatus
    , erMaxUsers :: Maybe Int
    , erMaxProjects :: Maybe Int
    , erMaxStorage :: Maybe Int
    , erBranding :: Maybe BrandingConfig
    , erSettings :: Value
    , erMetadata :: Maybe Value
    , erCreated :: UTCTime
    , erUpdated :: UTCTime
    } deriving (Show)

instance ToJSON EnterpriseResponse where
    toJSON EnterpriseResponse{..} = object
        [ "enterprise_id" .= erEnterpriseId
        , "name" .= erName
        , "domain" .= erDomain
        , "plan" .= erPlan
        , "status" .= erStatus
        , "max_users" .= erMaxUsers
        , "max_projects" .= erMaxProjects
        , "max_storage" .= erMaxStorage
        , "branding" .= erBranding
        , "settings" .= erSettings
        , "metadata" .= erMetadata
        , "created" .= erCreated
        , "updated" .= erUpdated
        ]

-- | Response for enterprise limits check
data EnterpriseLimitsResponse = EnterpriseLimitsResponse
    { elrUsers :: (Int, Maybe Int)  -- ^ (current, limit)
    , elrProjects :: (Int, Maybe Int)
    , elrStorage :: (Int, Maybe Int)
    } deriving (Show)

instance ToJSON EnterpriseLimitsResponse where
    toJSON EnterpriseLimitsResponse{..} = object
        [ "users" .= object
            [ "current" .= fst elrUsers
            , "limit" .= snd elrUsers
            ]
        , "projects" .= object
            [ "current" .= fst elrProjects
            , "limit" .= snd elrProjects
            ]
        , "storage" .= object
            [ "current" .= fst elrStorage
            , "limit" .= snd elrStorage
            ]
        ]

-- | Convert Enterprise entity to response
toEnterpriseResponse :: Entity Enterprise -> EnterpriseResponse
toEnterpriseResponse (Entity _ Enterprise{..}) = EnterpriseResponse
    { erEnterpriseId = enterpriseId
    , erName = enterpriseName
    , erDomain = enterpriseDomain
    , erPlan = enterprisePlan
    , erStatus = enterpriseStatus
    , erMaxUsers = enterpriseMaxUsers
    , erMaxProjects = enterpriseMaxProjects
    , erMaxStorage = enterpriseMaxStorage
    , erBranding = enterpriseBranding
    , erSettings = enterpriseSettings
    , erMetadata = enterpriseMetadata
    , erCreated = enterpriseCreated
    , erUpdated = enterpriseUpdated
    }

-- | Handle enterprise creation
handleCreateEnterprise :: MonadIO m
                      => EnterpriseService
                      -> CreateEnterpriseRequest
                      -> m (Either EnterpriseError EnterpriseResponse)
handleCreateEnterprise service CreateEnterpriseRequest{..} = do
    -- Create enterprise
    result <- createEnterprise service
        cerName
        cerDomain
        cerPlan
        cerMaxUsers
        cerMaxProjects
        cerMaxStorage
        cerBranding
        cerSettings
        cerMetadata

    -- Convert to response
    return $ fmap toEnterpriseResponse result

-- | Handle enterprise update
handleUpdateEnterprise :: MonadIO m
                      => EnterpriseService
                      -> Text  -- ^ Enterprise ID
                      -> UpdateEnterpriseRequest
                      -> m (Either EnterpriseError EnterpriseResponse)
handleUpdateEnterprise service enterpriseId UpdateEnterpriseRequest{..} = do
    -- Update enterprise
    result <- updateEnterprise service
        enterpriseId
        uerName
        uerDomain
        uerStatus
        uerMaxUsers
        uerMaxProjects
        uerMaxStorage
        uerSettings
        uerMetadata

    -- Convert to response
    return $ fmap toEnterpriseResponse result

-- | Handle getting enterprise by ID
handleGetEnterprise :: MonadIO m
                   => EnterpriseService
                   -> Text  -- ^ Enterprise ID
                   -> m (Either EnterpriseError EnterpriseResponse)
handleGetEnterprise service enterpriseId = do
    -- Get enterprise
    result <- getEnterprise service enterpriseId

    -- Convert to response
    return $ fmap toEnterpriseResponse result

-- | Handle listing enterprises
handleListEnterprises :: MonadIO m
                     => EnterpriseService
                     -> Maybe EnterprisePlan  -- ^ Filter by plan
                     -> Maybe EnterpriseStatus  -- ^ Filter by status
                     -> Int  -- ^ Offset
                     -> Int  -- ^ Limit
                     -> m [EnterpriseResponse]
handleListEnterprises service plan status offset limit = do
    -- List enterprises
    enterprises <- listEnterprises service plan status offset limit

    -- Convert to responses
    return $ map toEnterpriseResponse enterprises

-- | Handle updating enterprise plan
handleUpdateEnterprisePlan :: MonadIO m
                          => EnterpriseService
                          -> Text  -- ^ Enterprise ID
                          -> UpdateEnterprisePlanRequest
                          -> m (Either EnterpriseError EnterpriseResponse)
handleUpdateEnterprisePlan service enterpriseId UpdateEnterprisePlanRequest{..} = do
    -- Update plan
    result <- updateEnterprisePlan service
        enterpriseId
        uprPlan
        uprMaxUsers
        uprMaxProjects
        uprMaxStorage

    -- Convert to response
    return $ fmap toEnterpriseResponse result

-- | Handle checking enterprise limits
handleCheckEnterpriseLimits :: MonadIO m
                           => EnterpriseService
                           -> Text  -- ^ Enterprise ID
                           -> m (Either EnterpriseError EnterpriseLimitsResponse)
handleCheckEnterpriseLimits service enterpriseId = do
    -- Check limits
    result <- checkEnterpriseLimits service enterpriseId

    -- Convert to response
    return $ case result of
        Left err -> Left err
        Right limits -> Right $ EnterpriseLimitsResponse
            { elrUsers = (0, Nothing)  -- TODO: Implement actual limit checking
            , elrProjects = (0, Nothing)
            , elrStorage = (0, Nothing)
            }

-- | Handle updating enterprise branding
handleUpdateEnterpriseBranding :: MonadIO m
                              => EnterpriseService
                              -> Text  -- ^ Enterprise ID
                              -> UpdateEnterpriseBrandingRequest
                              -> m (Either EnterpriseError EnterpriseResponse)
handleUpdateEnterpriseBranding service enterpriseId UpdateEnterpriseBrandingRequest{..} = do
    -- Update branding
    result <- updateEnterpriseBranding service enterpriseId ubrBranding

    -- Convert to response
    return $ fmap toEnterpriseResponse result

-- | Handle getting enterprise branding
handleGetEnterpriseBranding :: MonadIO m
                           => EnterpriseService
                           -> Text  -- ^ Enterprise ID
                           -> m (Either EnterpriseError (Maybe BrandingConfig))
handleGetEnterpriseBranding = getEnterpriseBranding

-- | Handle updating enterprise settings
handleUpdateEnterpriseSettings :: MonadIO m
                              => EnterpriseService
                              -> Text  -- ^ Enterprise ID
                              -> UpdateEnterpriseSettingsRequest
                              -> m (Either EnterpriseError EnterpriseResponse)
handleUpdateEnterpriseSettings service enterpriseId UpdateEnterpriseSettingsRequest{..} = do
    -- Update settings
    result <- updateEnterpriseSettings service enterpriseId usrSettings

    -- Convert to response
    return $ fmap toEnterpriseResponse result

-- | Handle getting enterprise settings
handleGetEnterpriseSettings :: MonadIO m
                           => EnterpriseService
                           -> Text  -- ^ Enterprise ID
                           -> m (Either EnterpriseError Value)
handleGetEnterpriseSettings = getEnterpriseSettings
