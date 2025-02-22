{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.Enterprise
    ( enterpriseRoutes
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Web.Scotty

import Gerrit.Api.Handlers.Enterprise
import Gerrit.Services.EnterpriseService (EnterpriseService)
import Gerrit.Api.Utils (requireUserId, handleServiceError)

-- | Enterprise API routes
enterpriseRoutes :: EnterpriseService -> ScottyM ()
enterpriseRoutes service = do
    -- Create enterprise
    post "/api/v1/enterprises" $ do
        userId <- requireUserId
        req <- jsonData
        result <- liftIO $ handleCreateEnterprise service req
        case result of
            Left err -> handleServiceError err
            Right response -> json response

    -- Update enterprise
    put "/api/v1/enterprises/:enterprise_id" $ do
        userId <- requireUserId
        enterpriseId <- param "enterprise_id"
        req <- jsonData
        result <- liftIO $ handleUpdateEnterprise service enterpriseId req
        case result of
            Left err -> handleServiceError err
            Right response -> json response

    -- Get enterprise by ID
    get "/api/v1/enterprises/:enterprise_id" $ do
        userId <- requireUserId
        enterpriseId <- param "enterprise_id"
        result <- liftIO $ handleGetEnterprise service enterpriseId
        case result of
            Left err -> handleServiceError err
            Right response -> json response

    -- List enterprises
    get "/api/v1/enterprises" $ do
        userId <- requireUserId
        plan <- paramMaybe "plan"
        status <- paramMaybe "status"
        offset <- param "offset" `rescue` const (return 0)
        limit <- param "limit" `rescue` const (return 50)
        enterprises <- liftIO $ handleListEnterprises service plan status offset limit
        json enterprises

    -- Update enterprise plan
    put "/api/v1/enterprises/:enterprise_id/plan" $ do
        userId <- requireUserId
        enterpriseId <- param "enterprise_id"
        req <- jsonData
        result <- liftIO $ handleUpdateEnterprisePlan service enterpriseId req
        case result of
            Left err -> handleServiceError err
            Right response -> json response

    -- Check enterprise limits
    get "/api/v1/enterprises/:enterprise_id/limits" $ do
        userId <- requireUserId
        enterpriseId <- param "enterprise_id"
        result <- liftIO $ handleCheckEnterpriseLimits service enterpriseId
        case result of
            Left err -> handleServiceError err
            Right response -> json response

    -- Update enterprise branding
    put "/api/v1/enterprises/:enterprise_id/branding" $ do
        userId <- requireUserId
        enterpriseId <- param "enterprise_id"
        req <- jsonData
        result <- liftIO $ handleUpdateEnterpriseBranding service enterpriseId req
        case result of
            Left err -> handleServiceError err
            Right response -> json response

    -- Get enterprise branding
    get "/api/v1/enterprises/:enterprise_id/branding" $ do
        userId <- requireUserId
        enterpriseId <- param "enterprise_id"
        result <- liftIO $ handleGetEnterpriseBranding service enterpriseId
        case result of
            Left err -> handleServiceError err
            Right response -> json response

    -- Update enterprise settings
    put "/api/v1/enterprises/:enterprise_id/settings" $ do
        userId <- requireUserId
        enterpriseId <- param "enterprise_id"
        req <- jsonData
        result <- liftIO $ handleUpdateEnterpriseSettings service enterpriseId req
        case result of
            Left err -> handleServiceError err
            Right response -> json response

    -- Get enterprise settings
    get "/api/v1/enterprises/:enterprise_id/settings" $ do
        userId <- requireUserId
        enterpriseId <- param "enterprise_id"
        result <- liftIO $ handleGetEnterpriseSettings service enterpriseId
        case result of
            Left err -> handleServiceError err
            Right response -> json response
