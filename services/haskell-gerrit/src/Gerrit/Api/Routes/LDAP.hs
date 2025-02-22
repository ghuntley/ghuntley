-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.LDAP
    ( ldapRoutes
    ) where

import Web.Scotty.Trans

import Gerrit.Api.Error (ApiError)
import Gerrit.Api.Handlers.LDAP
import Gerrit.Services.LDAPService (LDAPService)

-- | LDAP routes
ldapRoutes :: LDAPService -> ScottyT ApiError IO ()
ldapRoutes service = do
    -- LDAP Configuration
    post "/api/ldap/configs" $
        handleCreateLDAPConfig service

    get "/api/ldap/configs" $
        handleListLDAPConfigs service

    get "/api/ldap/configs/:config_id" $
        handleGetLDAPConfig service

    put "/api/ldap/configs/:config_id" $
        handleUpdateLDAPConfig service

    post "/api/ldap/configs/:config_id/enable" $
        handleEnableLDAPConfig service

    post "/api/ldap/configs/:config_id/disable" $
        handleDisableLDAPConfig service

    post "/api/ldap/configs/:config_id/test" $
        handleTestLDAPConnection service

    -- LDAP Synchronization
    post "/api/ldap/configs/:config_id/sync/users" $
        handleSyncUsers service

    post "/api/ldap/configs/:config_id/sync/groups" $
        handleSyncGroups service
