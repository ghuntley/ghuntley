-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.VCS.Storage
    ( QueueStorage(..)
    , PostgresStorage(..)
    , MemoryStorage(..)
    , initPostgresStorage
    , initMemoryStorage
    ) where

import Control.Concurrent.STM
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (ToJSON(..), FromJSON(..), Value(..), encode, decode)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime)
import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.ToRow
import Database.PostgreSQL.Simple.FromRow
import Database.PostgreSQL.Simple.ToField
import Database.PostgreSQL.Simple.FromField

import Gerrit.VCS.Types

-- | Queue storage interface
class (MonadIO m) => QueueStorage m where
    -- Entry operations
    storeEntry :: MergeEntry -> m ()
    loadEntry :: EntryId -> m (Maybe MergeEntry)
    deleteEntry :: EntryId -> m ()
    listAllEntries :: Repository -> m [MergeEntry]

    -- Status operations
    updateEntryStatus :: EntryId -> MergeStatus -> m ()
    updateEntryValidation :: EntryId -> [ValidationResult] -> m ()

    -- Query operations
    queryByStatus :: Repository -> MergeStatus -> m [MergeEntry]
    queryByPriority :: Repository -> Priority -> m [MergeEntry]
    queryByTimeRange :: Repository -> UTCTime -> UTCTime -> m [MergeEntry]

-- | PostgreSQL storage implementation
data PostgresStorage = PostgresStorage
    { psConn :: Connection
    }

-- | Initialize PostgreSQL storage
initPostgresStorage :: ConnectInfo -> IO PostgresStorage
initPostgresStorage connInfo = do
    conn <- connect connInfo
    -- Create table if not exists
    execute_ conn createTableSQL
    pure $ PostgresStorage conn
  where
    createTableSQL = "CREATE TABLE IF NOT EXISTS merge_entries (\
        \id TEXT PRIMARY KEY, \
        \repository TEXT NOT NULL, \
        \source TEXT NOT NULL, \
        \target TEXT NOT NULL, \
        \priority TEXT NOT NULL, \
        \status TEXT NOT NULL, \
        \validation JSONB, \
        \dependencies TEXT[], \
        \created TIMESTAMP WITH TIME ZONE NOT NULL, \
        \updated TIMESTAMP WITH TIME ZONE NOT NULL \
        \)"

instance QueueStorage PostgresStorage where
    storeEntry entry = liftIO $ do
        let sql = "INSERT INTO merge_entries \
                 \(id, repository, source, target, priority, status, validation, dependencies, created, updated) \
                 \VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
                 \ON CONFLICT (id) DO UPDATE SET \
                 \repository = EXCLUDED.repository, \
                 \source = EXCLUDED.source, \
                 \target = EXCLUDED.target, \
                 \priority = EXCLUDED.priority, \
                 \status = EXCLUDED.status, \
                 \validation = EXCLUDED.validation, \
                 \dependencies = EXCLUDED.dependencies, \
                 \updated = EXCLUDED.updated"
        void $ execute (psConn storage) sql
            ( unEntryId $ meId entry
            , meRepository entry
            , meSource entry
            , meTarget entry
            , show $ mePriority entry
            , show $ meStatus entry
            , encode $ meValidation entry
            , map unEntryId $ meDependencies entry
            , meCreated entry
            , meUpdated entry
            )

    loadEntry entryId = liftIO $ do
        let sql = "SELECT repository, source, target, priority, status, validation, dependencies, created, updated \
                 \FROM merge_entries WHERE id = ?"
        rows <- query (psConn storage) sql (Only $ unEntryId entryId)
        case rows of
            [(repo, src, tgt, prio, stat, val, deps, created, updated)] ->
                pure $ Just MergeEntry
                    { meId = entryId
                    , meRepository = repo
                    , meSource = src
                    , meTarget = tgt
                    , mePriority = read prio
                    , meStatus = read stat
                    , meValidation = maybe [] id $ decode val
                    , meDependencies = map EntryId deps
                    , meCreated = created
                    , meUpdated = updated
                    }
            _ -> pure Nothing

    deleteEntry entryId = liftIO $ do
        let sql = "DELETE FROM merge_entries WHERE id = ?"
        void $ execute (psConn storage) sql (Only $ unEntryId entryId)

    listAllEntries repo = liftIO $ do
        let sql = "SELECT id, source, target, priority, status, validation, dependencies, created, updated \
                 \FROM merge_entries WHERE repository = ?"
        rows <- query (psConn storage) sql (Only repo)
        pure $ map rowToEntry rows

    updateEntryStatus entryId status = liftIO $ do
        now <- getCurrentTime
        let sql = "UPDATE merge_entries SET status = ?, updated = ? WHERE id = ?"
        void $ execute (psConn storage) sql (show status, now, unEntryId entryId)

    updateEntryValidation entryId results = liftIO $ do
        now <- getCurrentTime
        let sql = "UPDATE merge_entries SET validation = ?, updated = ? WHERE id = ?"
        void $ execute (psConn storage) sql (encode results, now, unEntryId entryId)

    queryByStatus repo status = liftIO $ do
        let sql = "SELECT id, source, target, priority, status, validation, dependencies, created, updated \
                 \FROM merge_entries WHERE repository = ? AND status = ?"
        rows <- query (psConn storage) sql (repo, show status)
        pure $ map rowToEntry rows

    queryByPriority repo priority = liftIO $ do
        let sql = "SELECT id, source, target, priority, status, validation, dependencies, created, updated \
                 \FROM merge_entries WHERE repository = ? AND priority = ?"
        rows <- query (psConn storage) sql (repo, show priority)
        pure $ map rowToEntry rows

    queryByTimeRange repo start end = liftIO $ do
        let sql = "SELECT id, source, target, priority, status, validation, dependencies, created, updated \
                 \FROM merge_entries WHERE repository = ? AND created BETWEEN ? AND ?"
        rows <- query (psConn storage) sql (repo, start, end)
        pure $ map rowToEntry rows

