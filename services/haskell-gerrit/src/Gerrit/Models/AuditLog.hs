{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Models.AuditLog
    ( -- * Types
      AuditLog(..)
    , AuditLogId
    , AuditAction(..)
      -- * Operations
    , createAuditLog
    , queryAuditLogs
    , getAuditLogById
    , exportAuditLogs
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (ToJSON(..), FromJSON(..), Value, encode)
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import qualified Data.Text as Text
import qualified Data.ByteString.Lazy as BL
import qualified Data.Csv as Csv
import GHC.Generics

import Gerrit.Models.Types

-- | Types of actions that can be audited
data AuditAction
    = AuthLogin                -- User login
    | AuthLogout               -- User logout
    | AuthTokenGen            -- API token generation
    | AuthRoleChange          -- Role/permission changes
    | ResourceCreate          -- Resource creation
    | ResourceRead            -- Resource access
    | ResourceUpdate          -- Resource modification
    | ResourceDelete          -- Resource deletion
    | ConfigChange            -- System configuration changes
    | SecurityEvent           -- Security-related events
    | RepoOperation          -- Repository operations
    | ReviewActivity         -- Code review activities
    | MergeOperation         -- Merge operations
    | AdminAction            -- Administrative actions
    | IntegrationEvent       -- Integration/webhook events
    deriving (Show, Read, Eq, Generic)

instance ToJSON AuditAction
instance FromJSON AuditAction

-- | Create a new audit log entry
createAuditLog :: MonadIO m
               => ConnectionPool
               -> Text  -- ^ User ID
               -> AuditAction
               -> Text  -- ^ Action details
               -> Maybe Text  -- ^ Additional details
               -> m (Entity AuditLog)
createAuditLog pool userId' action' details' additionalDetails' = do
    now <- liftIO getCurrentTime
    let logId' = generateAuditLogId userId' action' now
    let entry = AuditLog
            { auditLogLogId = logId'
            , auditLogUserId = userId'
            , auditLogAction = Text.pack $ show action'
            , auditLogDetails = details'
            , auditLogTimestamp = now
            }
    runSqlPool (insertEntity entry) pool

-- | Query audit logs with filtering
queryAuditLogs :: MonadIO m
               => ConnectionPool
               -> Maybe UTCTime  -- ^ Start time
               -> Maybe UTCTime  -- ^ End time
               -> Maybe AuditAction  -- ^ Filter by action
               -> Int  -- ^ Limit
               -> Int  -- ^ Offset
               -> m [Entity AuditLog]
queryAuditLogs pool start end action limit offset = do
    let filters = concat
            [ maybe [] (\s -> [AuditLogTimestamp >=. s]) start
            , maybe [] (\e -> [AuditLogTimestamp <=. e]) end
            , maybe [] (\a -> [AuditLogAction ==. Text.pack (show a)]) action
            ]
    runSqlPool (selectList filters [Desc AuditLogTimestamp, LimitTo limit, OffsetBy offset]) pool

-- | Get an audit log entry by ID
getAuditLogById :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Log ID
                -> m (Maybe (Entity AuditLog))
getAuditLogById pool logId' =
    runSqlPool (getBy $ UniqueLogId logId') pool

-- | Export audit logs to different formats
data ExportFormat = JSON | CSV
    deriving (Show, Eq)

exportAuditLogs :: MonadIO m
                => ConnectionPool
                -> FilePath  -- ^ Output file path
                -> ExportFormat  -- ^ Desired format
                -> m ()
exportAuditLogs pool path format = do
    logs <- queryAuditLogs pool Nothing Nothing Nothing 1000 0
    liftIO $ case format of
        JSON -> BL.writeFile path $ encode $ map entityVal logs
        CSV -> BL.writeFile path $ Csv.encode $ map entityVal logs

-- | Helper function to generate a unique audit log ID
generateAuditLogId :: Text -> AuditAction -> UTCTime -> Text
generateAuditLogId userId action timestamp =
    "al" <> Text.pack (show action) <> "-" <> userId <> "-" <> Text.pack (show timestamp)
