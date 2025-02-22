{-|
Module      : Gerrit.Middleware.CSRF
Description : CSRF protection middleware
Copyright   : (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>
License     : Proprietary
Maintainer  : Geoffrey Huntley <ghuntley@ghuntley.com>
Stability   : experimental
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gerrit.Middleware.CSRF
  ( CSRFConfig(..)
  , defaultCSRFConfig
  , csrfMiddleware
  , generateCSRFToken
  , validateCSRFToken
  ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Crypto.Random (getRandomBytes)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Base64 as Base64
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Time
import Network.HTTP.Types
import Network.Wai
import Web.Cookie

data CSRFConfig = CSRFConfig
  { csrfTokenLength :: Int        -- ^ Length of the CSRF token in bytes
  , csrfTokenHeader :: ByteString -- ^ Name of the header containing the CSRF token
  , csrfCookieName :: ByteString  -- ^ Name of the cookie containing the CSRF token
  , csrfTokenExpiry :: NominalDiffTime -- ^ Token expiration time in seconds
  }

defaultCSRFConfig :: CSRFConfig
defaultCSRFConfig = CSRFConfig
  { csrfTokenLength = 32
  , csrfTokenHeader = "X-CSRF-Token"
  , csrfCookieName = "XSRF-TOKEN"
  , csrfTokenExpiry = 3600 -- 1 hour
  }

-- | Generate a new CSRF token
generateCSRFToken :: MonadIO m => CSRFConfig -> m Text
generateCSRFToken CSRFConfig{..} = liftIO $ do
  randomBytes <- getRandomBytes csrfTokenLength
  return $ TE.decodeUtf8 $ Base64.encode randomBytes

-- | Validate a CSRF token against the stored cookie value
validateCSRFToken :: Request -> CSRFConfig -> Maybe ByteString -> ByteString -> Bool
validateCSRFToken req CSRFConfig{..} mCookieToken headerToken =
  case mCookieToken of
    Nothing -> False
    Just cookieToken ->
      -- Check if tokens match and the request method requires validation
      cookieToken == headerToken && requiresProtection (requestMethod req)

-- | Middleware to protect against CSRF attacks
csrfMiddleware :: CSRFConfig -> Middleware
csrfMiddleware config@CSRFConfig{..} app req respond = do
  case (requiresProtection (requestMethod req), lookup csrfTokenHeader (requestHeaders req)) of
    -- If the method requires protection and there's no CSRF token header, reject
    (True, Nothing) -> respond $ responseLBS status403 [] "CSRF token missing"

    -- If the method requires protection and there's a CSRF token header, validate
    (True, Just headerToken) -> do
      let mCookieToken = findCookie csrfCookieName req
      if validateCSRFToken req config mCookieToken headerToken
        then app req respond
        else respond $ responseLBS status403 [] "CSRF token validation failed"

    -- If the method doesn't require protection, proceed
    (False, _) -> app req respond

-- | Helper function to find a cookie value
findCookie :: ByteString -> Request -> Maybe ByteString
findCookie name req = do
  cookies <- lookup "cookie" (requestHeaders req)
  lookup name (parseCookies cookies)

-- | Helper function to determine if a request method requires CSRF protection
requiresProtection :: Method -> Bool
requiresProtection method = method `elem` ["POST", "PUT", "DELETE", "PATCH"]
