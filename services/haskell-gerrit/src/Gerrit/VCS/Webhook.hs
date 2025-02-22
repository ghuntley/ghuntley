-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.VCS.Webhook
    ( WebhookSystem(..)
    , WebhookConfig(..)
    , WebhookEvent(..)
    , DeliveryStatus(..)
    , DeliveryRecord(..)
    , RetryConfig(..)
    , WebhookMetrics(..)
    , defaultRetryConfig
    , initWebhookSystem
    ) where

import Control.Concurrent.Async (async)
import Control.Concurrent.STM
import Control.Monad.IO.Class (MonadIO, liftIO)
import Crypto.Hash (hmacGetDigest, hmac, SHA256(..))
import qualified Crypto.Hash as Hash
import Data.Aeson (ToJSON(..), FromJSON(..), Value(..), encode, decode, object, (.=))
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (UTCTime, getCurrentTime, addUTCTime)
import Network.HTTP.Client
import Network.HTTP.Client.TLS
import Network.HTTP.Types.Header
import System.Random (randomRIO)

-- | Webhook configuration
data WebhookConfig = WebhookConfig
    { whEndpoint :: Text           -- ^ Webhook endpoint URL
    , whSecret :: Text             -- ^ Secret for HMAC signing
    , whHeaders :: [(Text, Text)]  -- ^ Custom HTTP headers
    , whEvents :: [WebhookEvent]   -- ^ Subscribed event types
    , whRetryConfig :: RetryConfig -- ^ Retry configuration
    , whEnabled :: Bool            -- ^ Whether webhook is enabled
    } deriving (Show, Eq)

-- | Webhook event types
data WebhookEvent
    = EntryCreated
    | EntryUpdated
    | EntryDeleted
    | StatusChanged
    | ValidationUpdated
    | ConflictDetected
    | MetricsReport
    deriving (Show, Eq, Ord)

-- | Webhook delivery status
data DeliveryStatus
    = Pending
    | Delivered UTCTime
    | Failed Text UTCTime
    | Retrying Int UTCTime
    deriving (Show, Eq)

-- | Webhook delivery record
data DeliveryRecord = DeliveryRecord
    { drId :: Text                 -- ^ Delivery ID
    , drWebhook :: WebhookConfig   -- ^ Webhook configuration
    , drEvent :: WebhookEvent      -- ^ Event type
    , drPayload :: Value           -- ^ Event payload
    , drStatus :: DeliveryStatus   -- ^ Delivery status
    , drCreated :: UTCTime         -- ^ Creation timestamp
    , drUpdated :: UTCTime         -- ^ Last update timestamp
    }

-- | Retry configuration
data RetryConfig = RetryConfig
    { rcMaxAttempts :: Int         -- ^ Maximum retry attempts
    , rcInitialDelay :: Int        -- ^ Initial delay in seconds
    , rcMaxDelay :: Int            -- ^ Maximum delay in seconds
    , rcBackoffFactor :: Double    -- ^ Exponential backoff factor
    }

-- | Webhook metrics
data WebhookMetrics = WebhookMetrics
    { wmTotalDeliveries :: Int
    , wmSuccessfulDeliveries :: Int
    , wmFailedDeliveries :: Int
    , wmAverageResponseTime :: Double
    , wmActiveWebhooks :: Int
    }

-- | Default retry configuration
defaultRetryConfig :: RetryConfig
defaultRetryConfig = RetryConfig
    { rcMaxAttempts = 5
    , rcInitialDelay = 30
    , rcMaxDelay = 3600
    , rcBackoffFactor = 2.0
    }

-- | Webhook system interface
class (MonadIO m) => WebhookSystem m where
    -- Configuration
    registerWebhook :: WebhookConfig -> m ()
    updateWebhook :: Text -> WebhookConfig -> m ()
    deleteWebhook :: Text -> m ()
    listWebhooks :: m [WebhookConfig]

    -- Event delivery
    deliverEvent :: WebhookEvent -> Value -> m ()
    retryDelivery :: Text -> m ()
    getDeliveryStatus :: Text -> m DeliveryStatus
    listDeliveries :: WebhookConfig -> m [DeliveryRecord]

    -- Monitoring
    getWebhookMetrics :: m WebhookMetrics

-- | In-memory webhook system
data WebhookManager = WebhookManager
    { wmWebhooks :: TVar (Map Text WebhookConfig)
    , wmDeliveries :: TVar (Map Text DeliveryRecord)
    , wmMetrics :: TVar WebhookMetrics
    , wmManager :: Manager
    }

-- | Initialize webhook system
initWebhookSystem :: MonadIO m => m WebhookManager
initWebhookSystem = liftIO $ do
    manager <- newManager tlsManagerSettings
    webhooks <- newTVarIO Map.empty
    deliveries <- newTVarIO Map.empty
    metrics <- newTVarIO WebhookMetrics
        { wmTotalDeliveries = 0
        , wmSuccessfulDeliveries = 0
        , wmFailedDeliveries = 0
        , wmAverageResponseTime = 0.0
        , wmActiveWebhooks = 0
        }
    pure WebhookManager{..}

