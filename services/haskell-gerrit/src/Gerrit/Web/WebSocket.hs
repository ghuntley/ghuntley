-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Web.WebSocket
    ( handleMetricsWebSocket
    , MetricsSubscription(..)
    , SubscriptionType(..)
    ) where

import Control.Concurrent (forkIO)
import Control.Monad (forever, void)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (ToJSON(..), FromJSON(..), Value)
import qualified Data.Aeson as JSON
import Data.Text (Text)
import qualified Network.WebSockets as WS
import Gerrit.Analytics.RealTime
import Gerrit.Analytics.Types

-- | Types of metric subscriptions
data SubscriptionType
    = ActivitySubscription
    | QualitySubscription
    | ContributorSubscription
    | AllMetrics
    deriving (Show, Eq)

instance ToJSON SubscriptionType
instance FromJSON SubscriptionType

-- | Subscription request from client
data MetricsSubscription = MetricsSubscription
    { msType :: SubscriptionType
    , msUpdateInterval :: Maybe Int  -- ^ Optional custom update interval
    , msFilters :: [Text]           -- ^ Optional metric filters
    } deriving (Show)

instance ToJSON MetricsSubscription
instance FromJSON MetricsSubscription

-- | WebSocket message types
data WSMessage
    = Subscribe MetricsSubscription
    | Unsubscribe SubscriptionType
    | UpdateRequest SubscriptionType
    deriving (Show)

instance ToJSON WSMessage
instance FromJSON WSMessage

-- | WebSocket response types
data WSResponse
    = MetricData Text MetricUpdate
    | SubscriptionConfirmed SubscriptionType
    | UnsubscribeConfirmed SubscriptionType
    | ErrorResponse Text
    deriving (Show)

instance ToJSON WSResponse
instance FromJSON WSResponse

-- | Handle WebSocket connection for metrics
handleMetricsWebSocket :: MonadIO m
                      => MetricCache
                      -> WS.PendingConnection
                      -> m ()
handleMetricsWebSocket cache pending = liftIO $ do
    conn <- WS.acceptRequest pending
    WS.withPingThread conn 30 (return ()) $ do
        -- Add client to cache
        addClient cache conn

        -- Handle client messages
        flip finally (removeClient cache conn) $
            forever $ do
                msg <- WS.receiveData conn
                case JSON.decode msg of
                    Nothing ->
                        sendError conn "Invalid message format"
                    Just wsMsg ->
                        handleMessage cache conn wsMsg

-- | Handle incoming WebSocket messages
handleMessage :: MonadIO m
              => MetricCache
              -> WS.Connection
              -> WSMessage
              -> m ()
handleMessage cache conn msg = case msg of
    Subscribe sub -> do
        -- Set up subscription
        handleSubscription cache conn sub
        -- Send confirmation
        sendResponse conn $ SubscriptionConfirmed (msType sub)

    Unsubscribe subType -> do
        -- Remove subscription
        handleUnsubscribe cache conn subType
        -- Send confirmation
        sendResponse conn $ UnsubscribeConfirmed subType

    UpdateRequest subType -> do
        -- Send immediate update
        handleUpdateRequest cache conn subType

-- | Handle subscription request
handleSubscription :: MonadIO m
                   => MetricCache
                   -> WS.Connection
                   -> MetricsSubscription
                   -> m ()
handleSubscription cache conn MetricsSubscription{..} = do
    -- Set up periodic updates based on subscription type
    void $ liftIO $ forkIO $ case msType of
        ActivitySubscription -> do
            forever $ do
                metrics <- getCachedMetrics cache "global"
                case metrics of
                    Just (ActivityUpdate m) ->
                        sendResponse conn $ MetricData "activity" (ActivityUpdate m)
                    _ -> return ()
                threadDelay $ fromMaybe 5000000 (msUpdateInterval <&> (*1000))

        QualitySubscription -> do
            forever $ do
                metrics <- getCachedMetrics cache "global"
                case metrics of
                    Just (QualityUpdate m) ->
                        sendResponse conn $ MetricData "quality" (QualityUpdate m)
                    _ -> return ()
                threadDelay $ fromMaybe 5000000 (msUpdateInterval <&> (*1000))

        ContributorSubscription -> do
            forever $ do
                metrics <- getCachedMetrics cache "global"
                case metrics of
                    Just (ContributorUpdate m) ->
                        sendResponse conn $ MetricData "contributor" (ContributorUpdate m)
                    _ -> return ()
                threadDelay $ fromMaybe 5000000 (msUpdateInterval <&> (*1000))

        AllMetrics -> do
            forever $ do
                metrics <- getCachedMetrics cache "global"
                forM_ metrics $ \m ->
                    sendResponse conn $ MetricData "all" m
                threadDelay $ fromMaybe 5000000 (msUpdateInterval <&> (*1000))

-- | Handle unsubscribe request
handleUnsubscribe :: MonadIO m
                  => MetricCache
                  -> WS.Connection
                  -> SubscriptionType
                  -> m ()
handleUnsubscribe cache conn subType = do
    -- Remove client from specific subscription list
    -- This would need proper subscription tracking implementation
    return ()

-- | Handle immediate update request
handleUpdateRequest :: MonadIO m
                   => MetricCache
                   -> WS.Connection
                   -> SubscriptionType
                   -> m ()
handleUpdateRequest cache conn subType = do
    metrics <- getCachedMetrics cache "global"
    case (subType, metrics) of
        (ActivitySubscription, Just m@(ActivityUpdate _)) ->
            sendResponse conn $ MetricData "activity" m
        (QualitySubscription, Just m@(QualityUpdate _)) ->
            sendResponse conn $ MetricData "quality" m
        (ContributorSubscription, Just m@(ContributorUpdate _)) ->
            sendResponse conn $ MetricData "contributor" m
        (AllMetrics, Just m) ->
            sendResponse conn $ MetricData "all" m
        _ ->
            return ()

-- | Send error message to client
sendError :: MonadIO m => WS.Connection -> Text -> m ()
sendError conn msg =
    liftIO $ WS.sendTextData conn $ JSON.encode $ ErrorResponse msg

-- | Send response to client
sendResponse :: MonadIO m => WS.Connection -> WSResponse -> m ()
sendResponse conn response =
    liftIO $ WS.sendTextData conn $ JSON.encode response
