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

module Gerrit.Models.WebhookConfig
    ( -- * Types
      WebhookEvent(..)
    , DeliveryStatus(..)
    , RetryStrategy(..)
    , WebhookConfig(..)
    , WebhookConfigId
    , WebhookDelivery(..)
    , WebhookDeliveryId
    , WebhookSubscription(..)
    , WebhookSubscriptionId
      -- * Operations
    , createWebhookConfig
    , updateWebhookConfig
    , getWebhookConfigById
    , listWebhookConfigs
    , recordDelivery
    , getDeliveryById
    , listDeliveries
    , subscribeToEvent
    , unsubscribeFromEvent
    , getSubscriptionById
    , listSubscriptions
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

-- | Webhook event types
data WebhookEvent
    = ChangeCreated
    | ChangeUpdated
    | ChangeAbandoned
    | ChangeRestored
    | ChangeMerged
    | ReviewAdded
    | CommentAdded
    | VoteSubmitted
    | AlertTriggered
    | MetricsReport
    | CustomEvent Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "WebhookEvent"

-- | Delivery status
data DeliveryStatus
    = Pending
    | Delivered
    | Failed Text
    | Retrying Int
    deriving (Show, Read, Eq, Generic)
derivePersistField "DeliveryStatus"

-- | Retry strategy
data RetryStrategy
    = NoRetry
    | LinearRetry Int  -- ^ Number of retries
    | ExponentialRetry Int  -- ^ Maximum retries
    | CustomRetry Text  -- ^ Custom retry strategy
    deriving (Show, Read, Eq, Generic)
derivePersistField "RetryStrategy"

-- | Define the webhook configuration entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
WebhookConfig
    configId Text
    name Text
    description Text Maybe
    endpoint Text
    secret Text Maybe
    headers Value Maybe
    enabled Bool
    retryStrategy RetryStrategy
    timeout Int Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueConfigId configId
    UniqueName name
    deriving Show Eq Generic

WebhookDelivery
    deliveryId Text
    configId Text
    event WebhookEvent
    payload Value
    status DeliveryStatus
    statusCode Int Maybe
    response Text Maybe
    retryCount Int
    nextRetry UTCTime Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueDeliveryId deliveryId
    Foreign WebhookConfig configId References webhookConfigs OnDeleteCascade
    deriving Show Eq Generic

WebhookSubscription
    subscriptionId Text
    configId Text
    event WebhookEvent
    filter Value Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueSubscriptionId subscriptionId
    UniqueConfigEvent configId event
    Foreign WebhookConfig configId References webhookConfigs OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new webhook configuration
createWebhookConfig :: MonadIO m
                   => Text  -- ^ Name
                   -> Maybe Text  -- ^ Description
                   -> Text  -- ^ Endpoint URL
                   -> Maybe Text  -- ^ Secret
                   -> Maybe Value  -- ^ Headers
                   -> RetryStrategy  -- ^ Retry strategy
                   -> Maybe Int  -- ^ Timeout in seconds
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity WebhookConfig)
createWebhookConfig name description endpoint secret headers retry timeout metadata = do
    now <- liftIO getCurrentTime
    let configId = generateConfigId name now
    let config = WebhookConfig
            { webhookConfigConfigId = configId
            , webhookConfigName = name
            , webhookConfigDescription = description
            , webhookConfigEndpoint = endpoint
            , webhookConfigSecret = secret
            , webhookConfigHeaders = headers
            , webhookConfigEnabled = True
            , webhookConfigRetryStrategy = retry
            , webhookConfigTimeout = timeout
            , webhookConfigMetadata = metadata
            , webhookConfigCreated = now
            , webhookConfigUpdated = now
            }
    runDB $ insertEntity config

-- | Update webhook configuration
updateWebhookConfig :: MonadIO m
                   => Entity WebhookConfig
                   -> Text  -- ^ Name
                   -> Maybe Text  -- ^ Description
                   -> Text  -- ^ Endpoint URL
                   -> Maybe Text  -- ^ Secret
                   -> Maybe Value  -- ^ Headers
                   -> Bool  -- ^ Enabled
                   -> RetryStrategy  -- ^ Retry strategy
                   -> Maybe Int  -- ^ Timeout in seconds
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity WebhookConfig)
updateWebhookConfig (Entity key config) name description endpoint secret headers enabled retry timeout metadata = do
    now <- liftIO getCurrentTime
    let updatedConfig = config
            { webhookConfigName = name
            , webhookConfigDescription = description
            , webhookConfigEndpoint = endpoint
            , webhookConfigSecret = secret
            , webhookConfigHeaders = headers
            , webhookConfigEnabled = enabled
            , webhookConfigRetryStrategy = retry
            , webhookConfigTimeout = timeout
            , webhookConfigMetadata = metadata
            , webhookConfigUpdated = now
            }
    runDB $ replace key updatedConfig
    return $ Entity key updatedConfig

-- | Get webhook configuration by ID
getWebhookConfigById :: MonadIO m
                    => Text  -- ^ Config ID
                    -> m (Maybe (Entity WebhookConfig))
getWebhookConfigById configId =
    runDB $ getBy $ UniqueConfigId configId

-- | List webhook configurations
listWebhookConfigs :: MonadIO m
                   => Bool  -- ^ Only enabled configs
                   -> Int  -- ^ Offset
                   -> Int  -- ^ Limit
                   -> m [Entity WebhookConfig]
