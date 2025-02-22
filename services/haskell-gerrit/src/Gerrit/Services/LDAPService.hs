-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.LDAPService
    ( -- * Types
      LDAPService(..)
    , LDAPError(..)
      -- * Service Operations
    , initLDAPService
    , authenticateUser
    , synchronizeUsers
    , synchronizeGroups
    , validateLDAPConfig
    , testLDAPConnection
    ) where

import Control.Exception (try)
import Control.Monad (void, when, unless, forM_)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import LDAP
import qualified LDAP.Search as Search
import qualified LDAP.Modify as Modify

import Gerrit.Models.LDAPConfig
import Gerrit.Models.User (User(..))
import qualified Gerrit.Models.User as User
import Gerrit.Models.Permission (Role(..))
import qualified Gerrit.Models.Permission as Permission
import Gerrit.Services.NotificationService (NotificationService)
import qualified Gerrit.Services.NotificationService as Notification
import Gerrit.Services.MetricsService (MetricsService)
import qualified Gerrit.Services.MetricsService as Metrics

-- | LDAP service errors
data LDAPError
    = ConfigNotFound Text
    | ConnectionError Text
    | AuthenticationError Text
    | SyncError Text
    | ValidationError Text
    | DatabaseError Text
    deriving (Show, Eq)

-- | LDAP service
data LDAPService = LDAPService
    { ldapPool :: ConnectionPool
    , ldapNotificationService :: NotificationService
    , ldapMetricsService :: MetricsService
    }

-- | Initialize LDAP service
initLDAPService :: ConnectionPool -> NotificationService -> MetricsService -> LDAPService
initLDAPService pool notificationSvc metricsSvc = LDAPService
    { ldapPool = pool
    , ldapNotificationService = notificationSvc
    , ldapMetricsService = metricsSvc
    }

-- | Authenticate user against LDAP
authenticateUser :: MonadIO m
                => LDAPService
                -> Text  -- ^ Config ID
                -> Text  -- ^ Username
                -> Text  -- ^ Password
                -> m (Either LDAPError User)
authenticateUser LDAPService{..} configId username password = do
    -- Get LDAP config
    mConfig <- runSqlPool (getBy $ UniqueLDAPConfigId configId) ldapPool
    case mConfig of
        Nothing -> return $ Left $ ConfigNotFound configId
        Just (Entity _ config) -> do
            -- Connect to LDAP server
            result <- try $ liftIO $ do
                ldap <- initializeLDAP config
                -- Bind with user credentials
                let userDN = buildUserDN config username
                bindLDAP ldap userDN password
                -- Search for user attributes
                attrs <- Search.search ldap (ldapConfigBaseDN config) Search.WholeSubtree
                    (buildUserFilter config username) ["cn", "mail", "displayName"]
                case attrs of
                    [] -> return $ Left $ AuthenticationError "User not found"
                    (entry:_) -> do
                        -- Create or update user
                        let user = buildUser entry username
                        Right <$> runSqlPool (User.createOrUpdateUser user) ldapPool

            case result of
                Left err -> return $ Left $ ConnectionError $ T.pack $ show err
                Right res -> return res

-- | Synchronize users from LDAP
synchronizeUsers :: MonadIO m
                => LDAPService
                -> Text  -- ^ Config ID
                -> m (Either LDAPError Int)
synchronizeUsers LDAPService{..} configId = do
    -- Get LDAP config
    mConfig <- runSqlPool (getBy $ UniqueLDAPConfigId configId) ldapPool
    case mConfig of
        Nothing -> return $ Left $ ConfigNotFound configId
        Just (Entity configKey config) -> do
            -- Connect to LDAP server
            result <- try $ liftIO $ do
                ldap <- initializeLDAP config
                -- Bind with service account
                bindLDAP ldap (ldapConfigBindDN config) (ldapConfigBindPassword config)
                -- Search for all users
                entries <- Search.search ldap (ldapConfigBaseDN config) Search.WholeSubtree
                    (ldapConfigUserFilter config) ["cn", "mail", "displayName"]
                -- Create or update users
                count <- foldM (\acc entry -> do
                    void $ runSqlPool (User.createOrUpdateUser $ buildUser entry "") ldapPool
                    return $ acc + 1) 0 entries
                -- Update last sync time
                now <- getCurrentTime
                runSqlPool (update configKey [LDAPConfigLastSync =. Just now]) ldapPool
                return count

            case result of
                Left err -> return $ Left $ ConnectionError $ T.pack $ show err
                Right count -> do
                    -- Send notification
                    void $ Notification.sendNotification ldapNotificationService
                        "ldap_users_synced"
                        configId
                        "system"

                    -- Record metrics
                    void $ Metrics.recordMetric ldapMetricsService
                        "ldap_users_synced"
                        count

                    return $ Right count

-- | Synchronize groups from LDAP
synchronizeGroups :: MonadIO m
                 => LDAPService
                 -> Text  -- ^ Config ID
                 -> m (Either LDAPError Int)
synchronizeGroups LDAPService{..} configId = do
    -- Get LDAP config
    mConfig <- runSqlPool (getBy $ UniqueLDAPConfigId configId) ldapPool
    case mConfig of
        Nothing -> return $ Left $ ConfigNotFound configId
        Just (Entity configKey config) -> do
            case ldapConfigGroupFilter config of
                Nothing -> return $ Right 0
                Just groupFilter -> do
                    -- Connect to LDAP server
                    result <- try $ liftIO $ do
                        ldap <- initializeLDAP config
                        -- Bind with service account
                        bindLDAP ldap (ldapConfigBindDN config) (ldapConfigBindPassword config)
                        -- Search for all groups
                        entries <- Search.search ldap (ldapConfigBaseDN config) Search.WholeSubtree
                            groupFilter ["cn", "member"]
                        -- Update group mappings
                        count <- foldM (\acc entry -> do
                            void $ updateGroupMapping config entry
                            return $ acc + 1) 0 entries
                        -- Update last sync time
                        now <- getCurrentTime
                        runSqlPool (update configKey [LDAPConfigLastSync =. Just now]) ldapPool
                        return count

                    case result of
                        Left err -> return $ Left $ ConnectionError $ T.pack $ show err
                        Right count -> do
                            -- Send notification
                            void $ Notification.sendNotification ldapNotificationService
                                "ldap_groups_synced"
                                configId
                                "system"

                            -- Record metrics
                            void $ Metrics.recordMetric ldapMetricsService
                                "ldap_groups_synced"
                                count

                            return $ Right count

