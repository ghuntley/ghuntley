-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module Gerrit.Database.SQLite
    ( -- * Types
      SQLiteConfig(..)
    , SQLiteError(..)
      -- * Connection Management
    , createSQLitePool
    , withSQLitePool
    , closeSQLitePool
      -- * Operations
    , runSQLite
    , withSQLiteTransaction
      -- * Configuration
    , validateSQLiteConfig
    , optimizeSQLiteConnection
    ) where

import Control.Exception (try, throwIO, Exception)
import Control.Monad.Logger (MonadLogger, runStderrLoggingT)
import Control.Monad.Reader (MonadReader, asks)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime)
import Database.Persist.Sqlite
import Database.SQLite.Simple (SQLiteException)
import Database.SQLite.Simple.Config
import GHC.Generics

import Gerrit.Database.Connection (ConnectionError(..))
import qualified Gerrit.Database.Connection as DB

-- | SQLite configuration
data SQLiteConfig = SQLiteConfig
    { dbPath :: Text  -- ^ Database file path
    , dbPoolSize :: Int  -- ^ Connection pool size
    , dbPoolIdleTimeout :: NominalDiffTime  -- ^ Idle connection timeout
    , dbJournalMode :: Text  -- ^ Journal mode (WAL recommended)
    , dbSynchronous :: Text  -- ^ Synchronous mode
    , dbCacheSize :: Int  -- ^ Cache size in pages
    , dbForeignKeys :: Bool  -- ^ Enable foreign key constraints
    } deriving (Show, Generic)

-- | SQLite-specific errors
data SQLiteError
    = FileAccessError Text
    | LockingError Text
    | CorruptionError Text
    | ConfigError Text
    deriving (Show, Eq, Generic)

instance Exception SQLiteError

-- | Create a SQLite connection pool
createSQLitePool :: MonadIO m => SQLiteConfig -> m (Either ConnectionError ConnectionPool)
createSQLitePool config = liftIO $ do
    case validateSQLiteConfig config of
        Left err -> return $ Left $ ConfigError err
        Right _ -> do
            result <- try $ runStderrLoggingT $ do
                let connStr = sqliteConnectionString config
                createSqlitePool connStr (dbPoolSize config)
            case result of
                Left err -> return $ Left $ ConnectionFailed $ T.pack $ show (err :: SQLiteException)
                Right pool -> do
                    -- Apply optimizations to all connections in the pool
                    mapM_ (optimizeSQLiteConnection config) =<< getConnections pool
                    return $ Right pool

-- | Run an action with a SQLite connection pool
withSQLitePool :: MonadIO m
               => SQLiteConfig
               -> (ConnectionPool -> m a)
               -> m (Either ConnectionError a)
withSQLitePool config action = do
    poolResult <- createSQLitePool config
    case poolResult of
        Left err -> return $ Left err
        Right pool -> do
            result <- action pool
            liftIO $ closeSQLitePool pool
            return $ Right result

-- | Close a SQLite connection pool
closeSQLitePool :: MonadIO m => ConnectionPool -> m ()
closeSQLitePool = liftIO . destroyAllResources

-- | Run a SQLite action
runSQLite :: (MonadReader r m, MonadIO m)
          => (r -> ConnectionPool)  -- ^ Function to get the connection pool
          -> SqlPersistT IO a      -- ^ Action to run
          -> m (Either ConnectionError a)
runSQLite getPool action = do
    pool <- asks getPool
    result <- liftIO $ try $ runSqlPool action pool
    case result of
        Left err -> return $ Left $ ConnectionFailed $ T.pack $ show (err :: SQLiteException)
        Right value -> return $ Right value

-- | Run a SQLite action within a transaction
withSQLiteTransaction :: (MonadReader r m, MonadIO m)
                     => (r -> ConnectionPool)
                     -> SqlPersistT IO a
                     -> m (Either ConnectionError a)
withSQLiteTransaction getPool action = do
    pool <- asks getPool
    result <- liftIO $ try $ runSqlPool (transactionSave action) pool
    case result of
        Left err -> return $ Left $ ConnectionFailed $ T.pack $ show (err :: SQLiteException)
        Right value -> return $ Right value

-- | Create SQLite connection string
sqliteConnectionString :: SQLiteConfig -> Text
sqliteConnectionString SQLiteConfig{..} =
    T.concat
        [ "file:"
        , dbPath
        , "?cache=shared"
        , "&mode=rwc"
        , "&_journal_mode=", dbJournalMode
        , "&_synchronous=", dbSynchronous
        , if dbForeignKeys then "&_foreign_keys=ON" else "&_foreign_keys=OFF"
        ]

-- | Validate SQLite configuration
validateSQLiteConfig :: SQLiteConfig -> Either Text ()
validateSQLiteConfig SQLiteConfig{..} = do
    -- Validate path
    when (T.null dbPath) $
        Left "Database path cannot be empty"

    -- Validate pool settings
    when (dbPoolSize <= 0) $
        Left "Pool size must be positive"
    when (dbPoolIdleTimeout < 0) $
        Left "Pool idle timeout cannot be negative"

    -- Validate journal mode
    unless (dbJournalMode `elem` ["DELETE", "TRUNCATE", "PERSIST", "MEMORY", "WAL", "OFF"]) $
        Left "Invalid journal mode"

    -- Validate synchronous mode
    unless (dbSynchronous `elem` ["OFF", "NORMAL", "FULL", "EXTRA"]) $
        Left "Invalid synchronous mode"

    -- Validate cache size
    when (dbCacheSize < 0) $
        Left "Cache size cannot be negative"

    Right ()
  where
    when :: Bool -> Text -> Either Text ()
    when cond msg = if cond then Left msg else Right ()
    unless :: Bool -> Text -> Either Text ()
    unless cond msg = when (not cond) msg

-- | Optimize SQLite connection settings
optimizeSQLiteConnection :: MonadIO m => SQLiteConfig -> SqlBackend -> m ()
optimizeSQLiteConnection config conn = liftIO $ do
    let statements =
            [ "PRAGMA journal_mode = " <> dbJournalMode config
            , "PRAGMA synchronous = " <> dbSynchronous config
            , "PRAGMA cache_size = " <> T.pack (show $ dbCacheSize config)
            , "PRAGMA foreign_keys = " <> if dbForeignKeys config then "ON" else "OFF"
            , "PRAGMA temp_store = MEMORY"
            , "PRAGMA mmap_size = 30000000000"
            , "PRAGMA page_size = 4096"
            ]
    mapM_ (rawExecute conn) statements
  where
    rawExecute conn stmt = rawExecute' conn stmt []
