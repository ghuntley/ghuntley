-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Gerrit.Models.MigrationHistory where

import Data.Aeson
import Data.Text (Text)
import Data.Time
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

-- | Migration status enumeration
data MigrationStatus = Pending | InProgress | Completed | Failed | Rolled
    deriving (Show, Eq, Generic)

instance ToJSON MigrationStatus
instance FromJSON MigrationStatus

-- | Migration direction
data MigrationDirection = Up | Down
    deriving (Show, Eq, Generic)

instance ToJSON MigrationDirection
instance FromJSON MigrationDirection

-- | Persistent models for migration tracking
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
MigrationHistory
    version Int
    name Text
    description Text Maybe
    appliedAt UTCTime
    completedAt UTCTime Maybe
    status MigrationStatus
    direction MigrationDirection
    details Value Maybe
    appliedBy Text
    checksum Text
    UniqueMigrationVersion version
    deriving Show Eq Generic

MigrationLock
    lockId Text
    acquiredAt UTCTime
    acquiredBy Text
    expiresAt UTCTime
    UniqueMigrationLock lockId
    deriving Show Eq Generic

MigrationError
    migrationVersion Int
    errorMessage Text
    errorDetails Value Maybe
    occurredAt UTCTime
    Foreign MigrationHistory migrationVersion References migrationHistories OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Helper functions for migration management
logMigration :: MonadIO m
             => Int       -- ^ Version
             -> Text     -- ^ Name
             -> Text     -- ^ Applied by
             -> Text     -- ^ Checksum
             -> Maybe Text -- ^ Description
             -> Maybe Value -- ^ Details
             -> MigrationDirection -- ^ Direction
             -> m (Either Text ())
logMigration version name appliedBy checksum desc details direction = do
    now <- getCurrentTime
    runDB $ insert_ MigrationHistory
        { migrationHistoryVersion = version
        , migrationHistoryName = name
        , migrationHistoryDescription = desc
        , migrationHistoryAppliedAt = now
        , migrationHistoryCompletedAt = Nothing
        , migrationHistoryStatus = InProgress
        , migrationHistoryDirection = direction
        , migrationHistoryDetails = details
        , migrationHistoryAppliedBy = appliedBy
        , migrationHistoryChecksum = checksum
        }
    return $ Right ()

completeMigration :: MonadIO m
                  => Int  -- ^ Version
                  -> m (Either Text ())
completeMigration version = do
    now <- getCurrentTime
    runDB $ updateWhere
        [MigrationHistoryVersion ==. version]
        [MigrationHistoryCompletedAt =. Just now
        , MigrationHistoryStatus =. Completed]
    return $ Right ()

failMigration :: MonadIO m
              => Int  -- ^ Version
              -> Text -- ^ Error message
              -> Maybe Value -- ^ Error details
              -> m (Either Text ())
failMigration version errorMsg errorDetails = do
    now <- getCurrentTime
    runDB $ do
        updateWhere
            [MigrationHistoryVersion ==. version]
            [MigrationHistoryStatus =. Failed]
        insert_ MigrationError
            { migrationErrorMigrationVersion = version
            , migrationErrorErrorMessage = errorMsg
            , migrationErrorErrorDetails = errorDetails
            , migrationErrorOccurredAt = now
            }
    return $ Right ()

acquireMigrationLock :: MonadIO m
                     => Text  -- ^ Lock ID
                     -> Text  -- ^ Acquired by
                     -> NominalDiffTime  -- ^ Lock duration
                     -> m (Either Text ())
acquireMigrationLock lockId acquiredBy duration = do
    now <- getCurrentTime
    let expiresAt = addUTCTime duration now
    runDB $ do
        -- Delete expired locks
        deleteWhere [MigrationLockExpiresAt <=. now]
        -- Try to acquire lock
        existingLock <- selectFirst [MigrationLockLockId ==. lockId] []
        case existingLock of
            Just _ -> return $ Left "Lock already acquired"
            Nothing -> do
                insert_ MigrationLock
                    { migrationLockLockId = lockId
                    , migrationLockAcquiredAt = now
                    , migrationLockAcquiredBy = acquiredBy
                    , migrationLockExpiresAt = expiresAt
                    }
                return $ Right ()

releaseMigrationLock :: MonadIO m
                     => Text  -- ^ Lock ID
                     -> Text  -- ^ Acquired by
                     -> m (Either Text ())
releaseMigrationLock lockId acquiredBy = do
    runDB $ deleteWhere [MigrationLockLockId ==. lockId
                       , MigrationLockAcquiredBy ==. acquiredBy]
    return $ Right ()

getMigrationHistory :: MonadIO m
                    => m [Entity MigrationHistory]
getMigrationHistory = runDB $ selectList [] [Asc MigrationHistoryVersion]

getMigrationErrors :: MonadIO m
                   => Int  -- ^ Version
                   -> m [Entity MigrationError]
getMigrationErrors version =
    runDB $ selectList [MigrationErrorMigrationVersion ==. version] [Desc MigrationErrorOccurredAt]
