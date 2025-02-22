-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Auth.OAuth
    ( OAuthAuth(..)
    , initOAuthAuth
    , getAuthorizationUrl
    , handleCallback
    , refreshToken
    , validateToken
    , revokeToken
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Exception (try, throwIO)
import Crypto.Random (getRandomBytes)
import Data.Aeson (Value(..), decode, encode, object, (.=))
import Data.ByteString (ByteString)
import qualified Data.ByteString.Base64 as Base64
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (UTCTime, getCurrentTime, addUTCTime)
import Network.HTTP.Client
import Network.HTTP.Client.TLS
import Network.HTTP.Types.Status
import Network.HTTP.Types.URI (renderQuery)
import Web.JWT (JWT, EncodeSigner, DecodeSigner, JWTClaimsSet)
import qualified Web.JWT as JWT

import Gerrit.Auth.Types

-- | OAuth authentication manager
data OAuthAuth = OAuthAuth
    { oaConfig :: OAuthConfig
    , oaManager :: Manager
    , oaJWTSigner :: EncodeSigner
    , oaJWTVerifier :: DecodeSigner
    }

-- | Initialize OAuth authentication
initOAuthAuth :: MonadIO m => OAuthConfig -> m OAuthAuth
initOAuthAuth config = liftIO $ do
    manager <- newManager tlsManagerSettings
    -- Initialize JWT signer and verifier
    let secret = oauthClientSecret config
        signer = JWT.hmacSecret $ TE.encodeUtf8 secret
        verifier = signer
    pure $ OAuthAuth config manager signer verifier

-- | Get authorization URL
getAuthorizationUrl :: MonadIO m => OAuthAuth -> m (Text, Text)
getAuthorizationUrl auth = liftIO $ do
    state <- generateState
    let config = oaConfig auth
        baseUrl = oauthAuthEndpoint config
        query = renderQuery True
            [ ("client_id", Just $ TE.encodeUtf8 $ oauthClientId config)
            , ("redirect_uri", Just $ TE.encodeUtf8 $ oauthRedirectUri config)
            , ("scope", Just $ TE.encodeUtf8 $ T.intercalate " " $ oauthScopes config)
            , ("state", Just $ TE.encodeUtf8 state)
            , ("response_type", Just "code")
            ] ++
            -- Add PKCE parameters if enabled
            if oauthPKCE config
                then pkceParameters
                else []
        url = baseUrl <> T.pack (show query)
    pure (url, state)

-- | Handle OAuth callback
handleCallback :: MonadIO m => OAuthAuth -> Text -> Text -> m AuthResult
handleCallback auth code state = liftIO $ do
    -- Validate state parameter
    unless (validateState state) $
        pure $ AuthFailure $ ConfigurationError "Invalid state parameter"

    -- Exchange code for token
    tokenResult <- exchangeCode auth code
    case tokenResult of
        Right token -> do
            -- Get user info
            userResult <- getUserInfo auth token
            case userResult of
                Right user ->
                    pure $ AuthSuccess token user
                Left err ->
                    pure $ AuthFailure err
        Left err ->
            pure $ AuthFailure err

-- | Refresh access token
refreshToken :: MonadIO m => OAuthAuth -> Text -> m (Maybe AuthToken)
refreshToken auth refreshToken = liftIO $ do
    let config = oaConfig auth
        url = oauthTokenEndpoint config
        body = renderQuery False
            [ ("grant_type", Just "refresh_token")
            , ("refresh_token", Just $ TE.encodeUtf8 refreshToken)
            , ("client_id", Just $ TE.encodeUtf8 $ oauthClientId config)
            , ("client_secret", Just $ TE.encodeUtf8 $ oauthClientSecret config)
            ]

    request <- parseRequest $ T.unpack url
    let request' = request
            { method = "POST"
            , requestBody = RequestBodyBS body
            , requestHeaders =
                [ ("Content-Type", "application/x-www-form-urlencoded")
                ]
            }

    response <- try $ httpLbs request' (oaManager auth)
    case response of
        Right res
            | statusCode (responseStatus res) == 200 ->
                case decode (responseBody res) of
                    Just obj -> do
                        now <- getCurrentTime
                        pure $ Just $ AuthToken
                            { tokenValue = obj Map.! "access_token"
                            , tokenType = BearerToken
                            , tokenExpiry = addUTCTime (obj Map.! "expires_in") now
                            , tokenScopes = T.splitOn " " (obj Map.! "scope")
                            }
                    Nothing -> pure Nothing
        _ -> pure Nothing

-- | Validate access token
validateToken :: MonadIO m => OAuthAuth -> AuthToken -> m Bool
validateToken auth token = liftIO $ do
    let config = oaConfig auth
        url = oauthTokenEndpoint config <> "/validate"
        request = parseRequest_ $ T.unpack url

    response <- try $ httpLbs request
        { requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 (tokenValue token))
            ]
        }
        (oaManager auth)

    pure $ case response of
        Right res -> statusCode (responseStatus res) == 200
        Left _ -> False

