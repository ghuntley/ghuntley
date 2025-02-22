-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Auth
    ( handleLDAPLogin
    , handleOAuthLogin
    , handleOAuthCallback
    , handleOAuthRefresh
    , handleTokenValidate
    , handleTokenRevoke
    , handleTokenRefresh
    , handleGetCurrentUser
    , handleGetUser
    , handleUpdateUser
    , handleDeleteUser
    , handleEnableMFA
    , handleVerifyMFA
    , handleDisableMFA
    , handleGetBackupCodes
    , handleRegenerateBackupCodes
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime)
import Network.HTTP.Types.Status
import Web.Yesod

import Gerrit.Auth
import Gerrit.Auth.Types
import Gerrit.Api.Types

-- | Handle LDAP login
handleLDAPLogin :: AuthSystem -> LoginRequest -> Handler Value
handleLDAPLogin auth LoginRequest{..} = do
    result <- liftIO $ authenticate auth
        (LDAPProvider defaultLDAPConfig)
        loginUsername
        loginPassword

    case result of
        AuthSuccess token user ->
            return $ object
                [ "token" .= tokenValue token
                , "type" .= show (tokenType token)
                , "expires" .= tokenExpiry token
                , "user" .= user
                ]
        AuthFailure err ->
            sendResponseStatus status401 $ object
                [ "error" .= show err
                ]
        AuthChallenge challenge ->
            sendResponseStatus status403 $ object
                [ "challenge" .= show challenge
                ]

-- | Handle OAuth login
handleOAuthLogin :: AuthSystem -> Text -> Handler Value
handleOAuthLogin auth provider = do
    let config = defaultOAuthConfig { oauthProvider = read $ T.unpack provider }
    case Map.lookup (oauthProvider config) (asOAuth auth) of
        Just oauthAuth -> do
            (url, state) <- liftIO $ OAuth.getAuthorizationUrl oauthAuth
            return $ object
                [ "url" .= url
                , "state" .= state
                ]
        Nothing ->
            sendResponseStatus status400 $ object
                [ "error" .= ("Invalid OAuth provider" :: Text)
                ]

-- | Handle OAuth callback
handleOAuthCallback :: AuthSystem -> Text -> Text -> Text -> Handler Value
handleOAuthCallback auth provider code state = do
    let config = defaultOAuthConfig { oauthProvider = read $ T.unpack provider }
    case Map.lookup (oauthProvider config) (asOAuth auth) of
        Just oauthAuth -> do
            result <- liftIO $ OAuth.handleCallback oauthAuth code state
            case result of
                AuthSuccess token user ->
                    return $ object
                        [ "token" .= tokenValue token
                        , "type" .= show (tokenType token)
                        , "expires" .= tokenExpiry token
                        , "user" .= user
                        ]
                AuthFailure err ->
                    sendResponseStatus status401 $ object
                        [ "error" .= show err
                        ]
                AuthChallenge challenge ->
                    sendResponseStatus status403 $ object
                        [ "challenge" .= show challenge
                        ]
        Nothing ->
            sendResponseStatus status400 $ object
                [ "error" .= ("Invalid OAuth provider" :: Text)
                ]

-- | Handle OAuth token refresh
handleOAuthRefresh :: AuthSystem -> Text -> Text -> Handler Value
handleOAuthRefresh auth provider refreshToken = do
    let config = defaultOAuthConfig { oauthProvider = read $ T.unpack provider }
    case Map.lookup (oauthProvider config) (asOAuth auth) of
        Just oauthAuth -> do
            mToken <- liftIO $ OAuth.refreshToken oauthAuth refreshToken
            case mToken of
                Just token ->
                    return $ object
                        [ "token" .= tokenValue token
                        , "type" .= show (tokenType token)
                        , "expires" .= tokenExpiry token
                        ]
                Nothing ->
                    sendResponseStatus status401 $ object
                        [ "error" .= ("Invalid refresh token" :: Text)
                        ]
        Nothing ->
            sendResponseStatus status400 $ object
                [ "error" .= ("Invalid OAuth provider" :: Text)
                ]

-- | Handle token validation
handleTokenValidate :: AuthSystem -> Text -> Handler Value
handleTokenValidate auth token = do
    valid <- liftIO $ validateToken auth token
    return $ object
        [ "valid" .= valid
        ]

-- | Handle token revocation
handleTokenRevoke :: AuthSystem -> Text -> Handler Value
handleTokenRevoke auth token = do
    success <- liftIO $ revokeToken auth token
    return $ object
        [ "success" .= success
        ]

-- | Handle token refresh
handleTokenRefresh :: AuthSystem -> Text -> Handler Value
handleTokenRefresh auth refreshToken = do
    mToken <- liftIO $ refreshToken auth refreshToken
    case mToken of
        Just token ->
            return $ object
                [ "token" .= tokenValue token
                , "type" .= show (tokenType token)
                , "expires" .= tokenExpiry token
                ]
        Nothing ->
            sendResponseStatus status401 $ object
                [ "error" .= ("Invalid refresh token" :: Text)
                ]

-- | Handle get current user
handleGetCurrentUser :: AuthSystem -> Text -> Handler Value
handleGetCurrentUser auth token = do
    mUser <- liftIO $ getCurrentUser auth token
    case mUser of
        Just user ->
            return $ toJSON user
        Nothing ->
            sendResponseStatus status401 $ object
                [ "error" .= ("Invalid token" :: Text)
                ]