instance MonadIO m => WebhookSystem WebhookManager m where
    registerWebhook config = liftIO $ atomically $ do
        modifyTVar' (wmWebhooks manager) $ Map.insert (whEndpoint config) config
        modifyTVar' (wmMetrics manager) $ \m -> m { wmActiveWebhooks = wmActiveWebhooks m + 1 }

    updateWebhook endpoint config = liftIO $ atomically $
        modifyTVar' (wmWebhooks manager) $ Map.insert endpoint config

    deleteWebhook endpoint = liftIO $ atomically $ do
        modifyTVar' (wmWebhooks manager) $ Map.delete endpoint
        modifyTVar' (wmMetrics manager) $ \m -> m { wmActiveWebhooks = wmActiveWebhooks m - 1 }

    listWebhooks = liftIO $ atomically $
        Map.elems <$> readTVar (wmWebhooks manager)

    deliverEvent event payload = liftIO $ do
        webhooks <- atomically $ readTVar (wmWebhooks manager)
        now <- getCurrentTime
        let relevantWebhooks = filter (\wh -> event `elem` whEvents wh && whEnabled wh) $ Map.elems webhooks
        forM_ relevantWebhooks $ \webhook -> do
            deliveryId <- generateDeliveryId
            let record = DeliveryRecord
                    { drId = deliveryId
                    , drWebhook = webhook
                    , drEvent = event
                    , drPayload = payload
                    , drStatus = Pending
                    , drCreated = now
                    , drUpdated = now
                    }
            atomically $ modifyTVar' (wmDeliveries manager) $ Map.insert deliveryId record
            void $ async $ deliverWebhook manager record 1

    retryDelivery deliveryId = liftIO $ do
        mRecord <- atomically $ Map.lookup deliveryId <$> readTVar (wmDeliveries manager)
        case mRecord of
            Just record -> void $ async $ deliverWebhook manager record 1
            Nothing -> pure ()

    getDeliveryStatus deliveryId = liftIO $ atomically $ do
        deliveries <- readTVar (wmDeliveries manager)
        pure $ maybe Pending drStatus $ Map.lookup deliveryId deliveries

    listDeliveries webhook = liftIO $ atomically $ do
        deliveries <- readTVar (wmDeliveries manager)
        pure $ filter (\d -> drWebhook d == webhook) $ Map.elems deliveries

    getWebhookMetrics = liftIO $ atomically $ readTVar (wmMetrics manager)

-- Helper functions

-- | Generate a unique delivery ID
generateDeliveryId :: IO Text
generateDeliveryId = do
    uuid <- liftIO $ T.pack . show <$> randomRIO (1, maxBound :: Int)
    pure $ "del_" <> uuid

-- | Deliver a webhook with retries
deliverWebhook :: WebhookManager -> DeliveryRecord -> Int -> IO ()
deliverWebhook manager record attempt = do
    let webhook = drWebhook record
        RetryConfig{..} = whRetryConfig webhook

    -- Calculate delay with exponential backoff and jitter
    let baseDelay = min rcMaxDelay $
            rcInitialDelay * (rcBackoffFactor ^ (attempt - 1))
    jitter <- randomRIO (0.8, 1.2)
    let delay = round $ baseDelay * jitter

    -- Prepare request
    now <- getCurrentTime
    let payload = encode $ drPayload record
        signature = generateSignature (whSecret webhook) payload
        headers = [ ("Content-Type", "application/json")
                 , ("X-Hub-Signature", signature)
                 , ("X-Webhook-Event", TE.encodeUtf8 $ T.pack $ show $ drEvent record)
                 , ("X-Delivery-ID", TE.encodeUtf8 $ drId record)
                 ] ++ map (\(k, v) -> (TE.encodeUtf8 k, TE.encodeUtf8 v)) (whHeaders webhook)

    request <- parseRequest $ T.unpack $ whEndpoint webhook
    let request' = request
            { method = "POST"
            , requestHeaders = headers
            , requestBody = RequestBodyLBS payload
            }

    -- Attempt delivery
    result <- try $ httpNoBody request' { responseTimeout = responseTimeoutMicro $ 30 * 1000000 }
    case result of
        Right response | statusCode (responseStatus response) `div` 100 == 2 -> do
            -- Success
            atomically $ do
                modifyTVar' (wmDeliveries manager) $ Map.adjust
                    (\r -> r { drStatus = Delivered now, drUpdated = now })
                    (drId record)
                modifyTVar' (wmMetrics manager) $ \m -> m
                    { wmSuccessfulDeliveries = wmSuccessfulDeliveries m + 1
                    , wmTotalDeliveries = wmTotalDeliveries m + 1
                    }

        _ | attempt < rcMaxAttempts -> do
            -- Retry
            atomically $ modifyTVar' (wmDeliveries manager) $ Map.adjust
                (\r -> r { drStatus = Retrying attempt now, drUpdated = now })
                (drId record)
            threadDelay $ delay * 1000000
            deliverWebhook manager record (attempt + 1)

        _ -> do
            -- Final failure
            let errorMsg = case result of
                    Left e -> T.pack $ show (e :: HttpException)
                    Right response -> T.pack $ "HTTP " ++ show (statusCode $ responseStatus response)
            atomically $ do
                modifyTVar' (wmDeliveries manager) $ Map.adjust
                    (\r -> r { drStatus = Failed errorMsg now, drUpdated = now })
                    (drId record)
                modifyTVar' (wmMetrics manager) $ \m -> m
                    { wmFailedDeliveries = wmFailedDeliveries m + 1
                    , wmTotalDeliveries = wmTotalDeliveries m + 1
                    }

-- | Generate HMAC signature for payload
generateSignature :: Text -> LBS.ByteString -> ByteString
generateSignature secret payload =
    let key = TE.encodeUtf8 secret
        message = LBS.toStrict payload
        digest = hmacGetDigest $ hmac key message :: Hash.Digest SHA256
    in "sha256=" <> Base16.encode (Hash.digestToByteString digest)
