{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Middleware
    ( -- * Authentication
      authHandler
    , authMiddleware
      -- * Error handling
    , errorHandler
    , withErrorHandling
      -- * Validation
    , validateRequest
    , withValidation
      -- * Rate limiting
    , withRateLimit
      -- * Logging
    , logRequest
    , withLogging
    ) where

import Control.Monad.Catch (MonadCatch, catch)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (ToJSON(..), object, (.=))
import Data.Text (Text)
import Data.Time (getCurrentTime)
import Network.Wai (Middleware, Request, requestMethod, rawPathInfo, requestHeaders)
import Servant
import System.Log.FastLogger (LogStr, ToLogStr(..), pushLogStrLn)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

import Gerrit.Api.Config (Config(..))
import Gerrit.Api.Types (ErrorResponse(..), Response(..))
import Gerrit.Api.Validation
import Gerrit.Api.RateLimit (RateLimitConfig(..), withRateLimit)
import Gerrit.Api.Metrics (Metrics(..), incrementErrors, incrementRequests, observeRequestDuration)

-- | Authentication handler for protected endpoints
authHandler :: Metrics -> Request -> Handler Text
authHandler metrics req = case lookup "Authorization" (requestHeaders req) of
    Nothing -> do
        liftIO $ incrementErrors metrics
        throwError err401 { errBody = "Missing authorization header" }
    Just token -> do
        -- TODO: Implement proper JWT validation
        let bearerToken = Text.drop 7 $ Text.decodeUtf8 token
        if Text.null bearerToken
            then do
                liftIO $ incrementErrors metrics
                throwError err401 { errBody = "Invalid token" }
            else return bearerToken

-- | Authentication middleware
authMiddleware :: Metrics -> Middleware
authMiddleware metrics app req respond = do
    result <- runHandler $ authHandler metrics req
    case result of
        Left err -> respond $ errToResponse err
        Right _ -> app req respond

-- | Error handler that converts exceptions to proper API responses
errorHandler :: Metrics -> SomeException -> Handler (Response a)
errorHandler metrics e = do
    liftIO $ incrementErrors metrics
    return $ Response
        { success = False
        , data_ = Nothing
        , audit = Nothing
        , error = Just $ ErrorResponse $ Text.pack $ show e
        }

-- | Middleware for consistent error handling
withErrorHandling :: Metrics -> Middleware
withErrorHandling metrics app req respond = app req respond `catch` \e -> do
    result <- runHandler $ errorHandler metrics e
    respond $ responseToPending result

-- | Request validation middleware
validateRequest :: Metrics -> Config -> Request -> Handler ()
validateRequest metrics config req = do
    -- Apply validation rules based on request type
    let rules = [
            contentTypeRule,
            contentLengthRule,
            paginationRule
            ]
            ++ [ changeRequestRule | isChangeRequest req ]
            ++ [ commentRequestRule | isCommentRequest req ]
            ++ [ voteRequestRule | isVoteRequest req ]

    result <- liftIO $ validate metrics config req rules
    case result of
        Just err -> throwError err400
            { errBody = "Validation error: " <> Text.encodeUtf8 (errorMessage err)
            }
        Nothing -> return ()
  where
    isChangeRequest req = requestMethod req == "POST" && "/api/v1/changes" `Text.isInfixOf` Text.decodeUtf8 (rawPathInfo req)
    isCommentRequest req = requestMethod req == "POST" && "/comments" `Text.isInfixOf` Text.decodeUtf8 (rawPathInfo req)
    isVoteRequest req = requestMethod req == "POST" && "/votes" `Text.isInfixOf` Text.decodeUtf8 (rawPathInfo req)

-- | Middleware for request validation
withValidation :: Metrics -> Config -> Middleware
withValidation metrics config app req respond = do
    result <- runHandler $ validateRequest metrics config req
    case result of
        Left err -> respond $ errToResponse err
        Right _ -> app req respond

-- | Log request details
logRequest :: MonadIO m => Request -> m ()
logRequest req = liftIO $ do
    now <- getCurrentTime
    let logEntry = object
            [ "timestamp" .= now
            , "method" .= (Text.decodeUtf8 $ requestMethod req)
            , "path" .= (Text.decodeUtf8 $ rawPathInfo req)
            , "headers" .= object
                [ "user-agent" .= maybe "" Text.decodeUtf8 (lookup "User-Agent" $ requestHeaders req)
                , "content-type" .= maybe "" Text.decodeUtf8 (lookup "Content-Type" $ requestHeaders req)
                , "content-length" .= maybe "0" Text.decodeUtf8 (lookup "Content-Length" $ requestHeaders req)
                ]
            ]
    -- TODO: Use proper logging configuration
    print logEntry

-- | Middleware for request logging
withLogging :: Middleware
withLogging app req respond = do
    logRequest req
    app req respond

-- | Helper functions

-- | Convert a Servant error to a WAI response
errToResponse :: ServerError -> Response
errToResponse err = responseToPending $ Response
    { success = False
    , data_ = Nothing
    , audit = Nothing
    , error = Just $ ErrorResponse $ Text.pack $ errBody err
    }

-- | Convert a Response to a WAI response
responseToPending :: Response -> Response
responseToPending = id  -- TODO: Implement proper response conversion
