-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.VCS.Types
    ( VCS(..)
    , Repository(..)
    , RepositoryMetrics(..)
    , VCSType(..)
    , Reference(..)
    , VCSConfig(..)
    , Hook(..)
    , HookEvent(..)
    , VCSException(..)
    , Remote(..)
    , Branch(..)
    , CommitId(..)
    , LogOptions(..)
    , Diff(..)
    , BlameInfo(..)
    , RepoStatus(..)
    , Commit(..)
    , DiffHunk(..)
    , DiffLine(..)
    , CommitRange(..)
    , RevisionSet(..)
    , ConflictResolution(..)
    , MergeEntry(..)
    , MergeStatus(..)
    , MergeFailure(..)
    , QueueConfig(..)
    , MergeStrategy(..)
    , ValidationCheck(..)
    , ValidationStatus(..)
    , MergeQueue(..)
    , EntryId
    , Priority(..)
    , ValidationResult(..)
    , MergeResult(..)
    , QueueMetrics(..)
    , ProcessorConfig
    , QueueProcessor
    , QueueStorage
    , NotificationSystem
    , WebhookSystem
    , NotificationConfig
    , WebhookConfig
    , QueueItemStatus
    , QueueItem
    , QueueStatus
    , Extension
    , BookmarkConfig
    , MQConfig
    ) where

import Control.Exception (Exception)
import Control.Monad.IO.Class (MonadIO)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import GHC.Generics (Generic)
import Control.Monad.IO.Class (throwIO)

import Gerrit.Models.AuditLog (AuditLoggerConfig)

-- | Core VCS operations typeclass
class (MonadIO m) => VCS v m where
    -- Core operations
    clone :: v -> Text -> FilePath -> m Repository
    checkout :: v -> Repository -> Reference -> m ()
    commit :: v -> Repository -> Text -> [FilePath] -> m CommitId
    push :: v -> Repository -> Remote -> Branch -> m ()
    pull :: v -> Repository -> Remote -> Branch -> m ()

    -- Branch operations
    createBranch :: v -> Repository -> Text -> m Branch
    deleteBranch :: v -> Repository -> Text -> m ()
    listBranches :: v -> Repository -> m [Branch]

    -- History and diff operations
    log :: v -> Repository -> LogOptions -> m [Commit]
    diff :: v -> Repository -> Reference -> Reference -> m [Diff]
    blame :: v -> Repository -> FilePath -> m BlameInfo

    -- Repository status
    status :: v -> Repository -> m RepoStatus
    isClean :: v -> Repository -> m Bool

    -- Additional operations
    merge :: v -> Repository -> Reference -> m ()
    revert :: v -> Repository -> CommitId -> m ()
    cherryPick :: v -> Repository -> CommitId -> m CommitId
    fetch :: v -> Repository -> Remote -> m ()
    tag :: v -> Repository -> Text -> Maybe Text -> m ()
    listTags :: v -> Repository -> m [Text]

    -- Default implementations
    merge _ _ _ = throwIO $ VCSException "Merge operation not supported"
    revert _ _ _ = throwIO $ VCSException "Revert operation not supported"
    cherryPick _ _ _ = throwIO $ VCSException "Cherry-pick operation not supported"
    fetch v repo remote = pull v repo remote (Branch "HEAD")
    tag _ _ _ _ = throwIO $ VCSException "Tag operation not supported"
    listTags _ _ = pure []

-- | Repository representation
data Repository = Repository
    { repoPath :: FilePath
    , repoType :: VCSType
    , repoConfig :: VCSConfig
    , repoMetrics :: RepositoryMetrics
    } deriving (Show, Eq, Generic)

-- | Repository metrics
data RepositoryMetrics = RepositoryMetrics
    { rmCommitCount :: Int
    , rmBranchCount :: Int
    , rmContributorCount :: Int
    , rmLastActivity :: UTCTime
    , rmStorageSize :: Integer  -- in bytes
    } deriving (Show, Eq, Generic)

-- | Supported VCS types
data VCSType = Git | Mercurial | JJ
    deriving (Show, Eq, Generic)

-- | Reference types
data Reference
    = Branch Text
    | Tag Text
    | Commit CommitId
    | WorkingCopy
    deriving (Show, Eq, Generic)