-- | Validate LDAP configuration
validateLDAPConfig :: MonadIO m
                  => LDAPService
                  -> LDAPConfig
                  -> m (Either LDAPError ())
validateLDAPConfig _ config = do
    -- Validate required fields
    unless (T.length (ldapConfigServerUrl config) > 0) $
        return $ Left $ ValidationError "Server URL is required"
    unless (T.length (ldapConfigBindDN config) > 0) $
        return $ Left $ ValidationError "Bind DN is required"
    unless (T.length (ldapConfigBindPassword config) > 0) $
        return $ Left $ ValidationError "Bind password is required"
    unless (T.length (ldapConfigBaseDN config) > 0) $
        return $ Left $ ValidationError "Base DN is required"
    unless (T.length (ldapConfigUserFilter config) > 0) $
        return $ Left $ ValidationError "User filter is required"

    -- Validate sync interval if scheduled
    when (ldapConfigSyncMode config == Scheduled) $
        case ldapConfigSyncInterval config of
            Nothing -> return $ Left $ ValidationError "Sync interval is required for scheduled mode"
            Just interval ->
                when (interval <= 0) $
                    return $ Left $ ValidationError "Sync interval must be positive"

    return $ Right ()

-- | Test LDAP connection
testLDAPConnection :: MonadIO m
                  => LDAPService
                  -> LDAPConfig
                  -> m (Either LDAPError ())
testLDAPConnection _ config = do
    result <- try $ liftIO $ do
        ldap <- initializeLDAP config
        bindLDAP ldap (ldapConfigBindDN config) (ldapConfigBindPassword config)
        return ()

    case result of
        Left err -> return $ Left $ ConnectionError $ T.pack $ show err
        Right _ -> return $ Right ()

-- Helper functions

-- | Initialize LDAP connection
initializeLDAP :: LDAPConfig -> IO LDAP
initializeLDAP config = do
    ldap <- initialize (T.unpack $ ldapConfigServerUrl config)
    case ldapConfigSecurityMode config of
        None -> return ()
        StartTLS -> startTLS ldap
        LDAPS -> setOption ldap LdapOptProtocolVersion 3
    return ldap

-- | Build user DN
buildUserDN :: LDAPConfig -> Text -> Text
buildUserDN config username =
    "cn=" <> username <> "," <> ldapConfigBaseDN config

-- | Build user filter
buildUserFilter :: LDAPConfig -> Text -> Text
buildUserFilter config username =
    "(&" <> ldapConfigUserFilter config <> "(cn=" <> username <> "))"

-- | Build user from LDAP entry
buildUser :: SearchEntry -> Text -> User
buildUser entry username = User
    { userId = generateUserId username
    , userEmail = fromMaybe "" $ getAttr entry "mail"
    , userName = fromMaybe username $ getAttr entry "displayName"
    , userActive = True
    , userCreated = undefined  -- Will be set by createOrUpdateUser
    , userUpdated = undefined  -- Will be set by createOrUpdateUser
    , userLastLogin = Nothing
    , userPreferences = object
        [ "ldapAttributes" .= object
            [ "cn" .= fromMaybe "" (getAttr entry "cn")
            , "mail" .= fromMaybe "" (getAttr entry "mail")
            , "displayName" .= fromMaybe "" (getAttr entry "displayName")
            ]
        ]
    }
  where
    generateUserId :: Text -> Text
    generateUserId name = "ldap_" <> T.filter isAllowed name
      where
        isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

    getAttr :: SearchEntry -> Text -> Maybe Text
    getAttr e attr = case Search.getValues e (T.unpack attr) of
        [] -> Nothing
        (x:_) -> Just $ T.pack x

-- | Update group mapping
updateGroupMapping :: LDAPConfig -> SearchEntry -> IO ()
updateGroupMapping config entry = do
    -- Get group name and members
    let groupName = fromMaybe "" $ getAttr entry "cn"
    let members = getMembers entry

    -- Find matching group mapping
    forM_ (findGroupMapping config groupName) $ \mapping -> do
        -- For each member, assign the mapped role
        forM_ members $ \member -> do
            let userId = "ldap_" <> T.filter isAllowed member
            void $ Permission.assignRole userId "global" (readRole $ gerritRole mapping) "system"
  where
    getAttr :: SearchEntry -> Text -> Maybe Text
    getAttr e attr = case Search.getValues e (T.unpack attr) of
        [] -> Nothing
        (x:_) -> Just $ T.pack x

    getMembers :: SearchEntry -> [Text]
    getMembers e = map T.pack $ Search.getValues e "member"

    findGroupMapping :: LDAPConfig -> Text -> Maybe LDAPGroupMapping
    findGroupMapping cfg groupName =
        find (\m -> ldapGroup m == groupName) (ldapConfigGroupMappings cfg)

    readRole :: Text -> Role
    readRole role = case T.toLower role of
        "owner" -> Owner
        "admin" -> Admin
        "member" -> Member
        _ -> Guest

    isAllowed :: Char -> Bool
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
