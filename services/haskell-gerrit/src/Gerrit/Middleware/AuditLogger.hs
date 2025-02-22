-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Middleware.AuditLogger
    ( AuditLoggerConfig(..)
    , withAuditLogging
    , logOperation
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (ReaderT, ask)
import Data.Aeson (Value, object, (.=))
import Data.Text (Text)
import Data.Time (getCurrentTime)
import Network.Wai
import Network.Wai.Internal
import System.Log.FastLogger
import Web.HttpApiData

import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as T
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import qualified Network.HTTP.Types as HTTP

import Gerrit.Models.AuditLog
import Gerrit.Auth (AuthenticatedUser(..))

-- | Configuration for audit logging
data AuditLoggerConfig = AuditLoggerConfig
    { alcConnection :: Connection      -- Database connection
    , alcLogger :: LoggerSet          -- Fast logger for async logging
    , alcExcludePaths :: [Text]       -- Paths to exclude from audit logging
    }

-- | Middleware to add audit logging to all requests
withAuditLogging :: AuditLoggerConfig -> Middleware
withAuditLogging config app req respond = do
    -- Generate request ID
    requestId <- UUID.toString <$> UUID.nextRandom

    -- Extract user info from request
    let mUser = lookup "X-User-ID" (requestHeaders req)
        mEnterpriseId = lookup "X-Enterprise-ID" (requestHeaders req)

    -- Create audit context
    let context = AuditContext
            { acRequestId = T.pack requestId
            , acIpAddress = T.pack $ BS.unpack $ remoteHost req
            , acUserAgent = maybe "" (T.pack . BS.unpack) $ lookup "User-Agent" (requestHeaders req)
            , acSessionId = fmap (T.pack . BS.unpack) $ lookup "X-Session-ID" (requestHeaders req)
            }

    -- Only log if path is not excluded
    if shouldLog (pathInfo req) (alcExcludePaths config)
        then do
            -- Log the request
            logOperation config
                (maybe "anonymous" (T.pack . BS.unpack) mUser)
                (maybe "unknown" (T.pack . BS.unpack) mEnterpriseId)
                (determineAction req)
                (determineResource req)
                (requestDetails req)
                context

            -- Wrap response to log outcome
            app req $ \res -> do
                -- Log response status
                let details = object
                        [ "status" .= statusCode (responseStatus res)
                        , "duration" .= ("TODO" :: Text)
                        ]
                logOperation config
                    (maybe "anonymous" (T.pack . BS.unpack) mUser)
                    (maybe "unknown" (T.pack . BS.unpack) mEnterpriseId)
                    (determineAction req)
                    (determineResource req)
                    details
                    context
                respond res
        else
            app req respond

-- | Log a single operation
logOperation
    :: MonadIO m
    => AuditLoggerConfig
    -> Text              -- User ID
    -> Text              -- Enterprise ID
    -> AuditAction       -- Action type
    -> AuditResource     -- Resource affected
    -> Value             -- Operation details
    -> AuditContext      -- Request context
    -> m UUID.UUID
logOperation AuditLoggerConfig{..} userId enterpriseId action resource details context = liftIO $ do
    timestamp <- getCurrentTime
    entryId <- UUID.nextRandom

    let entry = AuditLogEntry
            { aleId = entryId
            , aleTimestamp = timestamp
            , aleEnterpriseId = enterpriseId
            , aleUserId = userId
            , aleAction = action
            , aleResource = resource
            , aleDetails = details
            , aleContext = context
            }

    -- Async log to database
    void $ createAuditLog alcConnection entry

    -- Also log to fast logger for immediate visibility
    pushLogStr alcLogger $
        toLogStr $ show entry <> "\n"

    pure entryId

-- | Determine if request should be logged
shouldLog :: [Text] -> [Text] -> Bool
shouldLog path excludes =
    not $ any (`elem` excludes) path

-- | Determine action type from request
determineAction :: Request -> AuditAction
determineAction req = case requestMethod req of
    "GET"    -> ResourceRead
    "POST"   -> ResourceCreate
    "PUT"    -> ResourceUpdate
    "PATCH"  -> ResourceUpdate
    "DELETE" -> ResourceDelete
    _        -> ResourceRead

-- | Determine resource type from request path
determineResource :: Request -> AuditResource
determineResource req = case pathInfo req of
    "users" : rest     -> UserResource $ T.intercalate "/" rest
    "roles" : rest     -> RoleResource $ T.intercalate "/" rest
    "repos" : rest     -> RepoResource $ T.intercalate "/" rest
    "reviews" : rest   -> ReviewResource $ T.intercalate "/" rest
    "config" : rest    -> ConfigResource $ T.intercalate "/" rest
    "tokens" : rest    -> TokenResource $ T.intercalate "/" rest
    "webhooks" : rest  -> WebhookResource $ T.intercalate "/" rest
    "enterprises" : rest -> EnterpriseResource $ T.intercalate "/" rest
    "orgs" : rest      -> OrganizationResource $ T.intercalate "/" rest
    _                  -> ConfigResource "unknown"

-- | Extract request details
requestDetails :: Request -> Value
requestDetails req = object
    [ "method" .= decodeUtf8 (requestMethod req)
    , "path" .= pathInfo req
    , "query" .= decodeUtf8 (rawQueryString req)
    ]