-- | Handle get user by ID
handleGetUser :: AuthSystem -> Text -> Handler Value
handleGetUser auth userId = do
    mUser <- liftIO $ getUser auth userId
    case mUser of
        Just user ->
            return $ toJSON user
        Nothing ->
            sendResponseStatus status404 $ object
                [ "error" .= ("User not found" :: Text)
                ]

-- | Handle update user
handleUpdateUser :: AuthSystem -> Text -> UpdateUserRequest -> Handler Value
handleUpdateUser auth userId UpdateUserRequest{..} = do
    mUser <- liftIO $ getUser auth userId
    case mUser of
        Just user -> do
            let updatedUser = user
                    { userName = updateUserName
                    , userEmail = updateUserEmail
                    , userFullName = updateUserFullName
                    , userRoles = updateUserRoles
                    , userGroups = updateUserGroups
                    , userMFAEnabled = updateUserMFAEnabled
                    }
            liftIO $ updateUser auth updatedUser
            return $ toJSON updatedUser
        Nothing ->
            sendResponseStatus status404 $ object
                [ "error" .= ("User not found" :: Text)
                ]

-- | Handle delete user
handleDeleteUser :: AuthSystem -> Text -> Handler Value
handleDeleteUser auth userId = do
    liftIO $ deleteUser auth userId
    return $ object
        [ "success" .= True
        ]

-- | Handle enable MFA
handleEnableMFA :: AuthSystem -> Text -> EnableMFARequest -> Handler Value
handleEnableMFA auth userId EnableMFARequest{..} = do
    mUser <- liftIO $ getUser auth userId
    case mUser of
        Just user -> do
            (secret, backupCodes) <- liftIO $ enableMFA auth user enableMFAType enableMFAName
            return $ object
                [ "secret" .= secret
                , "backup_codes" .= backupCodes
                ]
        Nothing ->
            sendResponseStatus status404 $ object
                [ "error" .= ("User not found" :: Text)
                ]

-- | Handle verify MFA
handleVerifyMFA :: AuthSystem -> Text -> Text -> Handler Value
handleVerifyMFA auth userId code = do
    mUser <- liftIO $ getUser auth userId
    case mUser of
        Just user -> do
            valid <- liftIO $ verifyMFA auth user code
            return $ object
                [ "valid" .= valid
                ]
        Nothing ->
            sendResponseStatus status404 $ object
                [ "error" .= ("User not found" :: Text)
                ]

-- | Handle disable MFA
handleDisableMFA :: AuthSystem -> Text -> Text -> Handler Value
handleDisableMFA auth userId code = do
    mUser <- liftIO $ getUser auth userId
    case mUser of
        Just user -> do
            success <- liftIO $ disableMFA auth user code
            return $ object
                [ "success" .= success
                ]
        Nothing ->
            sendResponseStatus status404 $ object
                [ "error" .= ("User not found" :: Text)
                ]

-- | Handle get backup codes
handleGetBackupCodes :: AuthSystem -> Text -> Handler Value
handleGetBackupCodes auth userId = do
    mUser <- liftIO $ getUser auth userId
    case mUser of
        Just user -> do
            codes <- liftIO $ getBackupCodes auth user
            return $ object
                [ "backup_codes" .= codes
                ]
        Nothing ->
            sendResponseStatus status404 $ object
                [ "error" .= ("User not found" :: Text)
                ]

-- | Handle regenerate backup codes
handleRegenerateBackupCodes :: AuthSystem -> Text -> Handler Value
handleRegenerateBackupCodes auth userId = do
    mUser <- liftIO $ getUser auth userId
    case mUser of
        Just user -> do
            codes <- liftIO $ regenerateBackupCodes auth user
            return $ object
                [ "backup_codes" .= codes
                ]
        Nothing ->
            sendResponseStatus status404 $ object
                [ "error" .= ("User not found" :: Text)
                ]

-- Helper functions

-- | Default LDAP configuration
defaultLDAPConfig :: LDAPConfig
defaultLDAPConfig = LDAPConfig
    { ldapServers = []
    , ldapBindDN = ""
    , ldapBindPassword = ""
    , ldapUserBaseDN = ""
    , ldapGroupBaseDN = ""
    , ldapUserFilter = ""
    , ldapGroupFilter = ""
    , ldapAttributes = defaultLDAPAttributes
    , ldapGroupSync = False
    , ldapTLS = True
    , ldapPoolSize = 10
    }

-- | Default LDAP attributes
defaultLDAPAttributes :: LDAPAttributes
defaultLDAPAttributes = LDAPAttributes
    { attrUsername = "uid"
    , attrEmail = "mail"
    , attrFullName = "cn"
    , attrGroups = "memberOf"
    }

-- | Default OAuth configuration
defaultOAuthConfig :: OAuthConfig
defaultOAuthConfig = OAuthConfig
    { oauthProvider = GitHub
    , oauthClientId = ""
    , oauthClientSecret = ""
    , oauthRedirectUri = ""
    , oauthScopes = []
    , oauthAuthEndpoint = ""
    , oauthTokenEndpoint = ""
    , oauthUserInfoEndpoint = ""
    , oauthPKCE = True
    , oauthRoleMapping = Map.empty
    }

-- | Login request
data LoginRequest = LoginRequest
    { loginUsername :: Text
    , loginPassword :: Text
    }

-- | Update user request
data UpdateUserRequest = UpdateUserRequest
    { updateUserName :: Text
    , updateUserEmail :: Text
    , updateUserFullName :: Text
    , updateUserRoles :: [Role]
    , updateUserGroups :: [Text]
    , updateUserMFAEnabled :: Bool
    }

-- | Enable MFA request
data EnableMFARequest = EnableMFARequest
    { enableMFAType :: Text
    , enableMFAName :: Text
    }
