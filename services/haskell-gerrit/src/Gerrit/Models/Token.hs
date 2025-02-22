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

module Gerrit.Models.Token
    ( -- * Types
      TokenType(..)
    , TokenStatus(..)
    , RotationPolicy(..)
    , Token(..)
    , TokenId
    , TokenPolicy(..)
    , TokenPolicyId
    , TokenSession(..)
    , TokenSessionId
      -- * Operations
    , createToken
    , updateTokenStatus
    , getTokenById
    , listActiveTokens
    , revokeToken
    , revokeAllTokens
    , updateTokenPolicy
    , getTokenPolicy
    , createTokenSession
    , updateTokenSession
    , getTokenSessionById
    , listTokenSessions
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.User (User)

-- | Token type
data TokenType
    = AccessToken
    | RefreshToken
    | ApiKey
    deriving (Show, Read, Eq, Generic)
derivePersistField "TokenType"

-- | Token status
data TokenStatus
    = Active
    | Expired
    | Revoked
    | Rotated
    deriving (Show, Read, Eq, Generic)
derivePersistField "TokenStatus"

-- | Rotation policy
data RotationPolicy
    = OnRefresh
    | OnUse
    | Manual
    | Never
    deriving (Show, Read, Eq, Generic)
derivePersistField "RotationPolicy"

-- | Define the token entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Token
    tokenId Text
    userId Text
    tokenType TokenType
    status TokenStatus
    value Text
    scope Value
    refreshCount Int default=0
    refreshLimit Int Maybe
    deviceId Text Maybe
    ipAddress Text Maybe
    lastUsedAt UTCTime Maybe
    expiresAt UTCTime Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueTokenId tokenId
    UniqueTokenValue value
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic

TokenPolicy
    policyId Text
    tokenType TokenType
    expiration Int Maybe  -- In seconds, null means unlimited
    refreshAllowed Bool
    rotationPolicy RotationPolicy
    maxActiveTokens Int Maybe
    maxRefreshCount Int Maybe
    requireRotation Bool
    ipBindingRequired Bool
    deviceBindingRequired Bool
    allowedScopes Value
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniquePolicyId policyId
    UniqueTokenTypePolicy tokenType
    deriving Show Eq Generic

TokenSession
    sessionId Text
    tokenId Text
    deviceId Text Maybe
    deviceType Text Maybe
    ipAddress Text Maybe
    userAgent Text Maybe
    lastActivity UTCTime
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueSessionId sessionId
    Foreign Token tokenId References tokens OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new token
createToken :: MonadIO m
            => Text  -- ^ User ID
            -> TokenType  -- ^ Token type
            -> Value  -- ^ Scope
            -> Maybe Text  -- ^ Device ID
            -> Maybe Text  -- ^ IP address
            -> Maybe Int  -- ^ Refresh limit
            -> Maybe UTCTime  -- ^ Expiration time
            -> Maybe Value  -- ^ Additional metadata
            -> m (Entity Token)
createToken userId tokenType scope deviceId ipAddr refreshLimit expiresAt metadata = do
    now <- liftIO getCurrentTime
    let tokenId = generateTokenId userId tokenType now
    let token = Token
            { tokenTokenId = tokenId
            , tokenUserId = userId
            , tokenTokenType = tokenType
            , tokenStatus = Active
            , tokenValue = generateTokenValue tokenId now
            , tokenScope = scope
            , tokenRefreshCount = 0
            , tokenRefreshLimit = refreshLimit
            , tokenDeviceId = deviceId
            , tokenIpAddress = ipAddr
            , tokenLastUsedAt = Nothing
            , tokenExpiresAt = expiresAt
            , tokenMetadata = metadata
            , tokenCreated = now
            , tokenUpdated = now
            }
    runDB $ insertEntity token

-- | Update token status
updateTokenStatus :: MonadIO m
                  => Entity Token
                  -> TokenStatus
                  -> Maybe UTCTime  -- ^ Last used at
                  -> Maybe Value  -- ^ Additional metadata
                  -> m (Entity Token)
updateTokenStatus (Entity key token) status lastUsed metadata = do
    now <- liftIO getCurrentTime
    let updatedToken = token
            { tokenStatus = status
            , tokenLastUsedAt = lastUsed <|> tokenLastUsedAt token
            , tokenMetadata = metadata <|> tokenMetadata token
            , tokenUpdated = now
            }
    runDB $ replace key updatedToken
    return $ Entity key updatedToken

-- | Get token by ID
getTokenById :: MonadIO m
             => Text  -- ^ Token ID
             -> m (Maybe (Entity Token))
getTokenById tokenId =
    runDB $ getBy $ UniqueTokenId tokenId

-- | List active tokens
listActiveTokens :: MonadIO m
                 => Text  -- ^ User ID
                 -> Maybe TokenType  -- ^ Token type filter
                 -> Int  -- ^ Offset
                 -> Int  -- ^ Limit
                 -> m [Entity Token]
listActiveTokens userId mType offset limit = do
    let filters = (TokenUserId ==. userId) :
                 (TokenStatus ==. Active) :
                 maybe [] (\t -> [TokenTokenType ==. t]) mType
    runDB $ selectList filters [Desc TokenCreated, OffsetBy offset, LimitTo limit]

-- | Revoke token
revokeToken :: MonadIO m
            => Text  -- ^ Token ID
            -> Bool  -- ^ Revoke refresh token
            -> Bool  -- ^ Revoke all sessions
            -> m Int
revokeToken tokenId revokeRefresh revokeSessions = do
    now <- liftIO getCurrentTime
    count <- runDB $ do
        -- Revoke the main token
        updateWhere
            [TokenTokenId ==. tokenId]
            [ TokenStatus =. Revoked
            , TokenUpdated =. now
            ]

        when revokeRefresh $ do
            -- Get the user ID from the token
            mToken <- getBy $ UniqueTokenId tokenId
            forM_ mToken $ \(Entity _ token) -> do
                -- Revoke all refresh tokens for the user
                updateWhere
                    [ TokenUserId ==. tokenUserId token
                    , TokenTokenType ==. RefreshToken
                    ]
                    [ TokenStatus =. Revoked
                    , TokenUpdated =. now
                    ]

        when revokeSessions $ do
            -- Delete all sessions for the token
            deleteWhere [TokenSessionTokenId ==. tokenId]

        -- Return the number of affected tokens
        selectCount [TokenTokenId ==. tokenId, TokenStatus ==. Revoked]

    return count

-- | Revoke all tokens
revokeAllTokens :: MonadIO m
                => Text  -- ^ User ID
                -> m Int
revokeAllTokens userId = do
    now <- liftIO getCurrentTime
    runDB $ do
        -- Revoke all tokens
        updateCount
            [TokenUserId ==. userId]
            [ TokenStatus =. Revoked
            , TokenUpdated =. now
            ]

-- | Update token policy
updateTokenPolicy :: MonadIO m
                  => TokenType  -- ^ Token type
                  -> Maybe Int  -- ^ Expiration in seconds
                  -> Bool  -- ^ Refresh allowed
                  -> RotationPolicy  -- ^ Rotation policy
                  -> Maybe Int  -- ^ Max active tokens
                  -> Maybe Int  -- ^ Max refresh count
                  -> Bool  -- ^ Require rotation
                  -> Bool  -- ^ IP binding required
                  -> Bool  -- ^ Device binding required
                  -> Value  -- ^ Allowed scopes
                  -> Maybe Value  -- ^ Additional metadata
                  -> m (Entity TokenPolicy)
updateTokenPolicy tokenType expiration refreshAllowed rotation maxActive maxRefresh requireRot ipBinding deviceBinding scopes metadata = do
    now <- liftIO getCurrentTime
    let policyId = generatePolicyId tokenType now
    let policy = TokenPolicy
            { tokenPolicyPolicyId = policyId
            , tokenPolicyTokenType = tokenType
            , tokenPolicyExpiration = expiration
            , tokenPolicyRefreshAllowed = refreshAllowed
            , tokenPolicyRotationPolicy = rotation
            , tokenPolicyMaxActiveTokens = maxActive
            , tokenPolicyMaxRefreshCount = maxRefresh
            , tokenPolicyRequireRotation = requireRot
            , tokenPolicyIpBindingRequired = ipBinding
            , tokenPolicyDeviceBindingRequired = deviceBinding
            , tokenPolicyAllowedScopes = scopes
            , tokenPolicyMetadata = metadata
            , tokenPolicyCreated = now
            , tokenPolicyUpdated = now
            }
    runDB $ insertBy policy >>= \case
        Left (Entity key _) -> do
            replace key policy
            return $ Entity key policy
        Right entity -> return entity

-- | Get token policy
getTokenPolicy :: MonadIO m
               => TokenType  -- ^ Token type
               -> m (Maybe (Entity TokenPolicy))
getTokenPolicy tokenType =
    runDB $ getBy $ UniqueTokenTypePolicy tokenType

-- | Create token session
createTokenSession :: MonadIO m
                   => Text  -- ^ Token ID
                   -> Maybe Text  -- ^ Device ID
                   -> Maybe Text  -- ^ Device type
                   -> Maybe Text  -- ^ IP address
                   -> Maybe Text  -- ^ User agent
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity TokenSession)
createTokenSession tokenId deviceId deviceType ipAddr userAgent metadata = do
    now <- liftIO getCurrentTime
    let sessionId = generateSessionId tokenId now
    let session = TokenSession
            { tokenSessionSessionId = sessionId
            , tokenSessionTokenId = tokenId
            , tokenSessionDeviceId = deviceId
            , tokenSessionDeviceType = deviceType
            , tokenSessionIpAddress = ipAddr
            , tokenSessionUserAgent = userAgent
            , tokenSessionLastActivity = now
            , tokenSessionMetadata = metadata
            , tokenSessionCreated = now
            , tokenSessionUpdated = now
            }
    runDB $ insertEntity session

