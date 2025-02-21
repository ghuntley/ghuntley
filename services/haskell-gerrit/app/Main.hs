-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import Control.Monad.Logger (runStderrLoggingT)
import Control.Monad.Reader (ReaderT, runReaderT)
import Database.Persist.Postgresql
import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.Cors (simpleCors)
import Servant
import System.Environment (getEnv)

import Gerrit.Api.Types
import Gerrit.Models.Types
import qualified Gerrit.Api.Handlers as H
import qualified Gerrit.Database.Connection as DB

-- | Application configuration
data Config = Config
    { configPool :: ConnectionPool
    , configPort :: Int
    , configGitBasePath :: FilePath
    }

-- | Application monad
type App = ReaderT Config Handler

-- | Server implementation
server :: ServerT GerritAPI App
server = projectServer :<|> changeServer :<|> commentServer
  where
    projectServer = H.createProject
                :<|> H.getProject
                :<|> H.listProjects

    changeServer = H.createChange
                :<|> H.getChange
                :<|> H.listChanges
                :<|> H.listRevisions
                :<|> H.reviewChange
                :<|> H.submitChange

    commentServer changeId revisionId =
                H.createComment changeId revisionId
                :<|> H.listComments changeId revisionId

-- | Convert our App monad to Handler
nt :: Config -> App a -> Handler a
nt cfg app = runReaderT app cfg

-- | Application API
app :: Config -> Application
app cfg = serve (Proxy :: Proxy GerritAPI)
    $ hoistServer (Proxy :: Proxy GerritAPI) (nt cfg) server

-- | Main entry point
main :: IO ()
main = do
    -- Get configuration from environment
    dbHost <- getEnv "GERRIT_DB_HOST"
    dbName <- getEnv "GERRIT_DB_NAME"
    dbUser <- getEnv "GERRIT_DB_USER"
    dbPass <- getEnv "GERRIT_DB_PASS"
    port <- read <$> getEnv "GERRIT_PORT"
    gitPath <- getEnv "GERRIT_GIT_PATH"

    -- Create database connection pool
    let connStr = DB.createConnStr dbHost dbName dbUser dbPass
    pool <- runStderrLoggingT $ createPostgresqlPool connStr 10

    -- Run migrations
    runStderrLoggingT $ DB.runMigrations pool

    -- Create config
    let config = Config
            { configPool = pool
            , configPort = port
            , configGitBasePath = gitPath
            }

    -- Start server
    putStrLn $ "Starting server on port " ++ show port
    run port $ simpleCors $ app config
