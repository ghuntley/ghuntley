-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuasiQuotes #-}

module Gerrit.Web.Foundation where

import Data.Text (Text)
import Database.Persist.Postgresql (ConnectionPool)
import Yesod.Core
import Yesod.Auth
import Yesod.Auth.Message
import Yesod.Form
import Yesod.Static

import Gerrit.Models.Types
import Gerrit.Auth.JWT (JWTConfig)
import Gerrit.Middleware.CSRF (CSRFConfig(..), defaultCSRFConfig, csrfMiddleware)
import Gerrit.Middleware.XSS (XSSConfig(..), defaultXSSConfig, xssMiddleware)

-- | Site configuration
data App = App
    { appConnectionPool :: ConnectionPool
    , appJWTConfig :: JWTConfig
    , appStatic :: Static
    , appCSRFConfig :: CSRFConfig
    , appXSSConfig :: XSSConfig
    }

mkYesodData "App" [parseRoutes|
/static StaticR Static appStatic
/auth   AuthR   Auth   getAuth

/                     HomeR     GET
/projects            ProjectsR  GET POST
/projects/#Text      ProjectR   GET
/changes             ChangesR   GET POST
/changes/#Text       ChangeR    GET
/changes/#Text/diff  ChangeDiffR GET
/profile             ProfileR   GET

/api/docs/openapi.json SwaggerJsonR GET
/api/docs            SwaggerUIR GET

/api/admin AdminR Admin adminRoutes
|]

instance Yesod App where
    -- Enable sessions
    makeSessionBackend _ = Just <$> defaultClientSessionBackend
        120    -- timeout in minutes
        "config/client_session_key.aes"

    -- Add security middleware to the application
    yesodMiddleware handler = do
        app <- getYesod
        let csrfM = csrfMiddleware (appCSRFConfig app)
            xssM = xssMiddleware (appXSSConfig app)
        defaultYesodMiddleware $ xssM . csrfM $ handler

    -- Authorization
    isAuthorized route _write = case route of
        -- Public routes
        HomeR -> return Authorized
        AuthR _ -> return Authorized
        StaticR _ -> return Authorized
        SwaggerJsonR -> return Authorized  -- Allow access to OpenAPI spec
        SwaggerUIR -> return Authorized    -- Allow access to Swagger UI

        -- Protected routes
        _ -> do
            mauth <- maybeAuthId
            return $ case mauth of
                Nothing -> AuthenticationRequired
                Just _ -> Authorized

    -- Add default layout
    defaultLayout widget = do
        pc <- widgetToPageContent $ do
            addStylesheet $ StaticR css_bootstrap_css
            addStylesheet $ StaticR css_main_css
            $(widgetFile "default-layout")
        withUrlRenderer $(hamletFile "templates/default-layout-wrapper.hamlet")

instance YesodAuth App where
    type AuthId App = UserId

    -- Use JWT authentication
    authenticate creds = do
        -- TODO: Implement JWT authentication
        return $ UserError InvalidLogin

    -- Login route
    loginDest _ = HomeR

    -- Logout route
    logoutDest _ = HomeR

    -- Enable authentication methods
    authPlugins _ = []  -- We'll use our own JWT authentication

instance RenderMessage App FormMessage where
    renderMessage _ _ = defaultFormMessage
