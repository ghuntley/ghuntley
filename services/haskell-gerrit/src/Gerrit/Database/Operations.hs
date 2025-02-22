{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE FlexibleContexts #-}

{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

module Gerrit.Database.Operations
    ( -- * Transaction Management
      withTransaction
    , transactionalSave
      -- * Query Operations
    , runQuery
    , runQueryCount
    , runQueryExists
    , runQueryOne
    , runQueryMaybe
      -- * Insert Operations
    , insertRecord
    , insertRecords
    , insertOrUpdate
      -- * Update Operations
    , updateRecord
    , updateWhere
    , updateWhereCount
      -- * Delete Operations
    , deleteRecord
    , deleteWhere
    , deleteWhereCount
      -- * Pagination
    , PaginationParams(..)
    , paginate
    , paginateWhere
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader)
import Data.Int (Int64)
import Data.Text (Text)
import Database.Persist
import Database.Persist.Sql
import qualified Database.Esqueleto.Legacy as E

import Gerrit.Models.Change
import Gerrit.Models.Revision
import Gerrit.Models.Comment
import Gerrit.Models.Vote
import Gerrit.Api.Metrics (Metrics(..), incrementDatabaseQueries, observeDatabaseQueryDuration, incrementDatabaseErrors)

-- | Pagination parameters
data PaginationParams = PaginationParams
    { pageSize :: Int
    , pageNumber :: Int
    , sortField :: Text
    , sortDirection :: Text
    } deriving (Show, Eq)

-- | Run a database query with pagination
paginate :: (MonadIO m, PersistEntity record)
        => PaginationParams
        -> [Filter record]
        -> [SelectOpt record]
        -> SqlPersistT m [Entity record]
paginate PaginationParams{..} filters opts = do
    let offset = (pageNumber - 1) * pageSize
    let direction = if sortDirection == "desc" then Desc else Asc
    let sorting = [direction sortField]
    selectList filters (sorting ++ [LimitTo pageSize, OffsetBy offset] ++ opts)

-- | Run a database query with pagination and where clause
paginateWhere :: (MonadIO m, PersistEntity record)
              => PaginationParams
              -> [Filter record]
              -> [SelectOpt record]
              -> SqlPersistT m ([Entity record], Int64)
paginateWhere params filters opts = do
    records <- paginate params filters opts
    count <- count filters
    return (records, count)

-- | Run a database query
runQuery :: (MonadIO m, PersistEntity record)
         => [Filter record]
         -> [SelectOpt record]
         -> SqlPersistT m [Entity record]
runQuery = selectList

-- | Run a database query and return count
runQueryCount :: (MonadIO m, PersistEntity record)
              => [Filter record]
              -> SqlPersistT m Int
runQueryCount = count

-- | Run a database query and check existence
runQueryExists :: (MonadIO m, PersistEntity record)
               => [Filter record]
               -> SqlPersistT m Bool
runQueryExists = exists

-- | Run a database query and return single result
runQueryOne :: (MonadIO m, PersistEntity record)
            => [Filter record]
            -> SqlPersistT m (Maybe (Entity record))
runQueryOne = selectFirst

-- | Run a database query and return maybe result
runQueryMaybe :: (MonadIO m, PersistEntity record)
              => [Filter record]
              -> SqlPersistT m (Maybe (Entity record))
runQueryMaybe = getBy

-- | Insert a single record
insertRecord :: (MonadIO m, PersistEntityBackend record ~ SqlBackend, PersistEntity record)
             => record
             -> SqlPersistT m (Key record)
insertRecord = insert

-- | Insert multiple records
insertRecords :: (MonadIO m, PersistEntityBackend record ~ SqlBackend, PersistEntity record)
              => [record]
              -> SqlPersistT m [Key record]
insertRecords = insertMany

-- | Insert or update a record
insertOrUpdate :: (MonadIO m, PersistEntityBackend record ~ SqlBackend, PersistEntity record)
               => record
               -> [Update record]
               -> SqlPersistT m (Key record)
insertOrUpdate record updates = do
    existing <- getBy $ toUnique record
    case existing of
        Just (Entity key _) -> do
            update key updates
            return key
        Nothing -> insert record

-- | Update a single record
updateRecord :: (MonadIO m, PersistEntityBackend record ~ SqlBackend, PersistEntity record)
             => Key record
             -> [Update record]
             -> SqlPersistT m ()
updateRecord = update

-- | Update records matching a filter
updateWhere :: (MonadIO m, PersistEntityBackend record ~ SqlBackend, PersistEntity record)
            => [Filter record]
            -> [Update record]
            -> SqlPersistT m ()
updateWhere = updateWhere_

-- | Update records matching a filter and return count
updateWhereCount :: (MonadIO m, PersistEntityBackend record ~ SqlBackend, PersistEntity record)
                 => [Filter record]
                 -> [Update record]
                 -> SqlPersistT m Int64
updateWhereCount filters updates = do
    updateWhere filters updates
    count filters

-- | Delete a single record
deleteRecord :: (MonadIO m, PersistEntityBackend record ~ SqlBackend, PersistEntity record)
             => Key record
             -> SqlPersistT m ()
deleteRecord = delete

-- | Delete records matching a filter
deleteWhere :: (MonadIO m, PersistEntityBackend record ~ SqlBackend, PersistEntity record)
            => [Filter record]
            -> SqlPersistT m ()
deleteWhere = deleteWhere_

-- | Delete records matching a filter and return count
deleteWhereCount :: (MonadIO m, PersistEntityBackend record ~ SqlBackend, PersistEntity record)
                 => [Filter record]
                 -> SqlPersistT m Int64
deleteWhereCount filters = do
    count <- count filters
    deleteWhere filters
    return count

-- | Run a database action in a transaction
withTransaction :: (MonadIO m)
                => SqlPersistT m a
                -> SqlPersistT m a
withTransaction = transactionSave

-- | Run a database action in a transaction with savepoints
transactionalSave :: (MonadIO m)
                  => SqlPersistT m a
                  -> SqlPersistT m a
transactionalSave action = do
    result <- transactionSaveWithIsolation
        Serializable  -- Use serializable isolation for safety
        action
    case result of
        Left err -> liftIO $ fail $ show err
        Right value -> return value

-- | Database operations for changes
class ChangeDB m where
    insertChange :: Metrics -> Change -> m ()
    getChange :: Metrics -> Text -> m (Maybe Change)
    updateChange :: Metrics -> Change -> m ()
    listChanges :: Metrics -> Int -> Int -> m [Change]
    getChangesByOwner :: Metrics -> Text -> m [Change]
    getChangesByProject :: Metrics -> Text -> m [Change]

-- | Database operations for revisions
class RevisionDB m where
    insertRevision :: Metrics -> Revision -> m ()
    getRevision :: Metrics -> Text -> m (Maybe Revision)
    getChangeRevisions :: Metrics -> Text -> m [Revision]
    getLatestRevision :: Metrics -> Text -> m (Maybe Revision)

-- | Database operations for comments
class CommentDB m where
    insertComment :: Metrics -> Comment -> m ()
    getComment :: Metrics -> Text -> m (Maybe Comment)
    updateComment :: Metrics -> Comment -> m ()
    getCommentsForRevision :: Metrics -> Text -> m [Comment]
    getCommentsForFile :: Metrics -> Text -> Text -> m [Comment]
    getRepliesForComment :: Metrics -> Text -> m [Comment]

-- | Database operations for votes
class VoteDB m where
    insertVote :: Metrics -> Vote -> m ()
    getVote :: Metrics -> Text -> m (Maybe Vote)
    updateVote :: Metrics -> Vote -> m ()
    getVotesForRevision :: Metrics -> Text -> m [Vote]
    getVotesByReviewer :: Metrics -> Text -> Text -> m [Vote]
    getVotesByLabel :: Metrics -> Text -> VoteLabel -> m [Vote]

-- | Database operations for alerts
class AlertDB m where
    insertAlert :: Alert -> m ()
    getAlert :: Text -> m (Maybe Alert)
    updateAlert :: Alert -> m ()
    getActiveAlerts :: m [Alert]
    getAlertsBySeverity :: AlertSeverity -> m [Alert]
    getAlertsBySource :: Text -> m [Alert]
    insertAlertRule :: AlertRule -> m ()
    getAlertRule :: Text -> m (Maybe AlertRule)
    updateAlertRule :: AlertRule -> m ()
    getEnabledAlertRules :: m [AlertRule]
    getAlertRulesByName :: Text -> m [AlertRule]

-- | SQLite implementation of database operations
newtype SQLiteM a = SQLiteM { runSQLiteM :: Connection -> IO a }

-- | Helper function to track database operation metrics
withMetrics :: Metrics -> String -> SQLiteM a -> SQLiteM a
withMetrics metrics operation action = SQLiteM $ \conn -> do
    startTime <- getCurrentTime
    incrementDatabaseQueries metrics
    result <- try $ runSQLiteM action conn
    endTime <- getCurrentTime
    let duration = realToFrac $ diffUTCTime endTime startTime * 1000  -- Convert to milliseconds
    observeDatabaseQueryDuration metrics duration
    case result of
        Left e -> do
            incrementDatabaseErrors metrics
            error $ "Database error in " ++ operation ++ ": " ++ show (e :: SQLError)
        Right value -> return value

instance ChangeDB SQLiteM where
    insertChange metrics change = withMetrics metrics "insertChange" $ SQLiteM $ \conn ->
        execute conn
            "INSERT INTO changes (id, project_id, branch, subject, description, owner_id, status, created, updated) \
            \VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
            change

    getChange metrics changeId = withMetrics metrics "getChange" $ SQLiteM $ \conn -> do
        results <- query conn
            "SELECT * FROM changes WHERE id = ?"
            (Only changeId)
        case results of
            [change] -> pure $ Just change
            _ -> pure Nothing

    updateChange metrics change = withMetrics metrics "updateChange" $ SQLiteM $ \conn ->
        execute conn
            "UPDATE changes SET status = ?, updated = ? WHERE id = ?"
            (status change, updated change, changeId change)

    listChanges metrics offset limit = withMetrics metrics "listChanges" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM changes ORDER BY created DESC LIMIT ? OFFSET ?"
            (limit, offset)

    getChangesByOwner metrics ownerId = withMetrics metrics "getChangesByOwner" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM changes WHERE owner_id = ? ORDER BY created DESC"
            (Only ownerId)

    getChangesByProject metrics projectId = withMetrics metrics "getChangesByProject" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM changes WHERE project_id = ? ORDER BY created DESC"
            (Only projectId)

instance RevisionDB SQLiteM where
    insertRevision metrics revision = withMetrics metrics "insertRevision" $ SQLiteM $ \conn ->
        execute conn
            "INSERT INTO revisions (id, change_id, number, commit_id, uploader_id, description, created) \
            \VALUES (?, ?, ?, ?, ?, ?, ?)"
            revision

    getRevision metrics revisionId = withMetrics metrics "getRevision" $ SQLiteM $ \conn -> do
        results <- query conn
            "SELECT * FROM revisions WHERE id = ?"
            (Only revisionId)
        case results of
            [revision] -> pure $ Just revision
            _ -> pure Nothing

    getChangeRevisions metrics changeId = withMetrics metrics "getChangeRevisions" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM revisions WHERE change_id = ? ORDER BY number ASC"
            (Only changeId)

    getLatestRevision metrics changeId = withMetrics metrics "getLatestRevision" $ SQLiteM $ \conn -> do
        results <- query conn
            "SELECT * FROM revisions WHERE change_id = ? ORDER BY number DESC LIMIT 1"
            (Only changeId)
        case results of
            [revision] -> pure $ Just revision
            _ -> pure Nothing

instance CommentDB SQLiteM where
    insertComment metrics comment = withMetrics metrics "insertComment" $ SQLiteM $ \conn ->
        execute conn
            "INSERT INTO comments (id, revision_id, author_id, comment_type, file, line, message, resolved, created, updated) \
            \VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            comment

    getComment metrics commentId = withMetrics metrics "getComment" $ SQLiteM $ \conn -> do
        results <- query conn
            "SELECT * FROM comments WHERE id = ?"
            (Only commentId)
        case results of
            [comment] -> pure $ Just comment
            _ -> pure Nothing

    updateComment metrics comment = withMetrics metrics "updateComment" $ SQLiteM $ \conn ->
        execute conn
            "UPDATE comments SET resolved = ?, updated = ? WHERE id = ?"
            (resolved comment, updated comment, commentId comment)

    getCommentsForRevision metrics revisionId = withMetrics metrics "getCommentsForRevision" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM comments WHERE revision_id = ? ORDER BY created ASC"
            (Only revisionId)

    getCommentsForFile metrics revisionId file = withMetrics metrics "getCommentsForFile" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM comments WHERE revision_id = ? AND file = ? ORDER BY line ASC, created ASC"
            (revisionId, file)

    getRepliesForComment metrics parentId = withMetrics metrics "getRepliesForComment" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM comments WHERE comment_type = ? ORDER BY created ASC"
            (Only parentId)

instance VoteDB SQLiteM where
    insertVote metrics vote = withMetrics metrics "insertVote" $ SQLiteM $ \conn ->
        execute conn
            "INSERT INTO votes (id, revision_id, reviewer_id, label, value, message, created, updated) \
            \VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            vote

    getVote metrics voteId = withMetrics metrics "getVote" $ SQLiteM $ \conn -> do
        results <- query conn
            "SELECT * FROM votes WHERE id = ?"
            (Only voteId)
        case results of
            [vote] -> pure $ Just vote
            _ -> pure Nothing

    updateVote metrics vote = withMetrics metrics "updateVote" $ SQLiteM $ \conn ->
        execute conn
            "UPDATE votes SET value = ?, message = ?, updated = ? WHERE id = ?"
            (value vote, message vote, updated vote, voteId vote)

    getVotesForRevision metrics revisionId = withMetrics metrics "getVotesForRevision" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM votes WHERE revision_id = ? ORDER BY created ASC"
            (Only revisionId)

    getVotesByReviewer metrics revisionId reviewerId = withMetrics metrics "getVotesByReviewer" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM votes WHERE revision_id = ? AND reviewer_id = ? ORDER BY created ASC"
            (revisionId, reviewerId)

    getVotesByLabel metrics revisionId label = withMetrics metrics "getVotesByLabel" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM votes WHERE revision_id = ? AND label = ? ORDER BY created ASC"
            (revisionId, label)

instance AlertDB SQLiteM where
    insertAlert alert = withMetrics metrics "insertAlert" $ SQLiteM $ \conn ->
        execute conn
            "INSERT INTO alerts (id, title, message, severity, status, source, timestamp, acknowledged_by, acknowledged_at, metadata, created, updated) \
            \VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            alert

    getAlert alertId' = withMetrics metrics "getAlert" $ SQLiteM $ \conn -> do
        results <- query conn
            "SELECT * FROM alerts WHERE id = ?"
            (Only alertId')
        case results of
            [alert] -> pure $ Just alert
            _ -> pure Nothing

    updateAlert alert = withMetrics metrics "updateAlert" $ SQLiteM $ \conn ->
        execute conn
            "UPDATE alerts SET status = ?, acknowledged_by = ?, acknowledged_at = ?, updated = ? WHERE id = ?"
            (alertStatus alert, alertAcknowledgedBy alert, alertAcknowledgedAt alert, alertUpdated alert, alertId alert)

    getActiveAlerts = withMetrics metrics "getActiveAlerts" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM alerts WHERE status = ? ORDER BY timestamp DESC"
            (Only Active)

    getAlertsBySeverity severity = withMetrics metrics "getAlertsBySeverity" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM alerts WHERE severity = ? ORDER BY timestamp DESC"
            (Only severity)

    getAlertsBySource source = withMetrics metrics "getAlertsBySource" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM alerts WHERE source = ? ORDER BY timestamp DESC"
            (Only source)

    insertAlertRule rule = withMetrics metrics "insertAlertRule" $ SQLiteM $ \conn ->
        execute conn
            "INSERT INTO alert_rules (id, name, description, enabled, thresholds, metadata, created, updated) \
            \VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            rule

    getAlertRule ruleId' = withMetrics metrics "getAlertRule" $ SQLiteM $ \conn -> do
        results <- query conn
            "SELECT * FROM alert_rules WHERE id = ?"
            (Only ruleId')
        case results of
            [rule] -> pure $ Just rule
            _ -> pure Nothing

    updateAlertRule rule = withMetrics metrics "updateAlertRule" $ SQLiteM $ \conn ->
        execute conn
            "UPDATE alert_rules SET name = ?, description = ?, enabled = ?, thresholds = ?, metadata = ?, updated = ? WHERE id = ?"
            (ruleName rule, ruleDescription rule, ruleEnabled rule, ruleThresholds rule, ruleMetadata rule, ruleUpdated rule, ruleId rule)

    getEnabledAlertRules = withMetrics metrics "getEnabledAlertRules" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM alert_rules WHERE enabled = ? ORDER BY name ASC"
            (Only True)

    getAlertRulesByName name = withMetrics metrics "getAlertRulesByName" $ SQLiteM $ \conn ->
        query conn
            "SELECT * FROM alert_rules WHERE name LIKE ? ORDER BY name ASC"
            (Only $ "%" <> name <> "%")

-- | Run a database operation
runDB :: FilePath -> SQLiteM a -> IO a
runDB dbPath action =
    bracket (open dbPath) close $ \conn -> do
        runSQLiteM action conn

-- | Initialize the database schema
initializeSchema :: FilePath -> IO ()
initializeSchema dbPath = runDB dbPath $ SQLiteM $ \conn -> do
    -- Create changes table
    void $ execute_ conn
        "CREATE TABLE IF NOT EXISTS changes (\
        \id TEXT PRIMARY KEY, \
        \project_id TEXT NOT NULL, \
        \branch TEXT NOT NULL, \
        \subject TEXT NOT NULL, \
        \description TEXT, \
        \owner_id TEXT NOT NULL, \
        \status TEXT NOT NULL, \
        \created TIMESTAMP NOT NULL, \
        \updated TIMESTAMP NOT NULL)"

    -- Create revisions table
    void $ execute_ conn
        "CREATE TABLE IF NOT EXISTS revisions (\
        \id TEXT PRIMARY KEY, \
        \change_id TEXT NOT NULL REFERENCES changes(id) ON DELETE CASCADE, \
        \number INTEGER NOT NULL, \
        \commit_id TEXT NOT NULL, \
        \uploader_id TEXT NOT NULL, \
        \description TEXT, \
        \created TIMESTAMP NOT NULL, \
        \UNIQUE (change_id, number))"

    -- Create comments table
    void $ execute_ conn
        "CREATE TABLE IF NOT EXISTS comments (\
        \id TEXT PRIMARY KEY, \
        \revision_id TEXT NOT NULL REFERENCES revisions(id) ON DELETE CASCADE, \
        \author_id TEXT NOT NULL, \
        \comment_type TEXT NOT NULL, \
        \file TEXT, \
        \line INTEGER, \
        \message TEXT NOT NULL, \
        \resolved BOOLEAN NOT NULL DEFAULT 0, \
        \created TIMESTAMP NOT NULL, \
        \updated TIMESTAMP NOT NULL)"

    -- Create votes table
    void $ execute_ conn
        "CREATE TABLE IF NOT EXISTS votes (\
        \id TEXT PRIMARY KEY, \
        \revision_id TEXT NOT NULL REFERENCES revisions(id) ON DELETE CASCADE, \
        \reviewer_id TEXT NOT NULL, \
        \label TEXT NOT NULL, \
        \value INTEGER NOT NULL, \
        \message TEXT, \
        \created TIMESTAMP NOT NULL, \
        \updated TIMESTAMP NOT NULL, \
        \UNIQUE (revision_id, reviewer_id, label))"

    -- Create alerts table
    void $ execute_ conn
        "CREATE TABLE IF NOT EXISTS alerts (\
        \id TEXT PRIMARY KEY, \
        \title TEXT NOT NULL, \
        \message TEXT NOT NULL, \
        \severity TEXT NOT NULL, \
        \status TEXT NOT NULL, \
        \source TEXT NOT NULL, \
        \timestamp TIMESTAMP NOT NULL, \
        \acknowledged_by TEXT, \
        \acknowledged_at TIMESTAMP, \
        \metadata JSON, \
        \created TIMESTAMP NOT NULL, \
        \updated TIMESTAMP NOT NULL)"

    -- Create alert rules table
    void $ execute_ conn
        "CREATE TABLE IF NOT EXISTS alert_rules (\
        \id TEXT PRIMARY KEY, \
        \name TEXT NOT NULL, \
        \description TEXT NOT NULL, \
        \enabled BOOLEAN NOT NULL DEFAULT 1, \
        \thresholds JSON NOT NULL, \
        \metadata JSON, \
        \created TIMESTAMP NOT NULL, \
        \updated TIMESTAMP NOT NULL)"

    -- Create indexes for changes
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_changes_project ON changes(project_id)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_changes_owner ON changes(owner_id)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_changes_status ON changes(status)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_changes_created ON changes(created)"

    -- Create indexes for revisions
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_revisions_change ON revisions(change_id)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_revisions_uploader ON revisions(uploader_id)"

    -- Create indexes for comments
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_comments_revision ON comments(revision_id)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_comments_author ON comments(author_id)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_comments_file ON comments(file)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_comments_type ON comments(comment_type)"

    -- Create indexes for votes
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_votes_revision ON votes(revision_id)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_votes_reviewer ON votes(reviewer_id)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_votes_label ON votes(label)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_votes_value ON votes(value)"

    -- Create indexes for alerts
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_alerts_severity ON alerts(severity)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_alerts_status ON alerts(status)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_alerts_source ON alerts(source)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_alerts_timestamp ON alerts(timestamp)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_alerts_acknowledged ON alerts(acknowledged_by, acknowledged_at)"

    -- Create indexes for alert rules
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_alert_rules_name ON alert_rules(name)"
    void $ execute_ conn "CREATE INDEX IF NOT EXISTS idx_alert_rules_enabled ON alert_rules(enabled)"
