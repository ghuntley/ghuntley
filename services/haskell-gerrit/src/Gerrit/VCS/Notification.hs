{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.VCS.Notification
    ( -- * Types
      NotificationSystem(..)
    , NotificationType(..)
    , NotificationConfig(..)
    , NotificationChannel(..)
      -- * Functions
    , initNotificationSystem
    , notifyNewAlert
    , notifyAlertAcknowledged
    , notifyAlertStatusChanged
    , notifyAlertDeleted
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.TLS as HTTP
import qualified Network.HTTP.Types.Status as HTTP
import System.Log.Logger (errorM)
import Data.Time.Format (formatTime, defaultTimeLocale)
import Data.Time.Clock (UTCTime)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Char8 as BS8
import Network.Mail.Mime (Mail(..), Address(..), simpleMail', renderMail')

import Gerrit.Models.Alert (Alert(..), AlertStatus(..), AlertSeverity(..))
import Gerrit.Api.Config (Config(..))

-- | Type of notification
data NotificationType
    = AlertCreated
    | AlertAcknowledged
    | AlertStatusChanged
    | AlertDeleted
    deriving (Show, Eq)

-- | Configuration for a notification channel
data NotificationConfig = NotificationConfig
    { notificationUrl :: Text
    , notificationToken :: Maybe Text
    , notificationEnabled :: Bool
    , notificationPriority :: Maybe Text
    , notificationChannel :: Maybe Text  -- For Slack
    , notificationRecipients :: [Text]   -- For email
    , notificationFromAddress :: Maybe Text  -- For email
    , notificationFromName :: Maybe Text     -- For email
    } deriving (Show, Eq)

-- | Supported notification channels
data NotificationChannel
    = SlackChannel NotificationConfig
    | EmailChannel NotificationConfig
    | TeamsChannel NotificationConfig
    | DiscordChannel NotificationConfig
    | PagerDutyChannel NotificationConfig
    deriving (Show, Eq)

-- | Notification system
data NotificationSystem = NotificationSystem
    { notificationChannels :: [NotificationChannel]
    , notificationManager :: HTTP.Manager
    }

-- | Initialize the notification system
initNotificationSystem :: Config -> IO NotificationSystem
initNotificationSystem config = do
    manager <- HTTP.newManager HTTP.tlsManagerSettings
    return $ NotificationSystem
        { notificationChannels = configureChannels config
        , notificationManager = manager
        }

-- | Configure notification channels from config
configureChannels :: Config -> [NotificationChannel]
configureChannels config =
    [ SlackChannel $ NotificationConfig
        { notificationUrl = configSlackWebhookUrl config
        , notificationToken = configSlackToken config
        , notificationEnabled = configSlackEnabled config
        , notificationPriority = Nothing
        , notificationChannel = Just $ configSlackDefaultChannel config
        , notificationRecipients = []
        , notificationFromAddress = Nothing
        , notificationFromName = Nothing
        }
    , EmailChannel $ NotificationConfig
        { notificationUrl = configEmailApiUrl config
        , notificationToken = configEmailApiKey config
        , notificationEnabled = configEmailEnabled config
        , notificationPriority = Nothing
        , notificationChannel = Nothing
        , notificationRecipients = configEmailDefaultRecipients config
        , notificationFromAddress = Just $ configEmailFromAddress config
        , notificationFromName = Just $ configEmailFromName config
        }
    -- ... existing Teams, Discord, PagerDuty configurations ...
    ]

-- | Notify about a new alert
notifyNewAlert :: MonadIO m => NotificationSystem -> Alert -> m ()
notifyNewAlert system alert = liftIO $
    sendNotification system AlertCreated alert Nothing Nothing

-- | Notify about an acknowledged alert
notifyAlertAcknowledged :: MonadIO m => NotificationSystem -> Alert -> Text -> m ()
notifyAlertAcknowledged system alert userId = liftIO $
    sendNotification system AlertAcknowledged alert (Just userId) Nothing

-- | Notify about an alert status change
notifyAlertStatusChanged :: MonadIO m => NotificationSystem -> Alert -> AlertStatus -> m ()
notifyAlertStatusChanged system alert newStatus = liftIO $
    sendNotification system AlertStatusChanged alert Nothing (Just newStatus)

-- | Notify about a deleted alert
notifyAlertDeleted :: MonadIO m => NotificationSystem -> Alert -> m ()
notifyAlertDeleted system alert = liftIO $
    sendNotification system AlertDeleted alert Nothing Nothing

-- | Send notification to all enabled channels
sendNotification :: NotificationSystem -> NotificationType -> Alert -> Maybe Text -> Maybe AlertStatus -> IO ()
sendNotification NotificationSystem{..} notificationType alert userId newStatus =
    mapM_ (sendToChannel notificationManager notificationType alert userId newStatus) notificationChannels

-- | Send notification to a specific channel
sendToChannel :: HTTP.Manager -> NotificationType -> Alert -> Maybe Text -> Maybe AlertStatus -> NotificationChannel -> IO ()
sendToChannel manager notificationType alert userId newStatus channel =
    case channel of
        SlackChannel config -> when (notificationEnabled config) $
            sendSlackNotification manager config notificationType alert userId newStatus
        EmailChannel config -> when (notificationEnabled config) $
            sendEmailNotification manager config notificationType alert userId newStatus
        TeamsChannel config -> when (notificationEnabled config) $
            sendTeamsNotification manager config notificationType alert userId newStatus
        DiscordChannel config -> when (notificationEnabled config) $
            sendDiscordNotification manager config notificationType alert userId newStatus
        PagerDutyChannel config -> when (notificationEnabled config) $
            sendPagerDutyNotification manager config notificationType alert userId newStatus

-- | Send notification to Slack
sendSlackNotification :: HTTP.Manager -> NotificationConfig -> NotificationType -> Alert -> Maybe Text -> Maybe AlertStatus -> IO ()
sendSlackNotification manager NotificationConfig{..} notificationType alert userId newStatus = do
    let payload = object
            [ "channel" .= fromMaybe "#gerrit-alerts" notificationChannel
            , "username" .= ("Gerrit Alert System" :: Text)
            , "icon_emoji" .= (":warning:" :: Text)
            , "attachments" .= [object
                [ "color" .= getSlackColor (alertSeverity alert)
                , "title" .= formatSlackTitle notificationType alert
                , "text" .= formatSlackMessage notificationType alert userId newStatus
                , "fields" .= formatSlackFields notificationType alert userId newStatus
                , "footer" .= ("Gerrit Alert System" :: Text)
                , "ts" .= (floor $ utcTimestampToSeconds $ alertTimestamp alert :: Integer)
                ]]
            ]

    request <- HTTP.parseRequest (Text.unpack notificationUrl)
    let request' = request
            { HTTP.method = "POST"
            , HTTP.requestBody = HTTP.RequestBodyLBS $ encode payload
            , HTTP.requestHeaders =
                [ ("Content-Type", "application/json")
                ] ++ maybe [] (\token -> [("Authorization", "Bearer " <> encodeUtf8 token)]) notificationToken
            }

    response <- HTTP.httpLbs request' manager
    unless (HTTP.statusCode (HTTP.responseStatus response) == 200) $
        errorM "Gerrit.VCS.Notification" $ "Failed to send Slack notification: " ++ show response

-- | Send notification via email
sendEmailNotification :: HTTP.Manager -> NotificationConfig -> NotificationType -> Alert -> Maybe Text -> Maybe AlertStatus -> IO ()
sendEmailNotification manager NotificationConfig{..} notificationType alert userId newStatus = do
    let fromAddr = Address
            { addressName = fmap Text.unpack notificationFromName
            , addressEmail = Text.unpack $ fromMaybe "gerrit@localhost" notificationFromAddress
            }
        toAddrs = map (\email -> Address Nothing (Text.unpack email)) notificationRecipients
        subject = formatEmailSubject notificationType alert
        body = formatEmailBody notificationType alert userId newStatus

    mail <- simpleMail'
        fromAddr
        toAddrs
        (Text.encodeUtf8 subject)
        (Text.encodeUtf8 body)

    -- If using an email API service
    if Text.null notificationUrl
        then do
            -- Use local SMTP (implementation depends on your needs)
            rendered <- renderMail' mail
            -- sendMailLocal rendered
            return ()
        else do
            -- Use email API service
            let payload = object
                    [ "from" .= object
                        [ "email" .= notificationFromAddress
                        , "name" .= notificationFromName
                        ]
                    , "to" .= map (\addr -> object ["email" .= addr]) notificationRecipients
                    , "subject" .= subject
                    , "text" .= body
                    ]

            request <- HTTP.parseRequest (Text.unpack notificationUrl)
            let request' = request
                    { HTTP.method = "POST"
                    , HTTP.requestBody = HTTP.RequestBodyLBS $ encode payload
                    , HTTP.requestHeaders =
                        [ ("Content-Type", "application/json")
                        ] ++ maybe [] (\token -> [("X-API-Key", encodeUtf8 token)]) notificationToken
                    }

            response <- HTTP.httpLbs request' manager
            unless (HTTP.statusCode (HTTP.responseStatus response) == 200) $
                errorM "Gerrit.VCS.Notification" $ "Failed to send email notification: " ++ show response

-- | Helper functions for Slack notifications
getSlackColor :: AlertSeverity -> Text
getSlackColor = \case
    Critical -> "danger"
    Warning -> "warning"
    Info -> "good"

formatSlackTitle :: NotificationType -> Alert -> Text
formatSlackTitle notificationType Alert{..} =
    case notificationType of
        AlertCreated -> "🚨 New Alert: " <> alertTitle
        AlertAcknowledged -> "✅ Alert Acknowledged: " <> alertTitle
        AlertStatusChanged -> "🔄 Alert Status Changed: " <> alertTitle
        AlertDeleted -> "❌ Alert Deleted: " <> alertTitle

formatSlackFields :: NotificationType -> Alert -> Maybe Text -> Maybe AlertStatus -> [Value]
formatSlackFields notificationType Alert{..} userId newStatus =
    [ object
        [ "title" .= ("Severity" :: Text)
        , "value" .= showt alertSeverity
        , "short" .= True
        ]
    , object
        [ "title" .= ("Source" :: Text)
        , "value" .= alertSource
        , "short" .= True
        ]
    ] ++ additionalFields
  where
    additionalFields = case notificationType of
        AlertCreated ->
            [ object
                [ "title" .= ("Message" :: Text)
                , "value" .= alertMessage
                , "short" .= False
                ]
            ]
        AlertAcknowledged ->
            [ object
                [ "title" .= ("Acknowledged By" :: Text)
                , "value" .= fromMaybe "Unknown" userId
                , "short" .= True
                ]
            ]
        AlertStatusChanged ->
            [ object
                [ "title" .= ("New Status" :: Text)
                , "value" .= maybe "Unknown" showt newStatus
                , "short" .= True
                ]
            ]
        AlertDeleted -> []

-- | Helper functions for email notifications
formatEmailSubject :: NotificationType -> Alert -> Text
formatEmailSubject notificationType Alert{..} =
    case notificationType of
        AlertCreated -> "[Gerrit Alert] New Alert: " <> alertTitle
        AlertAcknowledged -> "[Gerrit Alert] Alert Acknowledged: " <> alertTitle
        AlertStatusChanged -> "[Gerrit Alert] Alert Status Changed: " <> alertTitle
        AlertDeleted -> "[Gerrit Alert] Alert Deleted: " <> alertTitle

formatEmailBody :: NotificationType -> Alert -> Maybe Text -> Maybe AlertStatus -> Text
formatEmailBody notificationType Alert{..} userId newStatus =
    Text.unlines $
        [ "Alert Details:"
        , "============="
        , ""
        , "Title: " <> alertTitle
        , "Severity: " <> showt alertSeverity
        , "Source: " <> alertSource
        , "Timestamp: " <> Text.pack (formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S UTC" alertTimestamp)
        ] ++ case notificationType of
            AlertCreated ->
                [ "Message: " <> alertMessage
                ]
            AlertAcknowledged ->
                [ "Acknowledged By: " <> fromMaybe "Unknown" userId
                , "Acknowledged At: " <> Text.pack (maybe "Unknown" (formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S UTC") alertAcknowledgedAt)
                ]
            AlertStatusChanged ->
                [ "Previous Status: " <> showt alertStatus
                , "New Status: " <> maybe "Unknown" showt newStatus
                ]
            AlertDeleted ->
                [ "Alert has been deleted from the system."
                ]

-- | Helper function to convert UTCTime to Unix timestamp seconds
utcTimestampToSeconds :: UTCTime -> Double
utcTimestampToSeconds = fromRational . toRational . utcTimeToPOSIXSeconds
