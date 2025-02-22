-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Auth
    ( AuthSystem(..)
    , initAuthSystem
    , authenticate
    , validateToken
    , revokeToken
    , refreshToken
    , getUser
    , updateUser
    , deleteUser
    , listUsers
    , module Gerrit.Auth.Types
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Exception (try)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime)
import Database.PostgreSQL.Simple (Connection)

import Gerrit.Auth.Types
import Gerrit.Auth.LDAP (LDAPAuth)
import qualified Gerrit.Auth.LDAP as LDAP
import Gerrit.Auth.OAuth (OAuthAuth)
import qualified Gerrit.Auth.OAuth as OAuth
import Gerrit.Middleware.CSRF (CSRFConfig(..), defaultCSRFConfig, generateCSRFToken)

-- | Authentication system
data AuthSystem = AuthSystem
    { asLDAP :: Maybe LDAPAuth
    , asOAuth :: Map OAuthProvider OAuthAuth
    , asConn :: Connection
    , asCSRFConfig :: CSRFConfig
    }

-- | Initialize authentication system
initAuthSystem :: MonadIO m => Maybe LDAPConfig -> [OAuthConfig] -> Connection -> m AuthSystem
initAuthSystem mldapConfig oauthConfigs conn = liftIO $ do
    -- Initialize LDAP if configured
    ldapAuth <- mapM LDAP.initLDAPAuth mldapConfig

    -- Initialize OAuth providers
    oauthAuths <- foldM
        (\acc config -> do
            auth <- OAuth.initOAuthAuth config
            pure $ Map.insert (oauthProvider config) auth acc)
        Map.empty
        oauthConfigs

    pure $ AuthSystem
        { asLDAP = ldapAuth
        , asOAuth = oauthAuths
        , asConn = conn
        , asCSRFConfig = defaultCSRFConfig
        }

-- | Authenticate user
authenticate :: MonadIO m => AuthSystem -> AuthProvider -> Text -> Text -> m AuthResult
authenticate auth provider username password = do
    result <- case provider of
        LDAPProvider config ->
            case asLDAP auth of
                Just ldapAuth ->
                    LDAP.authenticate ldapAuth username password
                Nothing ->
                    pure $ AuthFailure $ ConfigurationError "LDAP not configured"

        OAuthProvider config ->
            case Map.lookup (oauthProvider config) (asOAuth auth) of
                Just oauthAuth ->
                    OAuth.handleCallback oauthAuth username password
                Nothing ->
                    pure $ AuthFailure $ ConfigurationError "OAuth provider not configured"

        LocalProvider ->
            authenticateLocal auth username password

    -- Generate CSRF token for successful authentications
    case result of
        AuthSuccess token user -> do
            csrfToken <- generateCSRFToken (asCSRFConfig auth)
            pure $ AuthSuccess (token { tokenCSRFToken = Just csrfToken }) user
        _ -> pure result

-- | Validate authentication token
validateToken :: MonadIO m => AuthSystem -> AuthToken -> Maybe Text -> m Bool
validateToken auth token mCsrfToken = do
    -- First validate the token itself
    isValid <- case tokenType token of
        BearerToken -> validateBearerToken auth token
        JWTToken -> validateJWTToken auth token
        APIToken -> validateAPIToken auth token

    -- Then validate CSRF token if present
    pure $ isValid && validateCSRFTokenMatch token mCsrfToken

-- | Helper function to validate CSRF token match
validateCSRFTokenMatch :: AuthToken -> Maybe Text -> Bool
validateCSRFTokenMatch token mCsrfToken =
    case (tokenCSRFToken token, mCsrfToken) of
        (Nothing, _) -> True  -- No CSRF token required
        (Just expected, Just actual) -> expected == actual
        _ -> False

-- | Revoke authentication token
revokeToken :: MonadIO m => AuthSystem -> AuthToken -> m Bool
revokeToken auth token = case tokenType token of
    BearerToken -> revokeBearerToken auth token
    JWTToken -> revokeJWTToken auth token
    APIToken -> revokeAPIToken auth token

-- | Refresh authentication token
refreshToken :: MonadIO m => AuthSystem -> AuthToken -> m (Maybe AuthToken)
refreshToken auth token = case tokenType token of
    BearerToken -> refreshBearerToken auth token
    JWTToken -> refreshJWTToken auth token
    APIToken -> pure Nothing  -- API tokens cannot be refreshed

-- | Get user by ID
getUser :: MonadIO m => AuthSystem -> Text -> m (Maybe User)
getUser auth userId = liftIO $ do
    let sql = "SELECT * FROM users WHERE id = ?"
    rows <- query (asConn auth) sql (Only userId)
    pure $ case rows of
        [user] -> Just user
        _ -> Nothing

