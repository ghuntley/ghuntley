{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.RateLimit
    ( -- * Rate limiting
      RateLimitConfig(..)
    , RateLimitError(..)
    , withRateLimit
    ) where

import Control.Concurrent.STM
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime, diffUTCTime)
import Network.Wai (Middleware, Request, requestHeaders, remoteHost)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

import Gerrit.Api.Types (ErrorResponse(..), Response(..))
import Gerrit.Api.Metrics (Metrics(..), incrementRateLimitExceeded)

-- | Rate limit configuration
data RateLimitConfig = RateLimitConfig
    { -- | Maximum number of requests per window
      maxRequests :: Int
      -- | Time window in seconds
    , timeWindow :: Int
      -- | Whether to use IP-based rate limiting
    , useIpLimit :: Bool
      -- | Whether to use token-based rate limiting
    , useTokenLimit :: Bool
    } deriving (Show, Eq)

-- | Rate limit error
data RateLimitError = RateLimitError
    { errorCode :: Text
    , errorMessage :: Text
    , retryAfter :: Int
    } deriving (Show, Eq)

-- | Rate limit entry
data RateLimitEntry = RateLimitEntry
    { requestCount :: Int
    , windowStart :: UTCTime
    } deriving (Show, Eq)

-- | Rate limit state
data RateLimitState = RateLimitState
    { ipLimits :: Map String RateLimitEntry
    , tokenLimits :: Map Text RateLimitEntry
    }

-- | Create a new rate limit state
newRateLimitState :: IO (TVar RateLimitState)
newRateLimitState = newTVarIO $ RateLimitState
    { ipLimits = Map.empty
    , tokenLimits = Map.empty
    }

-- | Rate limiting middleware
withRateLimit :: Metrics -> RateLimitConfig -> IO Middleware
withRateLimit metrics config = do
    state <- newRateLimitState
    return $ \app req respond -> do
        result <- checkRateLimit metrics config state req
        case result of
            Left err -> do
                -- Record rate limit exceeded metric
                incrementRateLimitExceeded metrics
                respond $ rateLimitErrorResponse err
            Right _ -> app req respond

-- | Check rate limits for a request
checkRateLimit :: Metrics -> RateLimitConfig -> TVar RateLimitState -> Request -> IO (Either RateLimitError ())
checkRateLimit metrics RateLimitConfig{..} stateVar req = do
    now <- getCurrentTime

    -- Check IP-based rate limit
    when useIpLimit $ do
        let ip = show $ remoteHost req
        ipResult <- atomically $ checkLimit stateVar now ip maxRequests timeWindow ipLimits
        case ipResult of
            Left err -> return $ Left err
            Right _ -> return ()

    -- Check token-based rate limit
    when useTokenLimit $ do
        case lookup "Authorization" (requestHeaders req) of
            Just token -> do
                let bearerToken = Text.decodeUtf8 $ Text.drop 7 token
                tokenResult <- atomically $ checkLimit stateVar now bearerToken maxRequests timeWindow tokenLimits
                case tokenResult of
                    Left err -> return $ Left err
                    Right _ -> return ()
            Nothing -> return ()

    return $ Right ()

-- | Check a single rate limit
checkLimit :: (Ord k)
          => TVar RateLimitState
          -> UTCTime
          -> k
          -> Int
          -> Int
          -> (RateLimitState -> Map k RateLimitEntry)
          -> STM (Either RateLimitError ())
checkLimit stateVar now key maxReqs window getMap = do
    state <- readTVar stateVar
    let limits = getMap state
    case Map.lookup key limits of
        Nothing -> do
            -- First request, create new entry
            let newEntry = RateLimitEntry 1 now
            let newLimits = Map.insert key newEntry limits
            writeTVar stateVar $ state { ipLimits = newLimits }
            return $ Right ()
        Just entry -> do
            let windowDiff = diffUTCTime now (windowStart entry)
            if windowDiff >= fromIntegral window
                then do
                    -- Window expired, reset counter
                    let newEntry = RateLimitEntry 1 now
                    let newLimits = Map.insert key newEntry limits
                    writeTVar stateVar $ state { ipLimits = newLimits }
                    return $ Right ()
                else if requestCount entry >= maxReqs
                    then do
                        -- Rate limit exceeded
                        let remaining = window - floor windowDiff
                        return $ Left $ RateLimitError
                            "RATE_LIMIT_EXCEEDED"
                            "Too many requests"
                            remaining
                    else do
                        -- Increment counter
                        let newEntry = entry { requestCount = requestCount entry + 1 }
                        let newLimits = Map.insert key newEntry limits
                        writeTVar stateVar $ state { ipLimits = newLimits }
                        return $ Right ()

-- | Convert rate limit error to response
rateLimitErrorResponse :: RateLimitError -> Response
rateLimitErrorResponse RateLimitError{..} = Response
    { success = False
    , data_ = Nothing
    , audit = Nothing
    , error = Just $ ErrorResponse errorMessage
    }
