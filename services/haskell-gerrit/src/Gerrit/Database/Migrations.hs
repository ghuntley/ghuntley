-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}

module Gerrit.Database.Migrations
    ( -- * Migration Management
      runMigrations
    , checkMigrations
    , getMigrationStatus
      -- * Types
    , MigrationStatus(..)
    , MigrationError(..)
    ) where

import Control.Exception (try)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Logger (MonadLogger, runStderrLoggingT)
import Data.Aeson (ToJSON(..), FromJSON(..), Value)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Postgresql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types (migrateAll)
import Gerrit.Models.Change ()
import Gerrit.Models.Revision ()
import Gerrit.Models.Comment ()
import Gerrit.Models.Vote ()
import Gerrit.Models.Organization ()
import Gerrit.Models.Enterprise ()
import Gerrit.Models.Admin ()
import Gerrit.Models.Stack ()
import Gerrit.Models.Alert ()
import Gerrit.Models.AuditLog ()
import Gerrit.Models.Billing ()

-- | Migration status
data MigrationStatus
    = MigrationNeeded [Text]  -- ^ List of pending migrations
    | MigrationUpToDate       -- ^ No migrations needed
    | MigrationFailed MigrationError  -- ^ Migration failed with error
    deriving (Show, Eq, Generic)

instance ToJSON MigrationStatus
instance FromJSON MigrationStatus

-- | Migration error types
data MigrationError
    = DatabaseConnectionError Text
    | SchemaVersionError Text
    | MigrationExecutionError Text
    | UnknownMigrationError Text
    deriving (Show, Eq, Generic)

instance ToJSON MigrationError
instance FromJSON MigrationError

-- | Define migration tracking
share [mkPersist sqlSettings] [persistLowerCase|
MigrationHistory
    version Int
    name Text
    appliedAt UTCTime
    details Value Maybe
    UniqueMigrationVersion version
    deriving Show Eq Generic
|]

-- | Run all pending migrations
runMigrations :: MonadIO m => ConnectionPool -> m (Either MigrationError ())
runMigrations pool = liftIO $ try (runSqlPool action pool) >>= \case
    Left err -> return $ Left $ DatabaseConnectionError $ T.pack $ show err
    Right result -> return $ Right result
  where
    action = do
        -- Create migration history table if it doesn't exist
        runMigration $ migrate (undefined :: MigrationHistory)

        -- Run all model migrations
        runMigration migrateAll

        -- Record migration in history
        now <- liftIO getCurrentTime
        let version = getLatestSchemaVersion
        insertUnique $ MigrationHistory
            { migrationHistoryVersion = version
            , migrationHistoryName = "full_schema_migration"
            , migrationHistoryAppliedAt = now
            , migrationHistoryDetails = Nothing
            }

-- | Check if migrations are needed
checkMigrations :: MonadIO m => ConnectionPool -> m MigrationStatus
checkMigrations pool = liftIO $ try (runSqlPool action pool) >>= \case
    Left err -> return $ MigrationFailed $ DatabaseConnectionError $ T.pack $ show err
    Right result -> return result
  where
    action = do
        currentVersion <- getCurrentSchemaVersion
        let latestVersion = getLatestSchemaVersion
        if currentVersion < latestVersion
            then do
                pending <- getPendingMigrations
                return $ MigrationNeeded pending
            else return MigrationUpToDate

-- | Get detailed migration status
getMigrationStatus :: MonadIO m => ConnectionPool -> m MigrationStatus
getMigrationStatus pool = liftIO $ try (runSqlPool action pool) >>= \case
    Left err -> return $ MigrationFailed $ DatabaseConnectionError $ T.pack $ show err
    Right result -> return result
  where
    action = do
        mVersion <- getCurrentSchemaVersion
        case mVersion of
            Left err -> return $ MigrationFailed $ SchemaVersionError err
            Right version -> do
                let latest = getLatestSchemaVersion
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
            result <- selectList [] [Desc MigrationHistoryVersion, LimitTo 1]
            case result of
                [Entity _ mh] -> return $ Right $ migrationHistoryVersion mh
                _ -> return $ Right 0
        else return $ Right 0

-- | Get latest schema version from models
getLatestSchemaVersion :: Int
getLatestSchemaVersion = 1  -- Increment this when adding new migrations

-- | Get list of pending migrations
getPendingMigrations :: MonadIO m => SqlPersistT m [Text]
getPendingMigrations = do
    eCurrentVersion <- getCurrentSchemaVersion
    case eCurrentVersion of
        Left err -> return [err]
        Right current -> do
            let latest = getLatestSchemaVersion
            return $ map (T.pack . show) [current + 1 .. latest]

-- | Get list of database tables
getTables :: MonadIO m => SqlPersistT m [Text]
getTables = do
    results <- rawSql "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'" []
    return $ map unSingle results

-- | Get list of applied migrations
getAppliedMigrations :: MonadIO m => SqlPersistT m [Entity MigrationHistory]
getAppliedMigrations =
    selectList [] [Asc MigrationHistoryVersion]
