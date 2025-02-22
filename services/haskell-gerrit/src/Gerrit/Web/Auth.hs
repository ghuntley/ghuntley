-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Web.Auth
    ( JWTAuthPlugin(..)
    , jwtAuthPlugin
    , authenticateToken
    ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Except (runExceptT)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Database.Persist
import Yesod.Auth
import Yesod.Core
import Yesod.Persist

import Gerrit.Models.Types
import Gerrit.Web.Foundation
import Gerrit.Auth.JWT
import qualified Gerrit.Database.Connection as DB

-- | JWT authentication plugin
data JWTAuthPlugin = JWTAuthPlugin

-- | Create a JWT authentication plugin
jwtAuthPlugin :: AuthPlugin App
jwtAuthPlugin = AuthPlugin
    { apName = "jwt"
    , apDispatch = \master -> dispatchJWT master
    , apLogin = \master -> loginHandlerJWT master
    }

-- | JWT authentication dispatch
dispatchJWT :: App -> Text -> [Text] -> Handler TypedContent
dispatchJWT app "POST" ["login"] = do
    ((result, _), _) <- runFormPost loginForm
    case result of
        FormSuccess (email, password) -> do
            muser <- runDB $ getBy $ UniqueEmail email
            case muser of
                Nothing -> loginError "Invalid email or password"
                Just (Entity userId user)
                    | verifyPassword password (userPasswordHash user) -> do
                        -- Generate JWT token
                        token <- liftIO $ generateToken
                            (appJWTConfig app)
                            user
                        return $ toTypedContent $ object
                            [ "token" .= token
                            , "user" .= Entity userId user
                            ]
                    | otherwise -> loginError "Invalid email or password"
        _ -> loginError "Invalid form submission"
  where
    loginError msg = invalidArgs [msg]

dispatchJWT _ _ _ = notFound

-- | JWT login handler
loginHandlerJWT :: App -> Widget
loginHandlerJWT _ = do
    (widget, enctype) <- handlerToWidget $ generateFormPost loginForm
    [whamlet|
        <form method="post" action=@{AuthR $ PluginR "jwt" ["login"]} enctype=#{enctype}>
            ^{widget}
            <button type="submit">Login
    |]

-- | Login form
loginForm :: Form (Text, Text)
loginForm = renderBootstrap3 BootstrapBasicForm $
    (,) <$> areq emailField "Email" Nothing
        <*> areq passwordField "Password" Nothing

-- | Authenticate a JWT token and return the user
authenticateToken :: Text -> Handler User
authenticateToken token = do
    config <- getsYesod appJWTConfig
    result <- liftIO $ runExceptT $ verifyToken config token
    case result of
        Left err -> permissionDenied $ T.pack $ show err
        Right claims -> do
            muser <- runDB $ getBy $ UniqueEmail $ gcEmail claims
            case muser of
                Nothing -> permissionDenied "User not found"
                Just (Entity _ user) -> return user

-- | Verify a password hash
verifyPassword :: Text -> Text -> Bool
verifyPassword password hash = undefined  -- TODO: Implement password verification
