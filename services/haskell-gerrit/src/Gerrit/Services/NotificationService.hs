-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.NotificationService
    ( -- * Types
      NotificationService(..)
    , NotificationConfig(..)
    , NotificationChannel(..)
      -- * Service
    , initNotificationService
    , startNotificationService
    , stopNotificationService
      -- * Notification Operations
    , sendNotification
    , sendAlertNotification
    , sendBatchNotifications
    ) where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Monad (forever, void, when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Network.HTTP.Client (Manager)
import Network.HTTP.Client.TLS (newTlsManager)
import qualified Network.Mail.SMTP as SMTP
import qualified Network.HTTP.Types as HTTP
import qualified Data.ByteString.Lazy as LBS

import Gerrit.Models.Alert
import Gerrit.Models.Notification

-- | Notification channel types
data NotificationChannel
    = EmailChannel
        { emailServer :: Text
        , emailPort :: Int
        , emailUsername :: Text
        , emailPassword :: Text
        , emailFrom :: Text
        }
    | SlackChannel
        { slackWebhookUrl :: Text
        , slackChannel :: Text
        , slackUsername :: Text
        }
    | WebhookChannel
        { webhookUrl :: Text
        , webhookMethod :: Text
        , webhookHeaders :: [(Text, Text)]
        }

-- | Notification service configuration
data NotificationConfig = NotificationConfig
    { notificationChannels :: [NotificationChannel]
    , notificationBatchSize :: Int
    , notificationRetryAttempts :: Int
    , notificationRetryDelay :: Int
    }

-- | Notification service state
data NotificationService = NotificationService
    { notificationConfig :: NotificationConfig
    , notificationManager :: Manager
    , notificationThread :: Maybe ThreadId
    }

-- | Initialize the notification service
initNotificationService :: NotificationConfig -> IO NotificationService
initNotificationService config = do
    manager <- newTlsManager
    return NotificationService
        { notificationConfig = config
        , notificationManager = manager
        , notificationThread = Nothing
        }

-- | Start the notification service
startNotificationService :: NotificationService -> IO NotificationService
startNotificationService service = do
    threadId <- forkIO $ notificationServiceLoop service
    return service { notificationThread = Just threadId }

-- | Stop the notification service
stopNotificationService :: NotificationService -> IO ()
stopNotificationService NotificationService{..} =
    mapM_ killThread notificationThread

-- | Main notification service loop
notificationServiceLoop :: NotificationService -> IO ()
notificationServiceLoop service@NotificationService{..} = forever $ do
    -- Process pending notifications
    void $ processPendingNotifications service

    -- Clean up old notifications
    void $ cleanupOldNotifications service

    -- Wait before next batch
    threadDelay 1000000  -- 1 second

-- | Send a notification through all configured channels
sendNotification :: MonadIO m
                => NotificationService
                -> Text  -- ^ Title
                -> Text  -- ^ Message
                -> Value  -- ^ Details
                -> m ()
sendNotification NotificationService{..} title message details = do
    now <- liftIO getCurrentTime
    let notification = Notification
            { notificationId = generateNotificationId now
            , notificationTitle = title
            , notificationMessage = message
            , notificationDetails = details
            , notificationStatus = Pending
            , notificationCreated = now
            , notificationUpdated = now
            }

    -- Store notification
    void $ createNotification notification

    -- Attempt immediate delivery
    void $ deliverNotification notificationManager notification (notificationChannels notificationConfig)

-- | Send an alert notification
sendAlertNotification :: MonadIO m => NotificationService -> Alert -> m ()
sendAlertNotification service Alert{..} = do
    let title = "[" <> showSeverity alertSeverity <> "] " <> alertTitle
        details = object
            [ "alert_id" .= alertId
            , "severity" .= alertSeverity
            , "source" .= alertSource
            , "metadata" .= alertMetadata
            ]
    sendNotification service title alertMessage details

-- | Send batch notifications
sendBatchNotifications :: MonadIO m
                      => NotificationService
                      -> [(Text, Text, Value)]  -- ^ (Title, Message, Details)
                      -> m ()
sendBatchNotifications service notifications =
    mapM_ (\(title, msg, details) -> sendNotification service title msg details) notifications

-- | Process pending notifications
processPendingNotifications :: MonadIO m => NotificationService -> m ()
processPendingNotifications service@NotificationService{..} = do
    -- Get pending notifications
    notifications <- getPendingNotifications (notificationBatchSize notificationConfig)

    -- Process each notification
    mapM_ processNotification notifications
  where
    processNotification notification = do
        -- Attempt delivery
        result <- deliverNotification
            notificationManager
            notification
            (notificationChannels notificationConfig)

        -- Update notification status
        case result of
            Right _ ->
                void $ updateNotificationStatus (notificationId notification) Delivered
            Left err -> do
                let attempts = notificationAttempts notification + 1
                if attempts >= notificationRetryAttempts notificationConfig
                    then void $ updateNotificationStatus (notificationId notification) Failed
                    else void $ updateNotificationAttempts (notificationId notification) attempts

-- | Clean up old notifications
cleanupOldNotifications :: MonadIO m => NotificationService -> m ()
cleanupOldNotifications NotificationService{..} = do
    now <- liftIO getCurrentTime
    let cutoff = addUTCTime (-30 * 86400) now  -- 30 days retention

    -- Delete old notifications
    void $ deleteOldNotifications cutoff

-- | Helper function to deliver a notification
deliverNotification :: MonadIO m
                   => Manager
                   -> Notification
                   -> [NotificationChannel]
                   -> m (Either Text ())
deliverNotification manager notification channels = do
    results <- mapM (deliverToChannel manager notification) channels
    return $ case sequence results of
        Right _ -> Right ()
        Left err -> Left err

-- | Helper function to deliver to a specific channel
deliverToChannel :: MonadIO m
                => Manager
                -> Notification
                -> NotificationChannel
                -> m (Either Text ())
deliverToChannel manager notification channel = case channel of
    EmailChannel{..} ->
        sendEmail
            emailServer
            emailPort
            emailUsername
            emailPassword
            emailFrom
            notification

    SlackChannel{..} ->
        sendSlackMessage
            manager
            slackWebhookUrl
            slackChannel
            slackUsername
            notification

    WebhookChannel{..} ->
        sendWebhook
            manager
            webhookUrl
            webhookMethod
            webhookHeaders
            notification

-- | Helper function to send email
sendEmail :: MonadIO m
          => Text  -- ^ Server
          -> Int   -- ^ Port
          -> Text  -- ^ Username
          -> Text  -- ^ Password
          -> Text  -- ^ From address
          -> Notification
          -> m (Either Text ())
sendEmail server port username password from Notification{..} = liftIO $ do
    let settings = SMTP.defaultSettingsSMTP
            { SMTP.smtpServer = Text.unpack server
            , SMTP.smtpPort = port
            , SMTP.smtpUsername = Text.unpack username
            , SMTP.smtpPassword = Text.unpack password
            }

    try $ SMTP.sendMailWithLogin'
        settings
        (Text.unpack from)
        []  -- TODO: Configure recipients
        (formatEmailContent notificationTitle notificationMessage)

    return $ Right ()
  where
    formatEmailContent title message =
        "Subject: " <> Text.unpack title <> "\r\n\r\n" <>
        Text.unpack message

-- | Helper function to send Slack message
sendSlackMessage :: MonadIO m
                => Manager
                -> Text   -- ^ Webhook URL
                -> Text   -- ^ Channel
                -> Text   -- ^ Username
                -> Notification
                -> m (Either Text ())
sendSlackMessage manager webhookUrl channel username Notification{..} = do
    let payload = object
            [ "channel" .= channel
            , "username" .= username
            , "text" .= formatSlackMessage notificationTitle notificationMessage
            , "attachments" .= [notificationDetails]
            ]

    void $ httpPost manager (Text.unpack webhookUrl) payload
    return $ Right ()
  where
    formatSlackMessage title message =
        "*" <> title <> "*\n" <> message

-- | Helper function to send webhook
sendWebhook :: MonadIO m
            => Manager
            -> Text   -- ^ URL
            -> Text   -- ^ Method
            -> [(Text, Text)]  -- ^ Headers
            -> Notification
            -> m (Either Text ())
sendWebhook manager url method headers Notification{..} = do
    let payload = object
            [ "title" .= notificationTitle
            , "message" .= notificationMessage
            , "details" .= notificationDetails
            , "timestamp" .= notificationCreated
            ]

    void $ httpRequest manager (Text.unpack url) (Text.unpack method) headers payload
    return $ Right ()

-- | Helper function to show severity level
showSeverity :: AlertSeverity -> Text
showSeverity severity = case severity of
    Critical -> "CRITICAL"
    Warning -> "WARNING"
    Info -> "INFO"

-- | Helper function to generate notification ID
generateNotificationId :: UTCTime -> Text
generateNotificationId timestamp =
    "notif_" <> Text.pack (show timestamp)