-- | Common VCS configuration
data VCSConfig = VCSConfig
    { vcUser :: Text
    , vcEmail :: Text
    , vcSigningKey :: Maybe Text
    , vcRemotes :: Map Text Remote
    , vcHooks :: [Hook]
    , vcIgnorePatterns :: [Text]
    } deriving (Show, Eq, Generic)

-- | Repository hooks
data Hook = Hook
    { hookName :: Text
    , hookScript :: FilePath
    , hookEvent :: HookEvent
    , hookEnabled :: Bool
    } deriving (Show, Eq, Generic)

-- | Hook event types
data HookEvent
    = PreCommit
    | PostCommit
    | PrePush
    | PostPush
    | PreRebase
    deriving (Show, Eq, Generic)

-- | Remote repository
data Remote = Remote
    { remoteName :: Text
    , remoteUrl :: Text
    , remoteFetch :: Text
    , remotePush :: Text
    } deriving (Show, Eq, Generic)

-- | Branch information
data Branch = Branch
    { branchName :: Text
    , branchCommit :: CommitId
    , branchUpstream :: Maybe Text
    } deriving (Show, Eq, Generic)

-- | Commit identifier
newtype CommitId = CommitId { unCommitId :: Text }
    deriving (Show, Eq, Generic)

-- | Log options
data LogOptions = LogOptions
    { loMaxCount :: Maybe Int
    , loSkip :: Maybe Int
    , loPath :: Maybe FilePath
    , loAuthor :: Maybe Text
    , loSince :: Maybe UTCTime
    , loUntil :: Maybe UTCTime
    } deriving (Show, Eq, Generic)

-- | Diff information
data Diff = Diff
    { diffOldFile :: FilePath
    , diffNewFile :: FilePath
    , diffHunks :: [DiffHunk]
    } deriving (Show, Eq, Generic)

-- | Blame information
data BlameInfo = BlameInfo
    { blameCommit :: CommitId
    , blameAuthor :: Text
    , blameDate :: UTCTime
    , blameLine :: Int
    , blameContent :: Text
    } deriving (Show, Eq, Generic)

-- | Repository status
data RepoStatus = RepoStatus
    { rsModified :: [FilePath]
    , rsAdded :: [FilePath]
    , rsDeleted :: [FilePath]
    , rsUntracked :: [FilePath]
    , rsConflicted :: [FilePath]
    } deriving (Show, Eq, Generic)

-- | VCS-specific exceptions
data VCSException
    = VCSException Text
    | InvalidReference Text
    | RepositoryNotFound FilePath
    | BranchExists Text
    | MergeConflict [FilePath]
    | HookFailed Text
    | AuthenticationError Text
    | PermissionDenied Text
    deriving (Show, Eq, Generic)

instance Exception VCSException

-- | Commit information
data Commit = Commit
    { commitId :: CommitId
    , commitAuthor :: Text
    , commitEmail :: Text
    , commitDate :: UTCTime
    , commitMessage :: Text
    , commitParents :: [CommitId]
    , commitFiles :: [FilePath]
    } deriving (Show, Eq, Generic)

-- | Diff hunk information
data DiffHunk = DiffHunk
    { dhOldStart :: Int
    , dhOldCount :: Int
    , dhNewStart :: Int
    , dhNewCount :: Int
    , dhLines :: [DiffLine]
    } deriving (Show, Eq, Generic)

-- | Diff line types
data DiffLine
    = DiffContext Text
    | DiffAdded Text
    | DiffRemoved Text
    | DiffModified Text Text  -- old and new content
    deriving (Show, Eq, Generic)

-- | Commit range for operations like rebase and squash
data CommitRange = CommitRange
    { crFrom :: CommitId
    , crTo :: CommitId
    , crInclusive :: Bool
    } deriving (Show, Eq, Generic)

-- | Revision set for Mercurial operations
data RevisionSet
    = RevisionSingle CommitId
    | RevisionRange CommitId CommitId
    | RevisionBranch Text
    | RevisionBookmark Text
    | RevisionTag Text
    | RevisionSpecial Text  -- For special revsets like "tip", "null", etc.
    deriving (Show, Eq, Generic)

-- | Conflict resolution type
data ConflictResolution
    = ResolveAcceptMine
    | ResolveAcceptTheirs
    | ResolveMerge
    | ResolveInteractive
    deriving (Show, Eq, Generic)

-- | Merge queue entry identifier
newtype EntryId = EntryId { unEntryId :: Text }
    deriving (Show, Eq, Generic)

