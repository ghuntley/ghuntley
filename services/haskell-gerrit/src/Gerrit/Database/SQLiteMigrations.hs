-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module Gerrit.Database.SQLiteMigrations
    ( -- * Migration Management
      runSQLiteMigrations
    , checkSQLiteMigrations
    , getSQLiteMigrationStatus
      -- * Types
    , SQLiteMigrationError(..)
    ) where

import Control.Exception (try)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Logger (MonadLogger, runStderrLoggingT)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist.Sqlite
import GHC.Generics

import Gerrit.Database.Migrations (MigrationStatus(..), MigrationError(..))
import qualified Gerrit.Database.Migrations as Migrations
import Gerrit.Models.Types (migrateAll)

-- | SQLite-specific migration errors
data SQLiteMigrationError
    = SQLiteFileError Text
    | SQLiteLockError Text
    | SQLiteSchemaError Text
    | SQLiteUnknownError Text
    deriving (Show, Eq, Generic)

-- | Run SQLite migrations
runSQLiteMigrations :: MonadIO m => ConnectionPool -> m (Either MigrationError ())
runSQLiteMigrations pool = liftIO $ try (runSqlPool action pool) >>= \case
    Left err -> return $ Left $ DatabaseConnectionError $ T.pack $ show err
    Right result -> return $ Right result
  where
    action = do
        -- Enable WAL mode for better concurrency during migrations
        rawExecute "PRAGMA journal_mode = WAL" []

        -- Create migration history table if it doesn't exist
        runMigration $ migrate (undefined :: Migrations.MigrationHistory)

        -- Run all model migrations
        runMigration migrateAll

        -- Record migration in history
        now <- liftIO getCurrentTime
        let version = Migrations.getLatestSchemaVersion
        insertUnique $ Migrations.MigrationHistory
            { Migrations.migrationHistoryVersion = version
            , Migrations.migrationHistoryName = "full_schema_migration"
            , Migrations.migrationHistoryAppliedAt = now
            , Migrations.migrationHistoryDetails = Nothing
            }

-- | Check if SQLite migrations are needed
checkSQLiteMigrations :: MonadIO m => ConnectionPool -> m MigrationStatus
checkSQLiteMigrations pool = liftIO $ try (runSqlPool action pool) >>= \case
    Left err -> return $ MigrationFailed $ DatabaseConnectionError $ T.pack $ show err
    Right result -> return result
  where
    action = do
        currentVersion <- getCurrentSchemaVersion
        let latestVersion = Migrations.getLatestSchemaVersion
        if currentVersion < latestVersion
            then do
                pending <- getPendingMigrations
                return $ MigrationNeeded pending
            else return MigrationUpToDate

-- | Get detailed SQLite migration status
getSQLiteMigrationStatus :: MonadIO m => ConnectionPool -> m MigrationStatus
getSQLiteMigrationStatus pool = liftIO $ try (runSqlPool action pool) >>= \case
    Left err -> return $ MigrationFailed $ DatabaseConnectionError $ T.pack $ show err
    Right result -> return result
  where
    action = do
        mVersion <- getCurrentSchemaVersion
        case mVersion of
            Left err -> return $ MigrationFailed $ SchemaVersionError err
            Right version -> do
                let latest = Migrations.getLatestSchemaVersion
                if version < latest
                    then do
                        pending <- getPendingMigrations
                        return $ MigrationNeeded pending
                    else return MigrationUpToDate

-- Helper functions

-- | Get current schema version from database
getCurrentSchemaVersion :: MonadIO m => SqlPersistT m (Either Text Int)
getCurrentSchemaVersion = do
    -- Check if migration history table exists
    tables <- getTables
    if "migration_history" `elem` tables
        then do
            -- Get latest migration version
            result <- selectList [] [Desc Migrations.MigrationHistoryVersion, LimitTo 1]
            case result of
                [Entity _ mh] -> return $ Right $ Migrations.migrationHistoryVersion mh
                _ -> return $ Right 0
        else return $ Right 0

-- | Get list of pending migrations
getPendingMigrations :: MonadIO m => SqlPersistT m [Text]
getPendingMigrations = do
    eCurrentVersion <- getCurrentSchemaVersion
    case eCurrentVersion of
        Left err -> return [err]
        Right current -> do
            let latest = Migrations.getLatestSchemaVersion
            return $ map (T.pack . show) [current + 1 .. latest]

-- | Get list of database tables
getTables :: MonadIO m => SqlPersistT m [Text]
getTables = do
    results <- rawSql "SELECT name FROM sqlite_master WHERE type='table'" []
    return $ map unSingle results

-- | Get list of applied migrations
getAppliedMigrations :: MonadIO m => SqlPersistT m [Entity Migrations.MigrationHistory]
getAppliedMigrations =
    selectList [] [Asc Migrations.MigrationHistoryVersion]

-- | Helper function to run raw SQL
runRawSQL :: MonadIO m => Text -> [PersistValue] -> SqlPersistT m ()
runRawSQL query params = rawExecute query params
