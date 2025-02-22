-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}

module Gerrit.Database.Connection
    ( -- * Types
      DatabaseConfig(..)
    , ConnectionPool
    , ConnectionError(..)
      -- * Connection Management
    , createConnPool
    , withConnPool
    , closeConnPool
    , runMigrations
    , runDB
    , withTransaction
      -- * Helper Functions
    , createConnStr
    , validateConfig
    ) where

import Control.Exception (try, throwIO, Exception)
import Control.Monad.Logger (MonadLogger, runStderrLoggingT, LogLevel(..))
import Control.Monad.Reader (MonadReader, asks)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime)
import Database.Persist.Postgresql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Database.Migrations (runMigrations, MigrationError)
import qualified Gerrit.Database.Migrations as Migrations

-- | Database configuration
data DatabaseConfig = DatabaseConfig
    { dbHost :: Text
    , dbPort :: Int
    , dbName :: Text
    , dbUser :: Text
    , dbPassword :: Text
    , dbPoolSize :: Int
    , dbPoolIdleTimeout :: NominalDiffTime  -- ^ Seconds before closing idle connections
    , dbPoolMaxLifetime :: NominalDiffTime  -- ^ Maximum lifetime of a connection in seconds
    , dbPoolStripes :: Int  -- ^ Number of stripes (sub-pools)
    , dbLogLevel :: LogLevel  -- ^ Database logging level
    } deriving (Show, Generic)

-- | Database connection errors
data ConnectionError
    = ConfigError Text
    | ConnectionFailed Text
    | PoolCreationFailed Text
    | MigrationFailed MigrationError
    deriving (Show, Eq, Generic)

instance Exception ConnectionError

-- | Create a PostgreSQL connection pool
createConnPool :: MonadIO m => DatabaseConfig -> m (Either ConnectionError ConnectionPool)
createConnPool config = liftIO $ do
    case validateConfig config of
        Left err -> return $ Left $ ConfigError err
        Right _ -> do
            result <- try $ runStderrLoggingT $ do
                let connStr = createConnStr config
                createPostgresqlPool connStr (dbPoolSize config)
            case result of
                Left err -> return $ Left $ ConnectionFailed $ T.pack $ show (err :: SqlError)
                Right pool -> return $ Right pool

-- | Run an action with a connection pool
withConnPool :: MonadIO m
             => DatabaseConfig
             -> (ConnectionPool -> m a)
             -> m (Either ConnectionError a)
withConnPool config action = do
    poolResult <- createConnPool config
    case poolResult of
        Left err -> return $ Left err
        Right pool -> do
            result <- action pool
            liftIO $ closeConnPool pool
            return $ Right result

-- | Close a connection pool
closeConnPool :: MonadIO m => ConnectionPool -> m ()
closeConnPool = liftIO . destroyAllResources

-- | Run database migrations
runMigrations :: MonadIO m => ConnectionPool -> m (Either ConnectionError ())
runMigrations pool = do
    result <- Migrations.runMigrations pool
    case result of
        Left err -> return $ Left $ MigrationFailed err
        Right _ -> return $ Right ()

-- | Run a database action in a reader monad
runDB :: (MonadReader r m, MonadIO m)
      => (r -> ConnectionPool)  -- ^ Function to get the connection pool from the environment
      -> SqlPersistT IO a      -- ^ Database action to run
      -> m (Either ConnectionError a)
runDB getPool action = do
    pool <- asks getPool
    result <- liftIO $ try $ runSqlPool action pool
    case result of
        Left err -> return $ Left $ ConnectionFailed $ T.pack $ show (err :: SqlError)
        Right value -> return $ Right value

-- | Run a database action within a transaction
withTransaction :: (MonadReader r m, MonadIO m)
                => (r -> ConnectionPool)
                -> SqlPersistT IO a
                -> m (Either ConnectionError a)
withTransaction getPool action = do
    pool <- asks getPool
    result <- liftIO $ try $ runSqlPool (transactionalSave action) pool
    case result of
        Left err -> return $ Left $ ConnectionFailed $ T.pack $ show (err :: SqlError)
        Right value -> return $ Right value

-- | Create a PostgreSQL connection string
createConnStr :: DatabaseConfig -> ConnectionString
createConnStr DatabaseConfig{..} =
    pgConnStr $ PostgresConf
        { pgConnHost = T.unpack dbHost
        , pgConnPort = dbPort
        , pgConnDatabase = T.unpack dbName
        , pgConnUser = T.unpack dbUser
        , pgConnPassword = T.unpack dbPassword
        , pgConnSchema = "public"
        , pgConnPoolIdleTimeout = round dbPoolIdleTimeout
        , pgConnPoolMaxLifetime = round dbPoolMaxLifetime
        , pgConnPoolStripes = dbPoolStripes
        }

-- | Validate database configuration
validateConfig :: DatabaseConfig -> Either Text ()
validateConfig DatabaseConfig{..} = do
    -- Validate host
    when (T.null dbHost) $
        Left "Database host cannot be empty"

    -- Validate port
    when (dbPort <= 0 || dbPort > 65535) $
        Left "Invalid database port number"

    -- Validate database name
    when (T.null dbName) $
        Left "Database name cannot be empty"

    -- Validate user
    when (T.null dbUser) $
        Left "Database user cannot be empty"

    -- Validate pool settings
    when (dbPoolSize <= 0) $
        Left "Pool size must be positive"
    when (dbPoolStripes <= 0) $
        Left "Number of stripes must be positive"
    when (dbPoolIdleTimeout < 0) $
        Left "Pool idle timeout cannot be negative"
    when (dbPoolMaxLifetime < 0) $
        Left "Pool max lifetime cannot be negative"

    Right ()
  where
    when :: Bool -> Text -> Either Text ()
    when cond msg = if cond then Left msg else Right ()