-- | Priority levels for merge queue entries
data Priority = Low | Normal | High | Critical
    deriving (Show, Eq, Ord, Generic)

-- | Merge queue entry
data MergeEntry = MergeEntry
    { meId :: EntryId
    , meRepository :: Repository
    , meSource :: Reference
    , meTarget :: Reference
    , mePriority :: Priority
    , meStatus :: MergeStatus
    , meValidation :: [ValidationCheck]
    , meDependencies :: [EntryId]
    , meCreated :: UTCTime
    , meUpdated :: UTCTime
    } deriving (Show, Eq, Generic)

-- | Merge entry status
data MergeStatus
    = Queued
    | Validating
    | Merging
    | Succeeded
    | Failed MergeFailure
    | Cancelled
    deriving (Show, Eq, Generic)

-- | Merge failure reasons
data MergeFailure
    = ValidationFailed Text
    | ConflictDetected [FilePath]
    | BuildFailed Text
    | TestsFailed Text
    | TimeoutExceeded
    | ResourceExhausted
    | SystemError Text
    deriving (Show, Eq, Generic)

-- | Queue configuration
data QueueConfig = QueueConfig
    { qcMaxConcurrent :: Int
    , qcBatchSize :: Int
    , qcRetryLimit :: Int
    , qcTimeout :: NominalDiffTime
    , qcValidations :: [ValidationConfig]
    , qcMergeStrategy :: MergeStrategy
    , qcNotifications :: NotificationConfig
    } deriving (Show, Eq, Generic)

-- | Merge strategy
data MergeStrategy
    = FastForward
    | CreateMergeCommit
    | Rebase
    | Squash
    deriving (Show, Eq, Generic)

-- | Validation check status
data ValidationCheck = ValidationCheck
    { vcName :: Text
    , vcStatus :: ValidationStatus
    , vcOutput :: Text
    , vcStarted :: UTCTime
    , vcCompleted :: Maybe UTCTime
    } deriving (Show, Eq, Generic)

-- | Validation status
data ValidationStatus
    = Pending
    | Running
    | Passed
    | Failed
    deriving (Show, Eq, Generic)

-- | Validation configuration
data ValidationConfig = ValidationConfig
    { valName :: Text
    , valCommand :: Text
    , valTimeout :: NominalDiffTime
    , valRequired :: Bool
    } deriving (Show, Eq, Generic)

-- | Notification configuration
data NotificationConfig = NotificationConfig
    { notifySuccess :: Bool
    , notifyFailure :: Bool
    , notifyTimeout :: Bool
    , notifyChannels :: [NotificationChannel]
    } deriving (Show, Eq, Generic)

-- | Notification channel
data NotificationChannel
    = Email Text
    | Webhook Text
    | Slack Text
    deriving (Show, Eq, Generic)

-- | Validation result
data ValidationResult
    = ValidationSuccess
    | ValidationFailure Text
    deriving (Show, Eq, Generic)

-- | Merge result
data MergeResult
    = MergeSuccess
    | MergeFailure MergeFailure
    deriving (Show, Eq, Generic)

-- | Queue metrics
data QueueMetrics = QueueMetrics
    { qmTotalEntries :: Int
    , qmSuccessRate :: Double
    , qmAverageWaitTime :: NominalDiffTime
    , qmAverageProcessTime :: NominalDiffTime
    , qmFailureRates :: Map MergeFailure Int
    , qmConcurrentMerges :: Int
    } deriving (Show, Eq, Generic)

-- | Merge queue typeclass
class (MonadIO m) => MergeQueue m where
    -- Queue operations
    enqueue :: Repository -> Reference -> Reference -> m EntryId
    dequeue :: EntryId -> m ()
    getEntry :: EntryId -> m (Maybe MergeEntry)
    listEntries :: Repository -> m [MergeEntry]

    -- Status management
    updateStatus :: EntryId -> MergeStatus -> m ()
    getStatus :: EntryId -> m MergeStatus

    -- Validation and processing
    runValidation :: EntryId -> m ValidationResult
    processMerge :: EntryId -> m MergeResult
    rollbackMerge :: EntryId -> m ()

    -- Metrics
    getQueueMetrics :: Repository -> m QueueMetrics

