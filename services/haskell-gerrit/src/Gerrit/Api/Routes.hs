-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}

module Gerrit.Api.Routes where

import Data.Text (Text)
import Yesod

import Gerrit.Api.Handlers.Auth
import Gerrit.Auth.Types

data App = App
    { appAuthSystem :: AuthSystem
    }

mkYesod "App" [parseRoutes|
/api/auth AuthR:
    /ldap/login LDAPLoginR POST
    /oauth/#Text/login OAuthLoginR GET
    /oauth/#Text/callback OAuthCallbackR GET
    /oauth/#Text/refresh OAuthRefreshR POST
    /token/validate TokenValidateR POST
    /token/revoke TokenRevokeR POST
    /token/refresh TokenRefreshR POST
    /user UserR:
        / CurrentUserR GET
        /#Text UserByIdR:
            / UserDetailsR GET PUT DELETE
            /mfa MFASettingsR:
                /enable EnableMFAR POST
                /verify VerifyMFAR POST
                /disable DisableMFAR POST
                /backup-codes BackupCodesR:
                    / BackupCodesListR GET
                    /regenerate RegenerateBackupCodesR POST
|]

instance Yesod App where
    -- Add authentication and authorization logic here
    isAuthorized _ _ = return Authorized

-- | LDAP login handler
postLDAPLoginR :: Handler Value
postLDAPLoginR = do
    app <- getYesod
    loginReq <- requireCheckJsonBody
    handleLDAPLogin (appAuthSystem app) loginReq

-- | OAuth login handler
getOAuthLoginR :: Text -> Handler Value
getOAuthLoginR provider = do
    app <- getYesod
    handleOAuthLogin (appAuthSystem app) provider

-- | OAuth callback handler
getOAuthCallbackR :: Text -> Handler Value
getOAuthCallbackR provider = do
    app <- getYesod
    code <- requireGetParam "code"
    state <- requireGetParam "state"
    handleOAuthCallback (appAuthSystem app) provider code state

-- | OAuth refresh handler
postOAuthRefreshR :: Text -> Handler Value
postOAuthRefreshR provider = do
    app <- getYesod
    refreshToken <- requireCheckJsonBody
    handleOAuthRefresh (appAuthSystem app) provider refreshToken

-- | Token validation handler
postTokenValidateR :: Handler Value
postTokenValidateR = do
    app <- getYesod
    token <- requireCheckJsonBody
    handleTokenValidate (appAuthSystem app) token

-- | Token revocation handler
postTokenRevokeR :: Handler Value
postTokenRevokeR = do
    app <- getYesod
    token <- requireCheckJsonBody
    handleTokenRevoke (appAuthSystem app) token

-- | Token refresh handler
postTokenRefreshR :: Handler Value
postTokenRefreshR = do
    app <- getYesod
    refreshToken <- requireCheckJsonBody
    handleTokenRefresh (appAuthSystem app) refreshToken

-- | Get current user handler
getCurrentUserR :: Handler Value
getCurrentUserR = do
    app <- getYesod
    token <- requireCheckJsonBody
    handleGetCurrentUser (appAuthSystem app) token

-- | Get user by ID handler
getUserDetailsR :: Text -> Handler Value
getUserDetailsR userId = do
    app <- getYesod
    handleGetUser (appAuthSystem app) userId

-- | Update user handler
putUserDetailsR :: Text -> Handler Value
putUserDetailsR userId = do
    app <- getYesod
    updateReq <- requireCheckJsonBody
    handleUpdateUser (appAuthSystem app) userId updateReq

-- | Delete user handler
deleteUserDetailsR :: Text -> Handler Value
deleteUserDetailsR userId = do
    app <- getYesod
    handleDeleteUser (appAuthSystem app) userId

-- | Enable MFA handler
postEnableMFAR :: Text -> Handler Value
postEnableMFAR userId = do
    app <- getYesod
    enableReq <- requireCheckJsonBody
    handleEnableMFA (appAuthSystem app) userId enableReq

-- | Verify MFA handler
postVerifyMFAR :: Text -> Handler Value
postVerifyMFAR userId = do
    app <- getYesod
    code <- requireCheckJsonBody
    handleVerifyMFA (appAuthSystem app) userId code

-- | Disable MFA handler
postDisableMFAR :: Text -> Handler Value
postDisableMFAR userId = do
    app <- getYesod
    code <- requireCheckJsonBody
    handleDisableMFA (appAuthSystem app) userId code

-- | Get backup codes handler
getBackupCodesListR :: Text -> Handler Value
getBackupCodesListR userId = do
    app <- getYesod
    handleGetBackupCodes (appAuthSystem app) userId

-- | Regenerate backup codes handler
postRegenerateBackupCodesR :: Text -> Handler Value
postRegenerateBackupCodesR userId = do
    app <- getYesod
    handleRegenerateBackupCodes (appAuthSystem app) userId