-- | Update token session
updateTokenSession :: MonadIO m
                   => Entity TokenSession
                   -> Maybe Text  -- ^ IP address
                   -> Maybe Text  -- ^ User agent
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity TokenSession)
updateTokenSession (Entity key session) ipAddr userAgent metadata = do
    now <- liftIO getCurrentTime
    let updatedSession = session
            { tokenSessionIpAddress = ipAddr <|> tokenSessionIpAddress session
            , tokenSessionUserAgent = userAgent <|> tokenSessionUserAgent session
            , tokenSessionLastActivity = now
            , tokenSessionMetadata = metadata <|> tokenSessionMetadata session
            , tokenSessionUpdated = now
            }
    runDB $ replace key updatedSession
    return $ Entity key updatedSession

-- | Get token session by ID
getTokenSessionById :: MonadIO m
                    => Text  -- ^ Session ID
                    -> m (Maybe (Entity TokenSession))
getTokenSessionById sessionId =
    runDB $ getBy $ UniqueSessionId sessionId

-- | List token sessions
listTokenSessions :: MonadIO m
                  => Text  -- ^ Token ID
                  -> Int  -- ^ Offset
                  -> Int  -- ^ Limit
                  -> m [Entity TokenSession]
listTokenSessions tokenId offset limit =
    runDB $ selectList
        [TokenSessionTokenId ==. tokenId]
        [Desc TokenSessionLastActivity, OffsetBy offset, LimitTo limit]

-- Helper functions for generating IDs and values
generateTokenId :: Text -> TokenType -> UTCTime -> Text
generateTokenId userId tokenType timestamp =
    prefix <> "_" <> Text.filter isAllowed userId <> "_" <> formatTime timestamp
  where
    prefix = case tokenType of
        AccessToken -> "at"
        RefreshToken -> "rt"
        ApiKey -> "ak"
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateTokenValue :: Text -> UTCTime -> Text
generateTokenValue tokenId timestamp =
    tokenId <> "_" <> formatTime timestamp

generatePolicyId :: TokenType -> UTCTime -> Text
generatePolicyId tokenType timestamp =
    "policy_" <> Text.pack (show tokenType) <> "_" <> formatTime timestamp

generateSessionId :: Text -> UTCTime -> Text
generateSessionId tokenId timestamp =
    "session_" <> Text.filter isAllowed tokenId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
