-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Models.User
    ( -- * Types
      User(..)
    , UserId
    , UserStatus(..)
    , UserSession(..)
    , UserSessionId
    , UserPreferences(..)
    , UserPreferencesId
      -- * Operations
    , createUser
    , updateUser
    , getUserById
    , getUserByEmail
    , listUsers
    , createSession
    , validateSession
    , revokeSession
    , updatePreferences
    , getPreferences
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | User status
data UserStatus
    = Active
    | Inactive
    | Suspended
    | PendingVerification
    deriving (Show, Read, Eq, Generic)
derivePersistField "UserStatus"

-- | Define the User entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
User
    userId Text
    email Text
    hashedPassword Text
    fullName Text
    status UserStatus
    lastLoginAt UTCTime Maybe
    failedLoginAttempts Int default=0
    verificationToken Text Maybe
    resetToken Text Maybe
    resetTokenExpiry UTCTime Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueUserId userId
    UniqueUserEmail email
    deriving Show Eq Generic

UserSession
    sessionId Text
    userId Text
    token Text
    deviceInfo Value Maybe
    ipAddress Text
    lastActivity UTCTime
    expiresAt UTCTime
    created UTCTime
    UniqueSessionId sessionId
    UniqueSessionToken token
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic

UserPreferences
    prefId Text
    userId Text
    theme Text default="light"
    emailNotifications Bool default=true
    timezone Text default="UTC"
    customSettings Value
    created UTCTime
    updated UTCTime
    UniquePrefId prefId
    UniqueUserPreferences userId
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new user
createUser :: MonadIO m
           => ConnectionPool
           -> Text  -- ^ Email
           -> Text  -- ^ Hashed password
           -> Text  -- ^ Full name
           -> Maybe Value  -- ^ Metadata
           -> m (Entity User)
createUser pool email hashedPw fullName metadata = do
    now <- liftIO getCurrentTime
    let userId = generateUserId email now
    let user = User
            { userUserId = userId
            , userEmail = email
            , userHashedPassword = hashedPw
            , userFullName = fullName
            , userStatus = PendingVerification
            , userLastLoginAt = Nothing
            , userFailedLoginAttempts = 0
            , userVerificationToken = Just $ generateVerificationToken userId now
            , userResetToken = Nothing
            , userResetTokenExpiry = Nothing
            , userMetadata = metadata
            , userCreated = now
            , userUpdated = now
            }
    runSqlPool (insertEntity user) pool

-- | Update user
updateUser :: MonadIO m
           => ConnectionPool
           -> Entity User
           -> Text  -- ^ New email
           -> Text  -- ^ New full name
           -> UserStatus  -- ^ New status
           -> Maybe Value  -- ^ New metadata
           -> m (Entity User)
updateUser pool (Entity key user) newEmail newFullName newStatus newMetadata = do
    now <- liftIO getCurrentTime
    let updatedUser = user
            { userEmail = newEmail
            , userFullName = newFullName
            , userStatus = newStatus
            , userMetadata = newMetadata
            , userUpdated = now
            }
    runSqlPool (replace key updatedUser) pool
    return $ Entity key updatedUser

-- | Get user by ID
getUserById :: MonadIO m
            => ConnectionPool
            -> Text  -- ^ User ID
            -> m (Maybe (Entity User))
getUserById pool userId =
    runSqlPool (getBy $ UniqueUserId userId) pool

-- | Get user by email
getUserByEmail :: MonadIO m
               => ConnectionPool
               -> Text  -- ^ Email
               -> m (Maybe (Entity User))
getUserByEmail pool email =
    runSqlPool (getBy $ UniqueUserEmail email) pool

-- | List users with filters
listUsers :: MonadIO m
          => ConnectionPool
          -> Maybe UserStatus  -- ^ Filter by status
          -> Int  -- ^ Offset
          -> Int  -- ^ Limit
          -> m [Entity User]
listUsers pool mStatus offset limit = do
    let filters = maybe [] (\status -> [UserStatus ==. status]) mStatus
    runSqlPool (selectList filters [Desc UserCreated, OffsetBy offset, LimitTo limit]) pool

-- | Create a new session
createSession :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ User ID
              -> Text  -- ^ Token
              -> Maybe Value  -- ^ Device info
              -> Text  -- ^ IP address
              -> Int  -- ^ Session duration in seconds
              -> m (Entity UserSession)
createSession pool userId token deviceInfo ipAddr duration = do
    now <- liftIO getCurrentTime
    let sessionId = generateSessionId userId now
    let expiresAt = addUTCTime (fromIntegral duration) now
    let session = UserSession
            { userSessionSessionId = sessionId
            , userSessionUserId = userId
            , userSessionToken = token
            , userSessionDeviceInfo = deviceInfo
            , userSessionIpAddress = ipAddr
            , userSessionLastActivity = now
            , userSessionExpiresAt = expiresAt
            , userSessionCreated = now
            }
    runSqlPool (insertEntity session) pool

-- | Validate session
validateSession :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Session token
                -> m (Maybe (Entity UserSession))
validateSession pool token = do
    now <- liftIO getCurrentTime
    runSqlPool (selectFirst
        [ UserSessionToken ==. token
        , UserSessionExpiresAt >. now
        ] []) pool

-- | Revoke session
revokeSession :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Session token
              -> m ()
revokeSession pool token =
    runSqlPool (deleteBy $ UniqueSessionToken token) pool

-- | Update user preferences
updatePreferences :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ User ID
                 -> Text  -- ^ Theme
                 -> Bool  -- ^ Email notifications
                 -> Text  -- ^ Timezone
                 -> Value  -- ^ Custom settings
                 -> m (Entity UserPreferences)
updatePreferences pool userId theme emailNotifs tz customSettings = do
    now <- liftIO getCurrentTime
    let prefId = generatePrefId userId now
    let prefs = UserPreferences
            { userPreferencesPrefId = prefId
            , userPreferencesUserId = userId
            , userPreferencesTheme = theme
            , userPreferencesEmailNotifications = emailNotifs
            , userPreferencesTimezone = tz
            , userPreferencesCustomSettings = customSettings
            , userPreferencesCreated = now
            , userPreferencesUpdated = now
            }
    runSqlPool (upsert prefs [UserPreferencesUpdated =. now]) pool

-- | Get user preferences
getPreferences :: MonadIO m
               => ConnectionPool
               -> Text  -- ^ User ID
               -> m (Maybe (Entity UserPreferences))
getPreferences pool userId =
    runSqlPool (getBy $ UniqueUserPreferences userId) pool

-- Helper functions for generating IDs
generateUserId :: Text -> UTCTime -> Text
generateUserId email timestamp =
    "usr_" <> Text.filter isAllowed email <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateSessionId :: Text -> UTCTime -> Text
generateSessionId userId timestamp =
    "sess_" <> Text.filter isAllowed userId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generatePrefId :: Text -> UTCTime -> Text
generatePrefId userId timestamp =
    "pref_" <> Text.filter isAllowed userId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateVerificationToken :: Text -> UTCTime -> Text
generateVerificationToken userId timestamp =
    "verify_" <> Text.filter isAllowed userId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
