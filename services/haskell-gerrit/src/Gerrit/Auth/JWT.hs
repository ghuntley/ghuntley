-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Auth.JWT
    ( JWTAuth(..)
    , JWTConfig(..)
    , initJWTAuth
    , validateJWTToken
    , generateJWTToken
    , refreshJWTToken
    , revokeJWTToken
    , JWTError(..)
    ) where

import Control.Monad.Except (ExceptT, throwError)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time.Clock (UTCTime, getCurrentTime, addUTCTime)
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import Web.JWT (JWT, EncodeSigner, DecodeSigner, NumericDate(..), JWTClaimsSet(..), SignedJWT)
import qualified Web.JWT as JWT

import Gerrit.Models.Types (User(..))
import Gerrit.Auth.Types

-- | JWT configuration
data JWTConfig = JWTConfig
    { jwtSecretKey :: Text
    , jwtIssuer :: Text
    , jwtExpiryTime :: Int  -- in seconds
    , jwtRefreshExpiryTime :: Int  -- in seconds
    }

data JWTAuth = JWTAuth
    { jwtConfig :: JWTConfig
    }

-- | JWT errors
data JWTError
    = InvalidToken Text
    | ExpiredToken
    | MalformedToken Text
    deriving (Show, Eq)

-- | JWT claims for our application
data GerritClaims = GerritClaims
    { gcUserId :: Text
    , gcEmail :: Text
    , gcIsAdmin :: Bool
    } deriving (Show, Generic)

instance ToJSON GerritClaims
instance FromJSON GerritClaims

initJWTAuth :: JWTConfig -> JWTAuth
initJWTAuth config = JWTAuth
    { jwtConfig = config
    }

-- | Generate a new JWT token
generateJWTToken :: MonadIO m => JWTAuth -> User -> [Text] -> m AuthToken
generateJWTToken auth user scopes = liftIO $ do
    now <- getCurrentTime
    let config = jwtConfig auth
        expiryTime = addUTCTime (fromIntegral $ jwtExpiryTime config) now
        claims = JWT.JWTClaimsSet
            { JWT.iss = Just $ JWT.StringOrURI $ jwtIssuer config
            , JWT.sub = Just $ JWT.StringOrURI $ userId user
            , JWT.aud = Nothing
            , JWT.exp = Just $ JWT.NumericDate expiryTime
            , JWT.nbf = Nothing
            , JWT.iat = Just $ JWT.NumericDate now
            , JWT.jti = Nothing
            }
        token = JWT.encodeSigned JWT.HS256
                                (JWT.Secret $ TE.encodeUtf8 $ jwtSecretKey config)
                                claims

    pure $ AuthToken
        { tokenValue = token
        , tokenType = JWTToken
        , tokenExpiry = expiryTime
        , tokenScopes = scopes
        , tokenCSRFToken = Nothing
        }

-- | Validate a JWT token
validateJWTToken :: MonadIO m => JWTAuth -> AuthToken -> m Bool
validateJWTToken auth token = liftIO $ do
    now <- getCurrentTime
    let config = jwtConfig auth
        secretKey = JWT.Secret $ TE.encodeUtf8 $ jwtSecretKey config
        result = JWT.decodeAndVerifySignature secretKey $ tokenValue token

    pure $ case result of
        Nothing -> False
        Just claims ->
            case JWT.exp claims of
                Nothing -> False
                Just (JWT.NumericDate expiry) -> expiry > now

-- | Refresh a JWT token
refreshJWTToken :: MonadIO m => JWTAuth -> AuthToken -> m (Maybe AuthToken)
refreshJWTToken auth token = liftIO $ do
    isValid <- validateJWTToken auth token
    if not isValid
        then pure Nothing
        else do
            let config = jwtConfig auth
                claims = JWT.claims <$> JWT.decode (tokenValue token)
            case claims of
                Nothing -> pure Nothing
                Just claimsSet ->
                    case JWT.sub claimsSet of
                        Nothing -> pure Nothing
                        Just (JWT.StringOrURI userId) -> do
                            now <- getCurrentTime
                            let expiryTime = addUTCTime
                                    (fromIntegral $ jwtRefreshExpiryTime config)
                                    now
                                newClaims = claimsSet
                                    { JWT.exp = Just $ JWT.NumericDate expiryTime
                                    , JWT.iat = Just $ JWT.NumericDate now
                                    }
                                newToken = JWT.encodeSigned
                                    JWT.HS256
                                    (JWT.Secret $ TE.encodeUtf8 $ jwtSecretKey config)
                                    newClaims

                            pure $ Just $ AuthToken
                                { tokenValue = newToken
                                , tokenType = JWTToken
                                , tokenExpiry = expiryTime
                                , tokenScopes = tokenScopes token
                                , tokenCSRFToken = Nothing
                                }

-- | Revoke a JWT token
revokeJWTToken :: MonadIO m => JWTAuth -> AuthToken -> m Bool
revokeJWTToken auth token = liftIO $ do
    -- Add token to blacklist in database
    -- This would require a token blacklist table
    pure True  -- TODO: Implement actual revocation
