-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Gerrit.Database.Connection
    ( createConnStr
    , runMigrations
    , runDB
    ) where

import Control.Monad.Logger (MonadLogger)
import Control.Monad.Reader (MonadReader, asks)
import Control.Monad.IO.Class (MonadIO)
import Data.Text (Text)
import qualified Data.Text as T
import Database.Persist.Postgresql
import Database.Persist.TH

import Gerrit.Models.Types

-- | Create a PostgreSQL connection string
createConnStr :: String -> String -> String -> String -> ConnectionString
createConnStr host dbName user pass =
    "host=" <> T.pack host <>
    " dbname=" <> T.pack dbName <>
    " user=" <> T.pack user <>
    " password=" <> T.pack pass <>
    " port=5432"

-- | Run database migrations
runMigrations :: MonadIO m => ConnectionPool -> m ()
runMigrations pool = runSqlPool (runMigration migrateAll) pool

-- | Run a database action in the App monad
runDB :: (MonadReader r m, MonadIO m)
      => (r -> ConnectionPool)  -- ^ Function to get the connection pool from the environment
      -> SqlPersistT IO a       -- ^ Database action to run
      -> m a
runDB getPool action = do
    pool <- asks getPool
    liftIO $ runSqlPool action pool