-- | In-memory storage implementation
data MemoryStorage = MemoryStorage
    { msEntries :: TVar (Map EntryId MergeEntry)
    }

-- | Initialize in-memory storage
initMemoryStorage :: IO MemoryStorage
initMemoryStorage = MemoryStorage <$> newTVarIO Map.empty

instance QueueStorage MemoryStorage where
    storeEntry entry = liftIO $ atomically $
        modifyTVar' (msEntries storage) $ Map.insert (meId entry) entry

    loadEntry entryId = liftIO $ atomically $
        Map.lookup entryId <$> readTVar (msEntries storage)

    deleteEntry entryId = liftIO $ atomically $
        modifyTVar' (msEntries storage) $ Map.delete entryId

    listAllEntries repo = liftIO $ atomically $ do
        entries <- readTVar (msEntries storage)
        pure $ filter ((== repo) . meRepository) $ Map.elems entries

    updateEntryStatus entryId status = liftIO $ do
        now <- getCurrentTime
        atomically $ modifyTVar' (msEntries storage) $ Map.adjust
            (\e -> e { meStatus = status, meUpdated = now })
            entryId

    updateEntryValidation entryId results = liftIO $ do
        now <- getCurrentTime
        atomically $ modifyTVar' (msEntries storage) $ Map.adjust
            (\e -> e { meValidation = results, meUpdated = now })
            entryId

    queryByStatus repo status = liftIO $ atomically $ do
        entries <- readTVar (msEntries storage)
        pure $ filter (\e -> meRepository e == repo && meStatus e == status)
             $ Map.elems entries

    queryByPriority repo priority = liftIO $ atomically $ do
        entries <- readTVar (msEntries storage)
        pure $ filter (\e -> meRepository e == repo && mePriority e == priority)
             $ Map.elems entries

    queryByTimeRange repo start end = liftIO $ atomically $ do
        entries <- readTVar (msEntries storage)
        pure $ filter (\e -> meRepository e == repo &&
                            meCreated e >= start &&
                            meCreated e <= end)
             $ Map.elems entries

-- Helper functions

-- | Convert database row to MergeEntry
rowToEntry :: (Text, Text, Text, Text, Text, Value, [Text], UTCTime, UTCTime) -> MergeEntry
rowToEntry (id, src, tgt, prio, stat, val, deps, created, updated) =
    MergeEntry
        { meId = EntryId id
        , meRepository = repo
        , meSource = src
        , meTarget = tgt
        , mePriority = read prio
        , meStatus = read stat
        , meValidation = maybe [] id $ decode val
        , meDependencies = map EntryId deps
        , meCreated = created
        , meUpdated = updated
        }

-- | Format a reference for storage
formatRef :: Reference -> Text
formatRef ref = case ref of
    Branch name -> "branch:" <> name
    Tag name -> "tag:" <> name
    Commit (CommitId hash) -> "commit:" <> hash
    WorkingCopy -> "working"

-- | Parse a reference from storage
parseRef :: Text -> Reference
parseRef text = case T.splitOn ":" text of
    ["branch", name] -> Branch name
    ["tag", name] -> Tag name
    ["commit", hash] -> Commit $ CommitId hash
    ["working"] -> WorkingCopy
    _ -> error $ "Invalid reference format: " <> T.unpack text

-- | Default VCS configuration
defaultVCSConfig :: VCSConfig
defaultVCSConfig = VCSConfig
    { vcUser = "system"
    , vcEmail = "system@gerrit"
    , vcSigningKey = Nothing
    , vcRemotes = Map.empty
    , vcHooks = []
    , vcIgnorePatterns = []
    }

-- | Default repository metrics
defaultRepoMetrics :: RepositoryMetrics
defaultRepoMetrics = RepositoryMetrics
    { rmCommitCount = 0
    , rmBranchCount = 0
    , rmContributorCount = 0
    , rmLastActivity = UTCTime (ModifiedJulianDay 0) 0
    , rmStorageSize = 0
    }
