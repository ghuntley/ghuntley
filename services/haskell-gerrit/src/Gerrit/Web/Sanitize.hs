{-|
Module      : Gerrit.Web.Sanitize
Description : Content sanitization functions for user-generated content
Copyright   : (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>
License     : Proprietary
Maintainer  : Geoffrey Huntley <ghuntley@ghuntley.com>
Stability   : experimental
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}

module Gerrit.Web.Sanitize
    ( -- * Content Sanitization
      sanitizeComment
    , sanitizeCommitMessage
    , sanitizeIssueDescription
    , sanitizeProfileInfo
    , sanitizeCustomField
    , sanitizeMarkdownField
      -- * Rate Limiting
    , RateLimitConfig(..)
    , defaultRateLimitConfig
    , withRateLimit
      -- * Error Types
    , SanitizationError(..)
    ) where

import Control.Concurrent.STM
import Control.Monad (when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import Gerrit.Middleware.XSS
import Gerrit.Web.Foundation (App(..))
import System.IO.Unsafe (unsafePerformIO)
import Yesod.Core

-- | Rate limiting configuration
data RateLimitConfig = RateLimitConfig
    { rlWindow :: Int          -- ^ Time window in seconds
    , rlMaxRequests :: Int     -- ^ Maximum requests per window
    , rlBucketSize :: Int      -- ^ Size of the token bucket
    }

-- | Default rate limit configuration
defaultRateLimitConfig :: RateLimitConfig
defaultRateLimitConfig = RateLimitConfig
    { rlWindow = 60            -- 1 minute window
    , rlMaxRequests = 1000     -- 1000 requests per minute
    , rlBucketSize = 100       -- Burst size of 100
    }

-- | Rate limiting state
data RateLimitState = RateLimitState
    { rlsLastReset :: UTCTime
    , rlsRequests :: Int
    }

-- | Global rate limit state
{-# NOINLINE rateLimitState #-}
rateLimitState :: TVar (Map Text RateLimitState)
rateLimitState = unsafePerformIO $ newTVarIO Map.empty

-- | Sanitization errors
data SanitizationError
    = RateLimitExceeded
    | InvalidContent Text
    | SanitizationFailed Text
    deriving (Show, Eq)

-- | Apply rate limiting to a sanitization function
withRateLimit :: (MonadHandler m)
              => RateLimitConfig
              -> Text            -- ^ Rate limit key
              -> m a            -- ^ Action to rate limit
              -> m (Either SanitizationError a)
withRateLimit RateLimitConfig{..} key action = do
    now <- liftIO getCurrentTime
    allowed <- liftIO $ atomically $ do
        states <- readTVar rateLimitState
        case Map.lookup key states of
            Nothing -> do
                writeTVar rateLimitState $ Map.insert key (RateLimitState now 1) states
                return True
            Just RateLimitState{..} -> do
                let timeDiff = diffUTCTime now rlsLastReset
                if timeDiff >= fromIntegral rlWindow
                    then do
                        writeTVar rateLimitState $ Map.insert key (RateLimitState now 1) states
                        return True
                    else if rlsRequests >= rlMaxRequests
                        then return False
                        else do
                            let newState = RateLimitState rlsLastReset (rlsRequests + 1)
                            writeTVar rateLimitState $ Map.insert key newState states
                            return True

    if allowed
        then Right <$> action
        else return $ Left RateLimitExceeded

-- | Sanitize a comment with rate limiting and error handling
sanitizeComment :: (MonadHandler m) => App -> Text -> m (Either SanitizationError Text)
sanitizeComment app content = withRateLimit defaultRateLimitConfig "comment" $ do
    let sanitized = sanitizeForContext (appXSSConfig app) MarkdownContext content
    when (sanitized /= content) $
        logSanitizationEvent app "comment" content sanitized
    return sanitized

-- | Sanitize a commit message with rate limiting and error handling
sanitizeCommitMessage :: (MonadHandler m) => App -> Text -> m (Either SanitizationError Text)
sanitizeCommitMessage app content = withRateLimit defaultRateLimitConfig "commit" $ do
    let sanitized = sanitizeForContext (appXSSConfig app) HTMLContext content
    when (sanitized /= content) $
        logSanitizationEvent app "commit" content sanitized
    return sanitized

-- | Sanitize an issue description with rate limiting and error handling
sanitizeIssueDescription :: (MonadHandler m) => App -> Text -> m (Either SanitizationError Text)
sanitizeIssueDescription app content = withRateLimit defaultRateLimitConfig "issue" $ do
    let sanitized = sanitizeForContext (appXSSConfig app) MarkdownContext content
    when (sanitized /= content) $
        logSanitizationEvent app "issue" content sanitized
    return sanitized

-- | Sanitize profile information with rate limiting and error handling
sanitizeProfileInfo :: (MonadHandler m) => App -> Text -> m (Either SanitizationError Text)
sanitizeProfileInfo app content = withRateLimit defaultRateLimitConfig "profile" $ do
    let sanitized = sanitizeForContext (appXSSConfig app) HTMLContext content
    when (sanitized /= content) $
        logSanitizationEvent app "profile" content sanitized
    return sanitized

-- | Sanitize a custom field with rate limiting and error handling
sanitizeCustomField :: (MonadHandler m) => App -> Context -> Text -> m (Either SanitizationError Text)
sanitizeCustomField app context content = withRateLimit defaultRateLimitConfig "custom" $ do
    let sanitized = sanitizeForContext (appXSSConfig app) context content
    when (sanitized /= content) $
        logSanitizationEvent app "custom" content sanitized
    return sanitized

-- | Sanitize a markdown field with rate limiting and error handling
sanitizeMarkdownField :: (MonadHandler m) => App -> Text -> m (Either SanitizationError Text)
sanitizeMarkdownField app content = withRateLimit defaultRateLimitConfig "markdown" $ do
    let sanitized = sanitizeForContext (appXSSConfig app) MarkdownContext content
    when (sanitized /= content) $
        logSanitizationEvent app "markdown" content sanitized
    return sanitized

-- | Log sanitization event
logSanitizationEvent :: (MonadHandler m) => App -> Text -> Text -> Text -> m ()
logSanitizationEvent app contentType original sanitized = do
    let config = appXSSConfig app
    when (auditFailures config && original /= sanitized) $ do
        now <- liftIO getCurrentTime
        $(logWarn) $ T.concat
            [ "Content sanitization event for type: "
            , contentType
            , "\nOriginal content: "
            , original
            , "\nSanitized content: "
            , sanitized
            , "\nTimestamp: "
            , T.pack (show now)
            ]