-- | Update user
updateUser :: MonadIO m => AuthSystem -> User -> m ()
updateUser auth user = liftIO $ do
    let sql = "UPDATE users SET name = ?, email = ?, full_name = ?, roles = ?, \
              \groups = ?, provider = ?, last_login = ?, mfa_enabled = ? \
              \WHERE id = ?"
    void $ execute (asConn auth) sql
        ( userName user
        , userEmail user
        , userFullName user
        , map show (userRoles user)
        , userGroups user
        , show (userProvider user)
        , userLastLogin user
        , userMFAEnabled user
        , userId user
        )

-- | Delete user
deleteUser :: MonadIO m => AuthSystem -> Text -> m ()
deleteUser auth userId = liftIO $ do
    let sql = "DELETE FROM users WHERE id = ?"
    void $ execute (asConn auth) sql (Only userId)

-- | List all users
listUsers :: MonadIO m => AuthSystem -> m [User]
listUsers auth = liftIO $ do
    let sql = "SELECT * FROM users"
    query_ (asConn auth) sql

-- Helper functions

-- | Authenticate with local database
authenticateLocal :: MonadIO m => AuthSystem -> Text -> Text -> m AuthResult
authenticateLocal auth username password = liftIO $ do
    let sql = "SELECT * FROM users WHERE name = ? AND password_hash = crypt(?, password_hash)"
    rows <- query (asConn auth) sql (username, password)
    case rows of
        [user] -> do
            now <- getCurrentTime
            let token = AuthToken
                    { tokenValue = "local_" <> userId user
                    , tokenType = BearerToken
                    , tokenExpiry = addUTCTime (60 * 60) now  -- 1 hour
                    , tokenScopes = ["*"]
                    }
            pure $ AuthSuccess token user
        _ ->
            pure $ AuthFailure InvalidCredentials

-- | Validate bearer token
validateBearerToken :: MonadIO m => AuthSystem -> AuthToken -> m Bool
validateBearerToken auth token = case T.split (== '_') (tokenValue token) of
    ["ldap", _] ->
        case asLDAP auth of
            Just ldapAuth -> LDAP.validateToken ldapAuth token
            Nothing -> pure False
    ["oauth", provider, _] ->
        case Map.lookup (read $ T.unpack provider) (asOAuth auth) of
            Just oauthAuth -> OAuth.validateToken oauthAuth token
            Nothing -> pure False
    ["local", _] ->
        validateLocalToken auth token
    _ ->
        pure False

-- | Validate JWT token
validateJWTToken :: MonadIO m => AuthSystem -> AuthToken -> m Bool
validateJWTToken = undefined  -- TODO: Implement JWT validation

-- | Validate API token
validateAPIToken :: MonadIO m => AuthSystem -> AuthToken -> m Bool
validateAPIToken = undefined  -- TODO: Implement API token validation

-- | Revoke bearer token
revokeBearerToken :: MonadIO m => AuthSystem -> AuthToken -> m Bool
revokeBearerToken auth token = case T.split (== '_') (tokenValue token) of
    ["ldap", _] ->
        -- LDAP tokens don't need explicit revocation
        pure True
    ["oauth", provider, _] ->
        case Map.lookup (read $ T.unpack provider) (asOAuth auth) of
            Just oauthAuth -> OAuth.revokeToken oauthAuth token
            Nothing -> pure False
    ["local", _] ->
        revokeLocalToken auth token
    _ ->
        pure False

-- | Revoke JWT token
revokeJWTToken :: MonadIO m => AuthSystem -> AuthToken -> m Bool
revokeJWTToken = undefined  -- TODO: Implement JWT revocation

-- | Revoke API token
revokeAPIToken :: MonadIO m => AuthSystem -> AuthToken -> m Bool
revokeAPIToken = undefined  -- TODO: Implement API token revocation

-- | Refresh bearer token
refreshBearerToken :: MonadIO m => AuthSystem -> AuthToken -> m (Maybe AuthToken)
refreshBearerToken auth token = case T.split (== '_') (tokenValue token) of
    ["ldap", _] ->
        -- LDAP tokens don't support refresh
        pure Nothing
    ["oauth", provider, _] ->
        case Map.lookup (read $ T.unpack provider) (asOAuth auth) of
            Just oauthAuth -> OAuth.refreshToken oauthAuth token
            Nothing -> pure Nothing
    ["local", _] ->
        -- Local tokens don't support refresh
        pure Nothing
    _ ->
        pure Nothing

-- | Refresh JWT token
refreshJWTToken :: MonadIO m => AuthSystem -> AuthToken -> m (Maybe AuthToken)
refreshJWTToken = undefined  -- TODO: Implement JWT refresh

-- | Validate local token
validateLocalToken :: MonadIO m => AuthSystem -> AuthToken -> m Bool
validateLocalToken auth token = liftIO $ do
    now <- getCurrentTime
    pure $ tokenExpiry token > now

-- | Revoke local token
revokeLocalToken :: MonadIO m => AuthSystem -> AuthToken -> m Bool
revokeLocalToken = undefined  -- TODO: Implement local token revocation