-- | Revoke access token
revokeToken :: MonadIO m => OAuthAuth -> AuthToken -> m Bool
revokeToken auth token = liftIO $ do
    let config = oaConfig auth
        url = oauthTokenEndpoint config <> "/revoke"
        body = renderQuery False
            [ ("token", Just $ TE.encodeUtf8 $ tokenValue token)
            , ("client_id", Just $ TE.encodeUtf8 $ oauthClientId config)
            , ("client_secret", Just $ TE.encodeUtf8 $ oauthClientSecret config)
            ]

    request <- parseRequest $ T.unpack url
    let request' = request
            { method = "POST"
            , requestBody = RequestBodyBS body
            , requestHeaders =
                [ ("Content-Type", "application/x-www-form-urlencoded")
                ]
            }

    response <- try $ httpLbs request' (oaManager auth)
    pure $ case response of
        Right res -> statusCode (responseStatus res) == 200
        Left _ -> False

-- Helper functions

-- | Exchange authorization code for token
exchangeCode :: OAuthAuth -> Text -> IO (Either AuthError AuthToken)
exchangeCode auth code = do
    let config = oaConfig auth
        url = oauthTokenEndpoint config
        body = renderQuery False
            [ ("grant_type", Just "authorization_code")
            , ("code", Just $ TE.encodeUtf8 code)
            , ("redirect_uri", Just $ TE.encodeUtf8 $ oauthRedirectUri config)
            , ("client_id", Just $ TE.encodeUtf8 $ oauthClientId config)
            , ("client_secret", Just $ TE.encodeUtf8 $ oauthClientSecret config)
            ]

    request <- parseRequest $ T.unpack url
    let request' = request
            { method = "POST"
            , requestBody = RequestBodyBS body
            , requestHeaders =
                [ ("Content-Type", "application/x-www-form-urlencoded")
                ]
            }

    response <- try $ httpLbs request' (oaManager auth)
    case response of
        Right res
            | statusCode (responseStatus res) == 200 ->
                case decode (responseBody res) of
                    Just obj -> do
                        now <- getCurrentTime
                        pure $ Right $ AuthToken
                            { tokenValue = obj Map.! "access_token"
                            , tokenType = BearerToken
                            , tokenExpiry = addUTCTime (obj Map.! "expires_in") now
                            , tokenScopes = T.splitOn " " (obj Map.! "scope")
                            }
                    Nothing -> pure $ Left $ ServerError "Invalid token response"
            | otherwise ->
                pure $ Left $ ServerError "Token request failed"
        Left err ->
            pure $ Left $ ServerError $ T.pack $ show err

-- | Get user info from provider
getUserInfo :: OAuthAuth -> AuthToken -> IO (Either AuthError User)
getUserInfo auth token = do
    let config = oaConfig auth
        url = oauthUserInfoEndpoint config
        request = parseRequest_ $ T.unpack url

    response <- try $ httpLbs request
        { requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 (tokenValue token))
            ]
        }
        (oaManager auth)

    case response of
        Right res
            | statusCode (responseStatus res) == 200 ->
                case decode (responseBody res) of
                    Just obj -> do
                        now <- getCurrentTime
                        let roles = mapRoles config obj
                        pure $ Right $ User
                            { userId = obj Map.! "id"
                            , userName = obj Map.! "login"
                            , userEmail = obj Map.! "email"
                            , userFullName = obj Map.! "name"
                            , userRoles = roles
                            , userGroups = []
                            , userProvider = OAuthProvider $ oaConfig auth
                            , userCreated = now
                            , userLastLogin = now
                            , userMFAEnabled = False
                            }
                    Nothing -> pure $ Left $ ServerError "Invalid user info response"
            | otherwise ->
                pure $ Left $ ServerError "User info request failed"
        Left err ->
            pure $ Left $ ServerError $ T.pack $ show err

-- | Map provider roles to system roles
mapRoles :: OAuthConfig -> Value -> [Role]
mapRoles config userInfo =
    let mapping = oauthRoleMapping config
        defaultRoles = [Guest]
    in case userInfo of
        Object obj ->
            Map.foldrWithKey
                (\k v acc ->
                    case Map.lookup k mapping of
                        Just role -> read (T.unpack role) : acc
                        Nothing -> acc)
                defaultRoles
                obj
        _ -> defaultRoles

-- | Generate random state parameter
generateState :: IO Text
generateState = do
    bytes <- getRandomBytes 32
    pure $ TE.decodeUtf8 $ Base64.encode bytes

-- | Validate state parameter
validateState :: Text -> Bool
validateState = undefined  -- TODO: Implement state validation

-- | Generate PKCE parameters
pkceParameters :: [(ByteString, Maybe ByteString)]
pkceParameters = undefined  -- TODO: Implement PKCE
