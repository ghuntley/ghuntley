-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Gerrit.Models.UserPreferences
    ( -- * Types
      Theme(..)
    , EmailFrequency(..)
    , DiffViewMode(..)
    , UserPreferences(..)
    , UserPreferencesId
    , NotificationSettings(..)
    , NotificationSettingsId
    , ReviewPreferences(..)
    , ReviewPreferencesId
      -- * Operations
    , createUserPreferences
    , updateUserPreferences
    , getUserPreferences
    , createNotificationSettings
    , updateNotificationSettings
    , getNotificationSettings
    , createReviewPreferences
    , updateReviewPreferences
    , getReviewPreferences
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.User (User)

-- | Theme preference
data Theme
    = LightTheme
    | DarkTheme
    | SystemTheme
    | CustomTheme Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "Theme"

-- | Email frequency preference
data EmailFrequency
    = Immediate
    | Daily
    | Weekly
    | Custom Int  -- ^ Custom interval in minutes
    deriving (Show, Read, Eq, Generic)
derivePersistField "EmailFrequency"

-- | Diff view mode
data DiffViewMode
    = UnifiedDiff
    | SideBySide
    | InlineDiff
    deriving (Show, Read, Eq, Generic)
derivePersistField "DiffViewMode"

-- | Define the user preferences entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
UserPreferences
    userId Text
    theme Theme
    language Text default="en"
    timezone Text default="UTC"
    pageSize Int default=25
    diffViewMode DiffViewMode
    showLineNumbers Bool default=true
    syntaxHighlighting Bool default=true
    autoRefresh Bool default=true
    customCss Text Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueUserPreferences userId
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic

NotificationSettings
    userId Text
    emailNotifications Bool default=true
    emailFrequency EmailFrequency
    webNotifications Bool default=true
    desktopNotifications Bool default=false
    digestEmails Bool default=true
    mentionNotifications Bool default=true
    reviewNotifications Bool default=true
    commentNotifications Bool default=true
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueNotificationSettings userId
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic

ReviewPreferences
    userId Text
    autoSubmit Bool default=false
    submitOnMerge Bool default=true
    ignoreWhitespace Bool default=false
    showCommitMessages Bool default=true
    expandAllComments Bool default=false
    showFileComments Bool default=true
    reviewerSuggestions Bool default=true
    customLabels Value Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueReviewPreferences userId
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create user preferences
createUserPreferences :: MonadIO m
                     => Text  -- ^ User ID
                     -> Theme  -- ^ Theme preference
                     -> Text  -- ^ Language
                     -> Text  -- ^ Timezone
                     -> Int  -- ^ Page size
                     -> DiffViewMode  -- ^ Diff view mode
                     -> Bool  -- ^ Show line numbers
                     -> Bool  -- ^ Syntax highlighting
                     -> Bool  -- ^ Auto refresh
                     -> Maybe Text  -- ^ Custom CSS
                     -> Maybe Value  -- ^ Additional metadata
                     -> m (Entity UserPreferences)
createUserPreferences userId theme lang tz pageSize diffMode lineNums syntax refresh css metadata = do
    now <- liftIO getCurrentTime
    let prefs = UserPreferences
            { userPreferencesUserId = userId
            , userPreferencesTheme = theme
            , userPreferencesLanguage = lang
            , userPreferencesTimezone = tz
            , userPreferencesPageSize = pageSize
            , userPreferencesDiffViewMode = diffMode
            , userPreferencesShowLineNumbers = lineNums
            , userPreferencesSyntaxHighlighting = syntax
            , userPreferencesAutoRefresh = refresh
            , userPreferencesCustomCss = css
            , userPreferencesMetadata = metadata
            , userPreferencesCreated = now
            , userPreferencesUpdated = now
            }
    runDB $ insertEntity prefs

-- | Update user preferences
updateUserPreferences :: MonadIO m
                     => Entity UserPreferences
                     -> Theme  -- ^ Theme preference
                     -> Text  -- ^ Language
                     -> Text  -- ^ Timezone
                     -> Int  -- ^ Page size
                     -> DiffViewMode  -- ^ Diff view mode
                     -> Bool  -- ^ Show line numbers
                     -> Bool  -- ^ Syntax highlighting
                     -> Bool  -- ^ Auto refresh
                     -> Maybe Text  -- ^ Custom CSS
                     -> Maybe Value  -- ^ Additional metadata
                     -> m (Entity UserPreferences)
updateUserPreferences (Entity key prefs) theme lang tz pageSize diffMode lineNums syntax refresh css metadata = do
    now <- liftIO getCurrentTime
    let updatedPrefs = prefs
            { userPreferencesTheme = theme
            , userPreferencesLanguage = lang
            , userPreferencesTimezone = tz
            , userPreferencesPageSize = pageSize
            , userPreferencesDiffViewMode = diffMode
            , userPreferencesShowLineNumbers = lineNums
            , userPreferencesSyntaxHighlighting = syntax
            , userPreferencesAutoRefresh = refresh
            , userPreferencesCustomCss = css
            , userPreferencesMetadata = metadata
            , userPreferencesUpdated = now
            }
    runDB $ replace key updatedPrefs
    return $ Entity key updatedPrefs

-- | Get user preferences
getUserPreferences :: MonadIO m
                  => Text  -- ^ User ID
                  -> m (Maybe (Entity UserPreferences))
getUserPreferences userId =
    runDB $ getBy $ UniqueUserPreferences userId

-- | Create notification settings
createNotificationSettings :: MonadIO m
                         => Text  -- ^ User ID
                         -> EmailFrequency  -- ^ Email frequency
                         -> Bool  -- ^ Email notifications
                         -> Bool  -- ^ Web notifications
                         -> Bool  -- ^ Desktop notifications
                         -> Bool  -- ^ Digest emails
                         -> Bool  -- ^ Mention notifications
                         -> Bool  -- ^ Review notifications
                         -> Bool  -- ^ Comment notifications
                         -> Maybe Value  -- ^ Additional metadata
                         -> m (Entity NotificationSettings)
createNotificationSettings userId freq email web desktop digest mention review comment metadata = do
    now <- liftIO getCurrentTime
    let settings = NotificationSettings
            { notificationSettingsUserId = userId
            , notificationSettingsEmailFrequency = freq
            , notificationSettingsEmailNotifications = email
            , notificationSettingsWebNotifications = web
            , notificationSettingsDesktopNotifications = desktop
            , notificationSettingsDigestEmails = digest
            , notificationSettingsMentionNotifications = mention
            , notificationSettingsReviewNotifications = review
            , notificationSettingsCommentNotifications = comment
            , notificationSettingsMetadata = metadata
            , notificationSettingsCreated = now
            , notificationSettingsUpdated = now
            }
    runDB $ insertEntity settings

-- | Update notification settings
updateNotificationSettings :: MonadIO m
                         => Entity NotificationSettings
                         -> EmailFrequency  -- ^ Email frequency
                         -> Bool  -- ^ Email notifications
                         -> Bool  -- ^ Web notifications
                         -> Bool  -- ^ Desktop notifications
                         -> Bool  -- ^ Digest emails
                         -> Bool  -- ^ Mention notifications
                         -> Bool  -- ^ Review notifications
                         -> Bool  -- ^ Comment notifications
                         -> Maybe Value  -- ^ Additional metadata
                         -> m (Entity NotificationSettings)
updateNotificationSettings (Entity key settings) freq email web desktop digest mention review comment metadata = do
    now <- liftIO getCurrentTime
    let updatedSettings = settings
            { notificationSettingsEmailFrequency = freq
            , notificationSettingsEmailNotifications = email
            , notificationSettingsWebNotifications = web
            , notificationSettingsDesktopNotifications = desktop
            , notificationSettingsDigestEmails = digest
            , notificationSettingsMentionNotifications = mention
            , notificationSettingsReviewNotifications = review
            , notificationSettingsCommentNotifications = comment
            , notificationSettingsMetadata = metadata
            , notificationSettingsUpdated = now
            }
    runDB $ replace key updatedSettings
    return $ Entity key updatedSettings

-- | Get notification settings
getNotificationSettings :: MonadIO m
                      => Text  -- ^ User ID
                      -> m (Maybe (Entity NotificationSettings))
getNotificationSettings userId =
    runDB $ getBy $ UniqueNotificationSettings userId

-- | Create review preferences
createReviewPreferences :: MonadIO m
                       => Text  -- ^ User ID
                       -> Bool  -- ^ Auto submit
                       -> Bool  -- ^ Submit on merge
                       -> Bool  -- ^ Ignore whitespace
                       -> Bool  -- ^ Show commit messages
                       -> Bool  -- ^ Expand all comments
                       -> Bool  -- ^ Show file comments
                       -> Bool  -- ^ Reviewer suggestions
                       -> Maybe Value  -- ^ Custom labels
                       -> Maybe Value  -- ^ Additional metadata
                       -> m (Entity ReviewPreferences)
createReviewPreferences userId autoSubmit submitMerge ignoreWs showCommits expandComments showFiles suggestions labels metadata = do
    now <- liftIO getCurrentTime
    let prefs = ReviewPreferences
            { reviewPreferencesUserId = userId
            , reviewPreferencesAutoSubmit = autoSubmit
            , reviewPreferencesSubmitOnMerge = submitMerge
            , reviewPreferencesIgnoreWhitespace = ignoreWs
            , reviewPreferencesShowCommitMessages = showCommits
            , reviewPreferencesExpandAllComments = expandComments
            , reviewPreferencesShowFileComments = showFiles
            , reviewPreferencesReviewerSuggestions = suggestions
            , reviewPreferencesCustomLabels = labels
            , reviewPreferencesMetadata = metadata
            , reviewPreferencesCreated = now
            , reviewPreferencesUpdated = now
            }
    runDB $ insertEntity prefs

-- | Update review preferences
updateReviewPreferences :: MonadIO m
                       => Entity ReviewPreferences
                       -> Bool  -- ^ Auto submit
                       -> Bool  -- ^ Submit on merge
                       -> Bool  -- ^ Ignore whitespace
                       -> Bool  -- ^ Show commit messages
                       -> Bool  -- ^ Expand all comments
                       -> Bool  -- ^ Show file comments
                       -> Bool  -- ^ Reviewer suggestions
                       -> Maybe Value  -- ^ Custom labels
                       -> Maybe Value  -- ^ Additional metadata
                       -> m (Entity ReviewPreferences)
updateReviewPreferences (Entity key prefs) autoSubmit submitMerge ignoreWs showCommits expandComments showFiles suggestions labels metadata = do
    now <- liftIO getCurrentTime
    let updatedPrefs = prefs
            { reviewPreferencesAutoSubmit = autoSubmit
            , reviewPreferencesSubmitOnMerge = submitMerge
            , reviewPreferencesIgnoreWhitespace = ignoreWs
            , reviewPreferencesShowCommitMessages = showCommits
            , reviewPreferencesExpandAllComments = expandComments
            , reviewPreferencesShowFileComments = showFiles
            , reviewPreferencesReviewerSuggestions = suggestions
            , reviewPreferencesCustomLabels = labels
            , reviewPreferencesMetadata = metadata
            , reviewPreferencesUpdated = now
            }
    runDB $ replace key updatedPrefs
    return $ Entity key updatedPrefs

-- | Get review preferences
getReviewPreferences :: MonadIO m
                    => Text  -- ^ User ID
                    -> m (Maybe (Entity ReviewPreferences))
getReviewPreferences userId =
    runDB $ getBy $ UniqueReviewPreferences userId
