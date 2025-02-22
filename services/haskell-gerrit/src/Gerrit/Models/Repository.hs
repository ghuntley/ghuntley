{-|
Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Models.Repository
    ( -- * Types
      Repository(..)
    , RepositoryId
    , RepositoryStatus(..)
    , RepositoryConfig(..)
    , RepositoryConfigId
    , RepositoryAccess(..)
    , RepositoryAccessId
    , RepositoryMetrics(..)
    , RepositoryMetricsId
    , VCSType
    , RepoVisibility
    , MirrorConfig
    , MirrorType
    , BranchProtection
    , RepoStats
      -- * Operations
    , createRepository
    , updateRepository
    , getRepositoryById
    , listRepositories
    , updateConfig
    , getConfig
    , grantAccess
    , revokeAccess
    , getAccessList
    , updateMetrics
    , getMetrics
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Organization (Organization)

-- | Repository status
data RepositoryStatus
    = Active
    | Archived
    | Disabled
    | Maintenance
    deriving (Show, Read, Eq, Generic)
derivePersistField "RepositoryStatus"

-- | VCS type supported by the repository
data VCSType =
    Git
  | Mercurial
  | JJ
  deriving (Show, Read, Eq, Generic)

instance ToJSON VCSType
instance FromJSON VCSType

derivePersistField "VCSType"

-- | Repository visibility level
data RepoVisibility =
    PublicRepo
  | PrivateRepo
  | InternalRepo
  deriving (Show, Read, Eq, Generic)

instance ToJSON RepoVisibility
instance FromJSON RepoVisibility

derivePersistField "RepoVisibility"

-- | Repository mirroring configuration
data MirrorConfig = MirrorConfig
  { mirrorUrl :: Text
  , mirrorType :: MirrorType
  , syncInterval :: Int  -- ^ Sync interval in minutes
  , syncEnabled :: Bool
  , credentials :: Value  -- ^ Encrypted credentials for mirror access
  , lastSync :: Maybe UTCTime
  , lastSyncStatus :: Maybe Text
  } deriving (Show, Generic)

instance ToJSON MirrorConfig
instance FromJSON MirrorConfig

derivePersistField "MirrorConfig"

-- | Mirror type
data MirrorType =
    PullMirror  -- ^ Mirror pulls from remote
  | PushMirror  -- ^ Mirror pushes to remote
  | BidirectionalMirror  -- ^ Mirror syncs both ways
  deriving (Show, Read, Eq, Generic)

instance ToJSON MirrorType
instance FromJSON MirrorType

derivePersistField "MirrorType"

-- | Branch protection rules
data BranchProtection = BranchProtection
  { pattern :: Text  -- ^ Branch name pattern
  , requirePullRequest :: Bool
  , requiredReviewers :: Int
  , requireBuildSuccess :: Bool
  , requireCodeOwnerReview :: Bool
  , allowForcePush :: Bool
  , allowDeletion :: Bool
  , requiredStatusChecks :: [Text]
  , bypassRules :: Value  -- ^ Rules for bypassing protection
  } deriving (Show, Generic)

instance ToJSON BranchProtection
instance FromJSON BranchProtection

derivePersistField "BranchProtection"

-- | Repository statistics
data RepoStats = RepoStats
  { totalCommits :: Int
  , totalBranches :: Int
  , totalTags :: Int
  , totalContributors :: Int
  , diskUsage :: Int64  -- ^ Disk usage in bytes
  , lastCommitAt :: UTCTime
  , lastActivityAt :: UTCTime
  , languageStats :: Value  -- ^ Language usage statistics
  } deriving (Show, Generic)

instance ToJSON RepoStats
instance FromJSON RepoStats

derivePersistField "RepoStats"

-- | Define the repository entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Repository
    repoId Text
    orgId Text
    name Text
    description Text Maybe
    vcsType VCSType
    visibility RepoVisibility
    projectId Text
    defaultBranch Text default='main'
    mirrorConfig MirrorConfig Maybe
    branchProtection [BranchProtection]
    webhookSecret Text Maybe
    stats RepoStats Maybe
    metadata Value Maybe
    createdBy Text
    created UTCTime
    updated UTCTime
    status RepositoryStatus
    cloneUrl Text
    webUrl Text
    UniqueRepoId repoId
    UniqueOrgRepo orgId name
    UniqueRepoName projectId name
    Foreign Organization orgId References organizations OnDeleteCascade
    deriving Show Eq Generic

RepositoryConfig
    configId Text
    repoId Text
    submitRequirements Value
    protectedBranches Value
    webhooks Value Maybe
    integrations Value Maybe
    customSettings Value Maybe
    created UTCTime
    updated UTCTime
    UniqueConfigId configId
    UniqueRepoConfig repoId
    Foreign Repository repoId References repositories OnDeleteCascade
    deriving Show Eq Generic

RepositoryAccess
    accessId Text
    repoId Text
    userId Text
    role Role
    permissions [Permission]
    grantedBy Text
    expiresAt UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueAccessId accessId
    UniqueRepoUserAccess repoId userId
    Foreign Repository repoId References repositories OnDeleteCascade
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic

RepositoryMetrics
    metricsId Text
    repoId Text
    totalChanges Int
    openChanges Int
    mergedChanges Int
    abandonedChanges Int
    totalComments Int
    totalReviewers Int
    avgReviewTime Double
    mergeSuccessRate Double
    timestamp UTCTime
    UniqueMetricsId metricsId
    Foreign Repository repoId References repositories OnDeleteCascade
    deriving Show Eq Generic

RepositoryMirrorLog
    logId Text
    repoId Text
    mirrorUrl Text
    action Text  -- ^ sync, configure, error
    status Text
    details Value Maybe
    timestamp UTCTime
    UniqueLogId logId
    Foreign Repository repoId References repositories OnDeleteCascade
    deriving Show Eq Generic

RepositoryActivity
    activityId Text
    repoId Text
    activityType Text  -- ^ push, branch, tag, etc.
    branch Text Maybe
    commitId Text Maybe
    performedBy Text
    details Value
    timestamp UTCTime
    UniqueActivityId activityId
    Foreign Repository repoId References repositories OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new repository
createRepository :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Organization ID
                 -> Text  -- ^ Name
                 -> Maybe Text  -- ^ Description
                 -> Text  -- ^ Default branch
                 -> Visibility  -- ^ Visibility
                 -> Text  -- ^ Clone URL
                 -> Text  -- ^ Web URL
                 -> Maybe Value  -- ^ Metadata
                 -> m (Entity Repository)
createRepository pool orgId name desc defaultBranch visibility cloneUrl webUrl metadata = do
    now <- liftIO getCurrentTime
    let repoId = generateRepoId orgId name now
    let repo = Repository
            { repositoryRepoId = repoId
            , repositoryOrgId = orgId
            , repositoryName = name
            , repositoryDescription = desc
            , repositoryDefaultBranch = defaultBranch
            , repositoryStatus = Active
            , repositoryVisibility = visibility
            , repositoryCloneUrl = cloneUrl
            , repositoryWebUrl = webUrl
            , repositoryMetadata = metadata
            , repositoryCreated = now
            , repositoryUpdated = now
            }
    runSqlPool (insertEntity repo) pool

-- | Update repository
updateRepository :: MonadIO m
                 => ConnectionPool
                 -> Entity Repository
                 -> Text  -- ^ New name
                 -> Maybe Text  -- ^ New description
                 -> Text  -- ^ New default branch
                 -> RepositoryStatus  -- ^ New status
                 -> Visibility  -- ^ New visibility
                 -> Maybe Value  -- ^ New metadata
                 -> m (Entity Repository)
updateRepository pool (Entity key repo) newName newDesc newBranch newStatus newVisibility newMetadata = do
    now <- liftIO getCurrentTime
    let updatedRepo = repo
            { repositoryName = newName
            , repositoryDescription = newDesc
            , repositoryDefaultBranch = newBranch
            , repositoryStatus = newStatus
            , repositoryVisibility = newVisibility
            , repositoryMetadata = newMetadata
            , repositoryUpdated = now
            }
    runSqlPool (replace key updatedRepo) pool
    return $ Entity key updatedRepo

-- | Get repository by ID
getRepositoryById :: MonadIO m
                  => ConnectionPool
                  -> Text  -- ^ Repository ID
                  -> m (Maybe (Entity Repository))
getRepositoryById pool repoId =
    runSqlPool (getBy $ UniqueRepoId repoId) pool

-- | List repositories with filters
listRepositories :: MonadIO m
                 => ConnectionPool
                 -> Maybe Text  -- ^ Organization ID filter
                 -> Maybe RepositoryStatus  -- ^ Status filter
                 -> Maybe Visibility  -- ^ Visibility filter
                 -> Int  -- ^ Offset
                 -> Int  -- ^ Limit
                 -> m [Entity Repository]
listRepositories pool mOrgId mStatus mVisibility offset limit = do
    let filters = concat
            [ maybe [] (\orgId -> [RepositoryOrgId ==. orgId]) mOrgId
            , maybe [] (\status -> [RepositoryStatus ==. status]) mStatus
            , maybe [] (\visibility -> [RepositoryVisibility ==. visibility]) mVisibility
            ]
    runSqlPool (selectList filters [Desc RepositoryCreated, OffsetBy offset, LimitTo limit]) pool

-- | Update repository configuration
updateConfig :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Repository ID
             -> Value  -- ^ Submit requirements
             -> Value  -- ^ Protected branches
             -> Maybe Value  -- ^ Webhooks
             -> Maybe Value  -- ^ Integrations
             -> Maybe Value  -- ^ Custom settings
             -> m (Entity RepositoryConfig)
updateConfig pool repoId submitReqs protectedBranches webhooks integrations customSettings = do
    now <- liftIO getCurrentTime
    let configId = generateConfigId repoId now
    let config = RepositoryConfig
            { repositoryConfigConfigId = configId
            , repositoryConfigRepoId = repoId
            , repositoryConfigSubmitRequirements = submitReqs
            , repositoryConfigProtectedBranches = protectedBranches
            , repositoryConfigWebhooks = webhooks
            , repositoryConfigIntegrations = integrations
            , repositoryConfigCustomSettings = customSettings
            , repositoryConfigCreated = now
            , repositoryConfigUpdated = now
            }
    runSqlPool (upsert config [RepositoryConfigUpdated =. now]) pool

-- | Get repository configuration
getConfig :: MonadIO m
          => ConnectionPool
          -> Text  -- ^ Repository ID
          -> m (Maybe (Entity RepositoryConfig))
getConfig pool repoId =
    runSqlPool (getBy $ UniqueRepoConfig repoId) pool

-- | Grant repository access
grantAccess :: MonadIO m
            => ConnectionPool
            -> Text  -- ^ Repository ID
            -> Text  -- ^ User ID
            -> Role  -- ^ Role
            -> [Permission]  -- ^ Permissions
            -> Text  -- ^ Granted by user ID
            -> Maybe UTCTime  -- ^ Expiry time
            -> m (Entity RepositoryAccess)
grantAccess pool repoId userId role perms grantedBy expiresAt = do
    now <- liftIO getCurrentTime
    let accessId = generateAccessId repoId userId now
    let access = RepositoryAccess
            { repositoryAccessAccessId = accessId
            , repositoryAccessRepoId = repoId
            , repositoryAccessUserId = userId
            , repositoryAccessRole = role
            , repositoryAccessPermissions = perms
            , repositoryAccessGrantedBy = grantedBy
            , repositoryAccessExpiresAt = expiresAt
            , repositoryAccessCreated = now
            , repositoryAccessUpdated = now
            }
    runSqlPool (upsert access [RepositoryAccessUpdated =. now]) pool

-- | Revoke repository access
revokeAccess :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Repository ID
             -> Text  -- ^ User ID
             -> m ()
revokeAccess pool repoId userId =
    runSqlPool (deleteBy $ UniqueRepoUserAccess repoId userId) pool

-- | Get repository access list
getAccessList :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Repository ID
              -> m [Entity RepositoryAccess]
getAccessList pool repoId =
    runSqlPool (selectList [RepositoryAccessRepoId ==. repoId] [Asc RepositoryAccessCreated]) pool

-- | Update repository metrics
updateMetrics :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Repository ID
              -> Int  -- ^ Total changes
              -> Int  -- ^ Open changes
              -> Int  -- ^ Merged changes
              -> Int  -- ^ Abandoned changes
              -> Int  -- ^ Total comments
              -> Int  -- ^ Total reviewers
              -> Double  -- ^ Average review time
              -> Double  -- ^ Merge success rate
              -> m (Entity RepositoryMetrics)
updateMetrics pool repoId totalChanges openChanges mergedChanges abandonedChanges
              totalComments totalReviewers avgReviewTime mergeSuccessRate = do
    now <- liftIO getCurrentTime
    let metricsId = generateMetricsId repoId now
    let metrics = RepositoryMetrics
            { repositoryMetricsMetricsId = metricsId
            , repositoryMetricsRepoId = repoId
            , repositoryMetricsTotalChanges = totalChanges
            , repositoryMetricsOpenChanges = openChanges
            , repositoryMetricsMergedChanges = mergedChanges
            , repositoryMetricsAbandonedChanges = abandonedChanges
            , repositoryMetricsTotalComments = totalComments
            , repositoryMetricsTotalReviewers = totalReviewers
            , repositoryMetricsAvgReviewTime = avgReviewTime
            , repositoryMetricsMergeSuccessRate = mergeSuccessRate
            , repositoryMetricsTimestamp = now
            }
    runSqlPool (insertEntity metrics) pool

-- | Get repository metrics
getMetrics :: MonadIO m
           => ConnectionPool
           -> Text  -- ^ Repository ID
           -> m (Maybe (Entity RepositoryMetrics))
getMetrics pool repoId = runSqlPool $
    selectFirst
        [RepositoryMetricsRepoId ==. repoId]
        [Desc RepositoryMetricsTimestamp]

-- Helper functions for generating IDs
generateRepoId :: Text -> Text -> UTCTime -> Text
generateRepoId orgId name timestamp =
    "repo_" <> Text.filter isAllowed (orgId <> "_" <> name) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateConfigId :: Text -> UTCTime -> Text
generateConfigId repoId timestamp =
    "cfg_" <> Text.filter isAllowed repoId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateAccessId :: Text -> Text -> UTCTime -> Text
generateAccessId repoId userId timestamp =
    "acc_" <> Text.filter isAllowed (repoId <> "_" <> userId) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateMetricsId :: Text -> UTCTime -> Text
generateMetricsId repoId timestamp =
    "met_" <> Text.filter isAllowed repoId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
