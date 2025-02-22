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

module Gerrit.Models.Notification
    ( -- * Types
      Notification(..)
    , NotificationId
    , NotificationType(..)
    , NotificationPriority(..)
    , NotificationStatus(..)
    , DeliveryMethod(..)
    , NotificationTemplate(..)
    , NotificationTemplateId
    , NotificationPreference(..)
    , NotificationPreferenceId
      -- * Operations
    , createNotification
    , updateNotification
    , getNotificationById
    , listNotifications
    , markAsRead
    , markAsDelivered
    , deleteNotification
    , migrateAll
    , createTemplate
    , updateTemplate
    , getTemplateById
    , listTemplates
    , setNotificationPreference
    , getNotificationPreference
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

-- | Notification type
data NotificationType
    = ChangeUpdate
        { changeId :: Text
        , updateType :: Text
        }
    | ReviewRequest
        { changeId :: Text
        , requestedBy :: Text
        }
    | CommentMention
        { commentId :: Text
        , mentionedBy :: Text
        }
    | VoteSubmitted
        { changeId :: Text
        , voterId :: Text
        , voteType :: Text
        }
    | StackUpdate
        { stackId :: Text
        , updateType :: Text
        }
    | SystemAlert
        { alertId :: Text
        , alertType :: Text
        }
    deriving (Show, Read, Eq, Generic)
derivePersistField "NotificationType"

-- | Notification priority
data NotificationPriority
    = Highest
    | High
    | Normal
    | Low
    | Lowest
    deriving (Show, Read, Eq, Generic, Ord)
derivePersistField "NotificationPriority"

-- | Notification status
data NotificationStatus
    = Unread
    | Read
    | Delivered
    | Failed Text
    | Archived
    deriving (Show, Read, Eq, Generic)
derivePersistField "NotificationStatus"

-- | Delivery method
data DeliveryMethod
    = InApp
    | Email
        { emailAddress :: Text
        , emailTemplate :: Text
        }
    | Webhook
        { webhookUrl :: Text
        , webhookHeaders :: Value
        }
    | PushNotification
        { deviceToken :: Text
        , platform :: Text
        }
    deriving (Show, Read, Eq, Generic)
derivePersistField "DeliveryMethod"

-- | Define the notification entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Notification
    notificationId Text
    userId Text
    notificationType NotificationType
    priority NotificationPriority
    status NotificationStatus
    deliveryMethod DeliveryMethod
    title Text
    message Text
    metadata Value Maybe
    readAt UTCTime Maybe
    deliveredAt UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueNotificationId notificationId
    deriving Show Eq Generic

NotificationTemplate
    templateId Text
    name Text
    description Text
    notificationType NotificationType
    subject Text
    body Text
    variables Value
    metadata Value Maybe
    isActive Bool
    created UTCTime
    updated UTCTime
    UniqueTemplateId templateId
    UniqueTemplateName name
    deriving Show Eq Generic

NotificationPreference
    preferenceId Text
    userId Text
    notificationType NotificationType
    deliveryMethod DeliveryMethod
    enabled Bool
    created UTCTime
    updated UTCTime
    UniquePreferenceId preferenceId
    UniqueUserTypePreference userId notificationType
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create notification
createNotification :: MonadIO m
                  => Text  -- ^ User ID
                  -> NotificationType  -- ^ Notification type
                  -> NotificationPriority  -- ^ Priority
                  -> DeliveryMethod  -- ^ Delivery method
                  -> Text  -- ^ Title
                  -> Text  -- ^ Message
                  -> Maybe Value  -- ^ Additional metadata
                  -> m (Entity Notification)
createNotification userId nType priority method title message metadata = do
    now <- liftIO getCurrentTime
    let notificationId = generateNotificationId userId now
    let notification = Notification
            { notificationNotificationId = notificationId
            , notificationUserId = userId
            , notificationNotificationType = nType
            , notificationPriority = priority
            , notificationStatus = Unread
            , notificationDeliveryMethod = method
            , notificationTitle = title
            , notificationMessage = message
            , notificationMetadata = metadata
            , notificationReadAt = Nothing
            , notificationDeliveredAt = Nothing
            , notificationCreated = now
            , notificationUpdated = now
            }
    runDB $ insertEntity notification

-- | Update notification
updateNotification :: MonadIO m
                  => Entity Notification
                  -> NotificationPriority  -- ^ New priority
                  -> NotificationStatus  -- ^ New status
                  -> DeliveryMethod  -- ^ New delivery method
                  -> Text  -- ^ New title
                  -> Text  -- ^ New message
                  -> Maybe Value  -- ^ New metadata
                  -> m (Entity Notification)
updateNotification (Entity key notification) priority status method title message metadata = do
    now <- liftIO getCurrentTime
    let updatedNotification = notification
            { notificationPriority = priority
            , notificationStatus = status
            , notificationDeliveryMethod = method
            , notificationTitle = title
            , notificationMessage = message
            , notificationMetadata = metadata
            , notificationUpdated = now
            }
    runDB $ replace key updatedNotification
    return $ Entity key updatedNotification

-- | Get notification by ID
getNotificationById :: MonadIO m
                   => Text  -- ^ Notification ID
                   -> m (Maybe (Entity Notification))
getNotificationById notificationId =
    runDB $ getBy $ UniqueNotificationId notificationId

-- | List notifications
listNotifications :: MonadIO m
                 => Text  -- ^ User ID
                 -> Maybe NotificationStatus  -- ^ Filter by status
                 -> Maybe NotificationPriority  -- ^ Filter by priority
                 -> Int   -- ^ Offset
                 -> Int   -- ^ Limit
                 -> m [Entity Notification]
listNotifications userId mStatus mPriority offset limit = do
    let filters = [NotificationUserId ==. userId] ++
                 maybe [] (\s -> [NotificationStatus ==. s]) mStatus ++
                 maybe [] (\p -> [NotificationPriority ==. p]) mPriority
    runDB $ selectList filters [Desc NotificationCreated, OffsetBy offset, LimitTo limit]

-- | Mark notification as read
markAsRead :: MonadIO m
           => Entity Notification
           -> m (Entity Notification)
markAsRead (Entity key notification) = do
    now <- liftIO getCurrentTime
    let updatedNotification = notification
            { notificationStatus = Read
            , notificationReadAt = Just now
            , notificationUpdated = now
            }
    runDB $ replace key updatedNotification
    return $ Entity key updatedNotification

-- | Mark notification as delivered
markAsDelivered :: MonadIO m
                => Entity Notification
                -> m (Entity Notification)
markAsDelivered (Entity key notification) = do
    now <- liftIO getCurrentTime
    let updatedNotification = notification
            { notificationStatus = Delivered
            , notificationDeliveredAt = Just now
            , notificationUpdated = now
            }
    runDB $ replace key updatedNotification
    return $ Entity key updatedNotification

-- | Delete notification
deleteNotification :: MonadIO m
                  => Entity Notification
                  -> m ()
deleteNotification (Entity key _) =
    runDB $ delete key

-- | Create a notification template
createTemplate :: MonadIO m
               => Text  -- ^ Name
               -> Text  -- ^ Description
               -> NotificationType  -- ^ Notification type
               -> Text  -- ^ Subject
               -> Text  -- ^ Body
               -> Value  -- ^ Variables
               -> Maybe Value  -- ^ Additional metadata
               -> m (Entity NotificationTemplate)
createTemplate name description nType subject body variables metadata = do
    now <- liftIO getCurrentTime
    let templateId = generateTemplateId name now
    let template = NotificationTemplate
            { notificationTemplateTemplateId = templateId
            , notificationTemplateName = name
            , notificationTemplateDescription = description
            , notificationTemplateNotificationType = nType
            , notificationTemplateSubject = subject
            , notificationTemplateBody = body
            , notificationTemplateVariables = variables
            , notificationTemplateMetadata = metadata
            , notificationTemplateIsActive = True
            , notificationTemplateCreated = now
            , notificationTemplateUpdated = now
            }
    runDB $ insertEntity template

-- | Update notification template
updateTemplate :: MonadIO m
               => Entity NotificationTemplate
               -> Text  -- ^ Name
               -> Text  -- ^ Description
               -> NotificationType  -- ^ Notification type
               -> Text  -- ^ Subject
               -> Text  -- ^ Body
               -> Value  -- ^ Variables
               -> Maybe Value  -- ^ Additional metadata
               -> Bool  -- ^ Is active
               -> m (Entity NotificationTemplate)
updateTemplate (Entity key template) name description nType subject body variables metadata isActive = do
    now <- liftIO getCurrentTime
    let updatedTemplate = template
            { notificationTemplateName = name
            , notificationTemplateDescription = description
            , notificationTemplateNotificationType = nType
            , notificationTemplateSubject = subject
            , notificationTemplateBody = body
            , notificationTemplateVariables = variables
            , notificationTemplateMetadata = metadata
            , notificationTemplateIsActive = isActive
            , notificationTemplateUpdated = now
            }
    runDB $ replace key updatedTemplate
    return $ Entity key updatedTemplate

-- | Get template by ID
getTemplateById :: MonadIO m
                => Text  -- ^ Template ID
                -> m (Maybe (Entity NotificationTemplate))
getTemplateById templateId =
    runDB $ getBy $ UniqueTemplateId templateId

-- | List templates
listTemplates :: MonadIO m
              => Maybe NotificationType  -- ^ Notification type
              -> Bool  -- ^ Only active templates
              -> Int  -- ^ Offset
              -> Int  -- ^ Limit
              -> m [Entity NotificationTemplate]
listTemplates mType onlyActive offset limit = do
    let filters = catMaybes
            [ (NotificationTemplateNotificationType ==.) <$> mType
            ] ++ [NotificationTemplateIsActive ==. True | onlyActive]
    runDB $ selectList filters [Asc NotificationTemplateName, OffsetBy offset, LimitTo limit]

-- | Set notification preference
setNotificationPreference :: MonadIO m
                         => Text  -- ^ User ID
                         -> NotificationType  -- ^ Notification type
                         -> DeliveryMethod  -- ^ Delivery method
                         -> Bool  -- ^ Enabled
                         -> m (Entity NotificationPreference)
setNotificationPreference userId nType method enabled = do
    now <- liftIO getCurrentTime
    let preferenceId = generatePreferenceId userId nType now
    let preference = NotificationPreference
            { notificationPreferencePreferenceId = preferenceId
            , notificationPreferenceUserId = userId
            , notificationPreferenceNotificationType = nType
            , notificationPreferenceDeliveryMethod = method
            , notificationPreferenceEnabled = enabled
            , notificationPreferenceCreated = now
            , notificationPreferenceUpdated = now
            }
    runDB $ insertBy preference >>= \case
        Left (Entity key _) -> do
            update key
                [ NotificationPreferenceDeliveryMethod =. method
                , NotificationPreferenceEnabled =. enabled
                , NotificationPreferenceUpdated =. now
                ]
            getEntity key
        Right entity -> return entity

-- | Get notification preference
getNotificationPreference :: MonadIO m
                         => Text  -- ^ User ID
                         -> NotificationType  -- ^ Notification type
                         -> m (Maybe (Entity NotificationPreference))
getNotificationPreference userId nType =
    runDB $ getBy $ UniqueUserTypePreference userId nType

-- Helper functions for generating IDs
generateNotificationId :: Text -> UTCTime -> Text
generateNotificationId userId timestamp =
    "n_" <> Text.filter isAllowed userId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateTemplateId :: Text -> UTCTime -> Text
generateTemplateId name timestamp =
    "tmpl_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generatePreferenceId :: Text -> NotificationType -> UTCTime -> Text
generatePreferenceId userId nType timestamp =
    "pref_" <> Text.filter isAllowed userId <> "_" <> Text.pack (show nType) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