-- | Queue processor configuration
data ProcessorConfig = ProcessorConfig
    { pcMaxConcurrent :: Int          -- Maximum concurrent merges
    , pcRetryLimit :: Int             -- Maximum retry attempts
    , pcRetryDelay :: NominalDiffTime -- Delay between retries
    , pcBatchSize :: Int              -- Number of changes to process in a batch
    , pcPollingInterval :: Int        -- Queue polling interval in microseconds
    } deriving (Show, Eq, Generic)

-- | Queue processor state
data QueueProcessor = QueueProcessor
    { qpConfig :: ProcessorConfig     -- Configuration
    , qpStorage :: QueueStorage       -- Storage backend
    , qpNotifier :: NotificationSystem -- Notification system
    , qpWebhooks :: WebhookSystem     -- Webhook system
    , qpAuditLogger :: AuditLoggerConfig -- Audit logging configuration
    } deriving (Show, Generic)

-- | Queue storage backend
data QueueStorage = QueueStorage
    { qsConnection :: Connection      -- Database connection
    , qsTableName :: Text            -- Queue table name
    } deriving (Show, Generic)

-- | Notification system
data NotificationSystem = NotificationSystem
    { nsConnection :: Connection      -- Database connection
    , nsConfig :: NotificationConfig  -- Notification configuration
    } deriving (Show, Generic)

-- | Webhook system
data WebhookSystem = WebhookSystem
    { wsConnection :: Connection      -- Database connection
    , wsConfig :: WebhookConfig      -- Webhook configuration
    } deriving (Show, Generic)

-- | Notification configuration
data NotificationConfig = NotificationConfig
    { ncEnabled :: Bool              -- Whether notifications are enabled
    , ncBatchSize :: Int            -- Notification batch size
    , ncRetryLimit :: Int           -- Maximum retry attempts
    } deriving (Show, Eq, Generic)

-- | Webhook configuration
data WebhookConfig = WebhookConfig
    { wcEnabled :: Bool              -- Whether webhooks are enabled
    , wcEndpoints :: [Text]         -- Webhook endpoints
    , wcTimeout :: Int              -- Webhook timeout in seconds
    , wcRetryLimit :: Int           -- Maximum retry attempts
    } deriving (Show, Eq, Generic)

-- | Queue item status
data QueueItemStatus
    = Queued        -- Waiting to be processed
    | Processing    -- Currently being processed
    | Merged        -- Successfully merged
    | Failed        -- Failed to merge
    | Abandoned     -- Abandoned due to conflicts/errors
    deriving (Show, Eq, Generic)

-- | Queue item
data QueueItem = QueueItem
    { qiId :: Text                    -- Queue item ID
    , qiChangeId :: Text              -- Change ID
    , qiStackId :: Maybe Text         -- Optional stack ID for stacked changes
    , qiDependencies :: [Text]        -- Change dependencies
    , qiPriority :: Int              -- Processing priority (lower = higher)
    , qiRetries :: Int               -- Number of retry attempts
    , qiSubmitted :: UTCTime         -- When the change was submitted
    , qiStarted :: Maybe UTCTime     -- When processing started
    , qiCompleted :: Maybe UTCTime   -- When processing completed
    , qiStatus :: QueueItemStatus    -- Current status
    , qiError :: Maybe Text          -- Error message if failed
    , qiUserId :: Text               -- User who submitted the change
    , qiEnterpriseId :: Text         -- Enterprise ID for the change
    } deriving (Show, Eq, Generic)

-- | Queue status
data QueueStatus = QueueStatus
    { qsActive :: Bool                -- Whether the queue is processing
    , qsSize :: Int                   -- Current queue size
    , qsProcessing :: Int             -- Number of items being processed
    , qsLastProcessed :: Maybe UTCTime -- Last successful processing time
    , qsErrors :: Int                 -- Number of errors
    } deriving (Show, Eq, Generic)

-- | VCS extension type
type Extension = Text

-- | Bookmark configuration
data BookmarkConfig = BookmarkConfig
    { bcActive :: Bool
    , bcPush :: Bool
    , bcTrack :: Bool
    } deriving (Show, Eq, Generic)

-- | MQ (Mercurial Queues) configuration
data MQConfig = MQConfig
    { mqEnabled :: Bool
    , mqGuards :: Bool
    , mqSeries :: FilePath
    , mqGuardsFile :: FilePath
    , mqRefresh :: Bool
    } deriving (Show, Eq, Generic)