listWebhookConfigs onlyEnabled offset limit = do
    let filters = [WebhookConfigEnabled ==. True | onlyEnabled]
    runDB $ selectList filters [Asc WebhookConfigName, OffsetBy offset, LimitTo limit]

-- | Record webhook delivery
recordDelivery :: MonadIO m
               => Text  -- ^ Config ID
               -> WebhookEvent  -- ^ Event type
               -> Value  -- ^ Payload
               -> DeliveryStatus  -- ^ Status
               -> Maybe Int  -- ^ Status code
               -> Maybe Text  -- ^ Response
               -> Maybe Value  -- ^ Additional metadata
               -> m (Entity WebhookDelivery)
recordDelivery configId event payload status statusCode response metadata = do
    now <- liftIO getCurrentTime
    let deliveryId = generateDeliveryId configId event now
    let delivery = WebhookDelivery
            { webhookDeliveryDeliveryId = deliveryId
            , webhookDeliveryConfigId = configId
            , webhookDeliveryEvent = event
            , webhookDeliveryPayload = payload
            , webhookDeliveryStatus = status
            , webhookDeliveryStatusCode = statusCode
            , webhookDeliveryResponse = response
            , webhookDeliveryRetryCount = 0
            , webhookDeliveryNextRetry = Nothing
            , webhookDeliveryMetadata = metadata
            , webhookDeliveryCreated = now
            , webhookDeliveryUpdated = now
            }
    runDB $ insertEntity delivery

-- | Get delivery by ID
getDeliveryById :: MonadIO m
                => Text  -- ^ Delivery ID
                -> m (Maybe (Entity WebhookDelivery))
getDeliveryById deliveryId =
    runDB $ getBy $ UniqueDeliveryId deliveryId

-- | List deliveries
listDeliveries :: MonadIO m
               => Text  -- ^ Config ID
               -> Maybe WebhookEvent  -- ^ Event filter
               -> Maybe DeliveryStatus  -- ^ Status filter
               -> Int  -- ^ Offset
               -> Int  -- ^ Limit
               -> m [Entity WebhookDelivery]
listDeliveries configId mEvent mStatus offset limit = do
    let filters = (WebhookDeliveryConfigId ==. configId) :
                 maybe [] (\event -> [WebhookDeliveryEvent ==. event]) mEvent ++
                 maybe [] (\status -> [WebhookDeliveryStatus ==. status]) mStatus
    runDB $ selectList filters [Desc WebhookDeliveryCreated, OffsetBy offset, LimitTo limit]

-- | Subscribe to webhook event
subscribeToEvent :: MonadIO m
                 => Text  -- ^ Config ID
                 -> WebhookEvent  -- ^ Event type
                 -> Maybe Value  -- ^ Event filter
                 -> Maybe Value  -- ^ Additional metadata
                 -> m (Entity WebhookSubscription)
subscribeToEvent configId event filter metadata = do
    now <- liftIO getCurrentTime
    let subscriptionId = generateSubscriptionId configId event now
    let subscription = WebhookSubscription
            { webhookSubscriptionSubscriptionId = subscriptionId
            , webhookSubscriptionConfigId = configId
            , webhookSubscriptionEvent = event
            , webhookSubscriptionFilter = filter
            , webhookSubscriptionMetadata = metadata
            , webhookSubscriptionCreated = now
            , webhookSubscriptionUpdated = now
            }
    runDB $ insertEntity subscription

-- | Unsubscribe from webhook event
unsubscribeFromEvent :: MonadIO m
                    => Text  -- ^ Config ID
                    -> WebhookEvent  -- ^ Event type
                    -> m ()
unsubscribeFromEvent configId event =
    runDB $ deleteWhere
        [ WebhookSubscriptionConfigId ==. configId
        , WebhookSubscriptionEvent ==. event
        ]

-- | Get subscription by ID
getSubscriptionById :: MonadIO m
                   => Text  -- ^ Subscription ID
                   -> m (Maybe (Entity WebhookSubscription))
getSubscriptionById subscriptionId =
    runDB $ getBy $ UniqueSubscriptionId subscriptionId

-- | List subscriptions
listSubscriptions :: MonadIO m
                 => Text  -- ^ Config ID
                 -> Maybe WebhookEvent  -- ^ Event filter
                 -> Int  -- ^ Offset
                 -> Int  -- ^ Limit
                 -> m [Entity WebhookSubscription]
listSubscriptions configId mEvent offset limit = do
    let filters = (WebhookSubscriptionConfigId ==. configId) :
                 maybe [] (\event -> [WebhookSubscriptionEvent ==. event]) mEvent
    runDB $ selectList filters [Asc WebhookSubscriptionCreated, OffsetBy offset, LimitTo limit]

-- Helper functions for generating IDs
generateConfigId :: Text -> UTCTime -> Text
generateConfigId name timestamp =
    "whc_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateDeliveryId :: Text -> WebhookEvent -> UTCTime -> Text
generateDeliveryId configId event timestamp =
    "whd_" <> Text.filter isAllowed configId <> "_" <> Text.pack (show event) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateSubscriptionId :: Text -> WebhookEvent -> UTCTime -> Text
generateSubscriptionId configId event timestamp =
    "whs_" <> Text.filter isAllowed configId <> "_" <> Text.pack (show event) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
