-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main (main) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)
import qualified Data.Text.IO as Text

import Gerrit.Api.Api (app)
import Gerrit.Api.Config (Config(..), LogConfig(..), loadConfig)
import Gerrit.Database.Connection (initializeDatabase)

-- | Initialize application
initialize :: Config -> IO ()
initialize config@Config{..} = do
    -- Ensure log directory exists
    let logDir = takeDirectory $ logPath configLogging
    createDirectoryIfMissing True logDir

    -- Initialize database
    initializeDatabase config

    -- Ensure Git base directory exists
    createDirectoryIfMissing True configGitBasePath

    -- Log startup information
    when (configEnvironment /= Production) $ do
        Text.putStrLn "Starting Gerrit Code Review System with configuration:"
        print config

-- | Main entry point
main :: IO ()
main = do
    -- Load configuration
    config <- loadConfig

    -- Initialize application
    initialize config

    -- Start the server
    app (configPort config)
