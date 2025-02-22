-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Auth.LDAP
    ( LDAPAuth(..)
    , initLDAPAuth
    , authenticate
    , validateCredentials
    , searchUser
    , searchGroups
    , syncGroups
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Exception (try, throwIO)
import Data.Pool
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime)
import qualified LDAP as L
import qualified LDAP.Search as L
import qualified LDAP.Modify as L

import Gerrit.Auth.Types

-- | LDAP authentication manager
data LDAPAuth = LDAPAuth
    { laConfig :: LDAPConfig
    , laPool :: Pool L.LDAP
    }

-- | Initialize LDAP authentication
initLDAPAuth :: MonadIO m => LDAPConfig -> m LDAPAuth
initLDAPAuth config = liftIO $ do
    -- Create connection pool for each server
    pools <- mapM (createServerPool config) (ldapServers config)
    -- Use the pool from the highest priority server
    let pool = head $ sortOn (ldapPriority . fst) pools
    pure $ LDAPAuth config (snd pool)

-- | Create a connection pool for a server
createServerPool :: LDAPConfig -> LDAPServer -> IO (LDAPServer, Pool L.LDAP)
createServerPool config server = do
    pool <- createPool
        (connect config server)    -- Create connection
        L.ldapClose               -- Close connection
        1                         -- Stripes
        300                       -- Idle timeout (seconds)
        (ldapPoolSize config)     -- Max connections
    pure (server, pool)

-- | Connect to LDAP server
connect :: LDAPConfig -> LDAPServer -> IO L.LDAP
connect config server = do
    ldap <- L.ldapInit (T.unpack $ ldapHost server) (ldapPort server)
    when (ldapTLS config) $
        L.ldapStartTLS ldap
    -- Bind with service account
    L.ldapSimpleBind ldap
        (T.unpack $ ldapBindDN config)
        (T.unpack $ ldapBindPassword config)
    pure ldap

-- | Authenticate user
authenticate :: MonadIO m => LDAPAuth -> Text -> Text -> m AuthResult
authenticate auth username password = liftIO $ do
    -- Search for user
    mUser <- searchUser auth username
    case mUser of
        Just user -> do
            -- Validate credentials
            valid <- validateCredentials auth username password
            if valid
                then do
                    -- Create auth token
                    now <- getCurrentTime
                    let token = AuthToken
                            { tokenValue = "ldap_" <> userId user
                            , tokenType = BearerToken
                            , tokenExpiry = addUTCTime (60 * 60) now  -- 1 hour
                            , tokenScopes = ["*"]
                            }
                    -- Sync groups if enabled
                    when (ldapGroupSync $ laConfig auth) $
                        void $ syncGroups auth user
                    pure $ AuthSuccess token user
                else
                    pure $ AuthFailure InvalidCredentials
        Nothing ->
            pure $ AuthFailure InvalidCredentials

-- | Validate user credentials
validateCredentials :: MonadIO m => LDAPAuth -> Text -> Text -> m Bool
validateCredentials auth username password = liftIO $ do
    -- Get user DN
    mDN <- getUserDN auth username
    case mDN of
        Just dn -> withResource (laPool auth) $ \ldap -> do
            -- Try to bind with user credentials
            result <- try $ L.ldapSimpleBind ldap (T.unpack dn) (T.unpack password)
            case result of
                Right _ -> do
                    -- Rebind with service account
                    L.ldapSimpleBind ldap
                        (T.unpack $ ldapBindDN $ laConfig auth)
                        (T.unpack $ ldapBindPassword $ laConfig auth)
                    pure True
                Left (_ :: L.LDAPError) ->
                    pure False
        Nothing -> pure False

-- | Search for user
searchUser :: MonadIO m => LDAPAuth -> Text -> m (Maybe User)
searchUser auth username = liftIO $
    withResource (laPool auth) $ \ldap -> do
        let config = laConfig auth
            attrs = ldapAttributes config
            base = ldapUserBaseDN config
            filter' = substituteFilter (ldapUserFilter config) [("username", username)]

        result <- L.ldapSearch ldap
            (T.unpack base)
            L.LdapScopeSubtree
            (T.unpack filter')
            [T.unpack $ attrUsername attrs
            ,T.unpack $ attrEmail attrs
            ,T.unpack $ attrFullName attrs
            ,T.unpack $ attrGroups attrs
            ]
            False

        case result of
            [entry] -> do
                now <- getCurrentTime
                let getAttr name = head $ L.getAttrValue name entry
                pure $ Just User
                    { userId = username
                    , userName = T.pack $ getAttr $ T.unpack $ attrUsername attrs
                    , userEmail = T.pack $ getAttr $ T.unpack $ attrEmail attrs
                    , userFullName = T.pack $ getAttr $ T.unpack $ attrFullName attrs
                    , userRoles = [Guest]  -- Default role
                    , userGroups = []      -- Will be filled by syncGroups
                    , userProvider = LDAPProvider $ laConfig auth
                    , userCreated = now
                    , userLastLogin = now
                    , userMFAEnabled = False
                    }
            _ -> pure Nothing

-- | Search for user's groups
searchGroups :: MonadIO m => LDAPAuth -> User -> m [Text]
searchGroups auth user = liftIO $
    withResource (laPool auth) $ \ldap -> do
        let config = laConfig auth
            base = ldapGroupBaseDN config
            filter' = substituteFilter (ldapGroupFilter config)
                [("username", userName user)
                ,("dn", userDN user)
                ]

        result <- L.ldapSearch ldap
            (T.unpack base)
            L.LdapScopeSubtree
            (T.unpack filter')
            ["cn"]
            False

        pure $ map (T.pack . head . L.getAttrValue "cn") result

-- | Synchronize user's groups
syncGroups :: MonadIO m => LDAPAuth -> User -> m User
syncGroups auth user = liftIO $ do
    groups <- searchGroups auth user
    pure $ user { userGroups = groups }

-- Helper functions

-- | Get user's DN
getUserDN :: MonadIO m => LDAPAuth -> Text -> m (Maybe Text)
getUserDN auth username = liftIO $
    withResource (laPool auth) $ \ldap -> do
        let config = laConfig auth
            base = ldapUserBaseDN config
            filter' = substituteFilter (ldapUserFilter config) [("username", username)]

        result <- L.ldapSearch ldap
            (T.unpack base)
            L.LdapScopeSubtree
            (T.unpack filter')
            ["dn"]
            False

        pure $ case result of
            [entry] -> Just $ T.pack $ L.getDN entry
            _ -> Nothing

-- | Substitute variables in LDAP filter
substituteFilter :: Text -> [(Text, Text)] -> Text
substituteFilter filter' vars =
    foldr (\(var, val) acc -> T.replace (T.concat ["%", var, "%"]) val acc) filter' vars
