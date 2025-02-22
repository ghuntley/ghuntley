-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Auth.APIToken
    ( APITokenAuth(..)
    , APITokenConfig(..)
    , initAPITokenAuth
    , generateAPIToken
    , validateAPIToken
    , revokeAPIToken
    , listAPITokens
    , updateAPITokenScopes
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime, addUTCTime)
import Database.PostgreSQL.Simple (Connection, Only(..), query, execute)
import System.Random (randomRIO)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID

import Gerrit.Auth.Types

data APITokenConfig = APITokenConfig
    { apiTokenPrefix :: Text
    , apiTokenLength :: Int
    , apiTokenDefaultExpiry :: Int  -- in seconds, 0 for no expiry
    }

data APITokenAuth = APITokenAuth
    { apiTokenConfig :: APITokenConfig
    , apiTokenConn :: Connection
    }

initAPITokenAuth :: APITokenConfig -> Connection -> APITokenAuth
initAPITokenAuth config conn = APITokenAuth
    { apiTokenConfig = config
    , apiTokenConn = conn
    }

-- | Generate a new API token
generateAPIToken :: MonadIO m => APITokenAuth -> User -> [Text] -> m AuthToken
generateAPIToken auth user scopes = liftIO $ do
    now <- getCurrentTime
    uuid <- UUID.nextRandom
    let config = apiTokenConfig auth
        token = T.concat [apiTokenPrefix config, T.pack $ UUID.toString uuid]
        expiryTime = case apiTokenDefaultExpiry config of
            0 -> maxBound  -- No expiry
            seconds -> addUTCTime (fromIntegral seconds) now

    -- Store token in database
    let sql = "INSERT INTO api_tokens \
              \(token_value, user_id, scopes, created_at, expires_at) \
              \VALUES (?, ?, ?, ?, ?)"
    void $ execute (apiTokenConn auth) sql
        ( token
        , userId user
        , scopes
        , now
        , expiryTime
        )

    pure $ AuthToken
        { tokenValue = token
        , tokenType = APIToken
        , tokenExpiry = expiryTime
        , tokenScopes = scopes
        , tokenCSRFToken = Nothing
        }

-- | Validate an API token
validateAPIToken :: MonadIO m => APITokenAuth -> AuthToken -> m Bool
validateAPIToken auth token = liftIO $ do
    now <- getCurrentTime
    let sql = "SELECT COUNT(*) FROM api_tokens \
              \WHERE token_value = ? \
              \AND (expires_at > ? OR expires_at IS NULL) \
              \AND revoked_at IS NULL"
    [Only count] <- query (apiTokenConn auth) sql (tokenValue token, now)
    pure (count > 0)

-- | Revoke an API token
revokeAPIToken :: MonadIO m => APITokenAuth -> AuthToken -> m Bool
revokeAPIToken auth token = liftIO $ do
    now <- getCurrentTime
    let sql = "UPDATE api_tokens \
              \SET revoked_at = ? \
              \WHERE token_value = ? \
              \AND revoked_at IS NULL"
    n <- execute (apiTokenConn auth) sql (now, tokenValue token)
    pure (n > 0)

-- | List all API tokens for a user
listAPITokens :: MonadIO m => APITokenAuth -> User -> m [AuthToken]
listAPITokens auth user = liftIO $ do
    let sql = "SELECT token_value, scopes, created_at, expires_at \
              \FROM api_tokens \
              \WHERE user_id = ? \
              \AND revoked_at IS NULL"
    rows <- query (apiTokenConn auth) sql (Only $ userId user)
    pure [AuthToken
        { tokenValue = value
        , tokenType = APIToken
        , tokenExpiry = expiry
        , tokenScopes = scopes
        , tokenCSRFToken = Nothing
        }
        | (value, scopes, _, expiry) <- rows
        ]

-- | Update API token scopes
updateAPITokenScopes :: MonadIO m => APITokenAuth -> AuthToken -> [Text] -> m Bool
updateAPITokenScopes auth token newScopes = liftIO $ do
    let sql = "UPDATE api_tokens \
              \SET scopes = ? \
              \WHERE token_value = ? \
              \AND revoked_at IS NULL"
    n <- execute (apiTokenConn auth) sql (newScopes, tokenValue token)
    pure (n > 0)
