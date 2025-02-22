{-
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

module Gerrit.Models.Change
    ( -- * Types
      Change(..)
    , ChangeId
    , ChangeStatus(..)
    , ChangeType(..)
    , ChangePhase(..)
    , PatchSetGeneration(..)
    , DependencyType(..)
      -- * Operations
    , createChange
    , updateChangeStatus
    , getChangeById
    , listChanges
    , getChangesByOwner
    , getChangesByProject
    , getChangeDependencies
    , updateChangeDependencies
    , generatePatchSet
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Represents the status of a change
data ChangeStatus
    = Draft
    | Open
    | Merged
    | Abandoned
    | Deferred
    | Integrating  -- ^ Change is being integrated
    | IntegrationFailed Text  -- ^ Integration failed with error
    deriving (Show, Eq, Generic)

derivePersistField "ChangeStatus"

-- | Type of change
data ChangeType
    = Feature
    | Bugfix
    | Documentation
    | Refactor
    | Test
    | Build
    | Other Text
    deriving (Show, Eq, Generic)

derivePersistField "ChangeType"

-- | Phase of the change
data ChangePhase
    = Review
    | Verification
    | Integration
    | Submission
    deriving (Show, Eq, Generic)

derivePersistField "ChangePhase"

-- | Patch set generation configuration
data PatchSetGeneration = PatchSetGeneration
    { autoGenerate :: Bool  -- ^ Whether to auto-generate patch sets
    , triggerPaths :: [Text]  -- ^ Paths that trigger generation
    , excludePaths :: [Text]  -- ^ Paths to exclude
    , maxSize :: Int  -- ^ Maximum patch set size
    , strategy :: Text  -- ^ Generation strategy
    } deriving (Show, Eq, Generic)

derivePersistField "PatchSetGeneration"

-- | Type of dependency between changes
data DependencyType
    = Required  -- ^ Hard dependency
    | Optional  -- ^ Soft dependency
    | Related   -- ^ Related change
    deriving (Show, Eq, Generic)

derivePersistField "DependencyType"

-- | Define the Change entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Change
    changeId Text
    projectId Text
    branch Text
    subject Text
    description Text Maybe
    ownerId Text
    status ChangeStatus
    changeType ChangeType
    phase ChangePhase
    patchSetConfig PatchSetGeneration
    workInProgress Bool default=false
    private Bool default=false
    topic Text Maybe
    hashtags [Text] default=[]
    reviewers [Text] default=[]
    assignee Text Maybe
    priority Int default=0
    submitStrategy Text default="merge_if_necessary"
    mergeStrategy Text Maybe
    integrationStatus Value Maybe
    created UTCTime
    updated UTCTime
    UniqueChangeId changeId
    deriving Show Eq Generic

ChangeDependency
    dependencyId Text
    changeId Text
    dependsOnId Text  -- ^ ID of the change this depends on
    dependencyType DependencyType
    required Bool default=true
    metadata Value Maybe
    created UTCTime
    UniqueDependencyId dependencyId
    Foreign Change changeId References changes OnDeleteCascade
    Foreign Change dependsOnId References changes OnDeleteCascade
    deriving Show Eq Generic

ChangeActivity
    activityId Text
    changeId Text
    activityType Text
    oldValue Value Maybe
    newValue Value Maybe
    performedBy Text
    details Value Maybe
    timestamp UTCTime
    UniqueActivityId activityId
    Foreign Change changeId References changes OnDeleteCascade
    deriving Show Eq Generic
|]

instance ToJSON Change
instance FromJSON Change

instance ToJSON ChangeDependency
instance FromJSON ChangeDependency

instance ToJSON ChangeActivity
instance FromJSON ChangeActivity

-- | Create a new change
createChange :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Project ID
             -> Text  -- ^ Branch
             -> Text  -- ^ Subject
             -> Maybe Text  -- ^ Description
             -> Text  -- ^ Owner ID
             -> ChangeType  -- ^ Type of change
             -> PatchSetGeneration  -- ^ Patch set configuration
             -> m (Entity Change)
createChange pool projectId' branch' subject' description' ownerId' changeType' patchSetConfig' = do
    now <- liftIO getCurrentTime
    let changeId' = generateChangeId projectId' branch' now
    let change = Change
            { changeChangeId = changeId'
            , changeProjectId = projectId'
            , changeBranch = branch'
            , changeSubject = subject'
            , changeDescription = description'
            , changeOwnerId = ownerId'
            , changeStatus = Draft
            , changeChangeType = changeType'
            , changePhase = Review
            , changePatchSetConfig = patchSetConfig'
            , changeWorkInProgress = True
            , changePrivate = False
            , changeTopic = Nothing
            , changeHashtags = []
            , changeReviewers = []
            , changeAssignee = Nothing
            , changePriority = 0
            , changeSubmitStrategy = "merge_if_necessary"
            , changeMergeStrategy = Nothing
            , changeIntegrationStatus = Nothing
            , changeCreated = now
            , changeUpdated = now
            }
    runSqlPool (insertEntity change) pool

-- | Update a change's status
updateChangeStatus :: MonadIO m
                  => ConnectionPool
                  -> Entity Change
                  -> ChangeStatus
                  -> m (Entity Change)
updateChangeStatus pool (Entity key change) newStatus = do
    now <- liftIO getCurrentTime
    let updatedChange = change
            { changeStatus = newStatus
            , changeUpdated = now
            }
    runSqlPool (replace key updatedChange) pool
    return $ Entity key updatedChange

-- | Get a change by ID
getChangeById :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Change ID
              -> m (Maybe (Entity Change))
getChangeById pool changeId' =
    runSqlPool (getBy $ UniqueChangeId changeId') pool

-- | List changes with pagination
listChanges :: MonadIO m
            => ConnectionPool
            -> Int  -- ^ Offset
            -> Int  -- ^ Limit
            -> m [Entity Change]
listChanges pool offset limit =
    runSqlPool (selectList [] [Desc ChangeCreated, OffsetBy offset, LimitTo limit]) pool

-- | Get changes by owner
getChangesByOwner :: MonadIO m
                  => ConnectionPool
                  -> Text  -- ^ Owner ID
                  -> m [Entity Change]
getChangesByOwner pool ownerId' =
    runSqlPool (selectList [ChangeOwnerId ==. ownerId'] [Desc ChangeCreated]) pool

-- | Get changes by project
getChangesByProject :: MonadIO m
                    => ConnectionPool
                    -> Text  -- ^ Project ID
                    -> m [Entity Change]
getChangesByProject pool projectId' =
    runSqlPool (selectList [ChangeProjectId ==. projectId'] [Desc ChangeCreated]) pool

-- | Get dependencies for a change
getChangeDependencies :: MonadIO m
                     => ConnectionPool
                     -> Text  -- ^ Change ID
                     -> m [Entity ChangeDependency]
getChangeDependencies pool changeId' =
    runSqlPool (selectList [ChangeDependencyChangeId ==. changeId'] [Asc ChangeDependencyCreated]) pool

-- | Update dependencies for a change
updateChangeDependencies :: MonadIO m
                        => ConnectionPool
                        -> Text  -- ^ Change ID
                        -> [(Text, DependencyType)]  -- ^ List of (dependsOnId, type) pairs
                        -> m [Entity ChangeDependency]
updateChangeDependencies pool changeId' dependencies = do
    now <- liftIO getCurrentTime
    -- Delete existing dependencies
    runSqlPool (deleteWhere [ChangeDependencyChangeId ==. changeId']) pool
    -- Create new dependencies
    mapM (\(depId, depType) -> do
        let depId' = generateDependencyId changeId' depId now
        let dep = ChangeDependency
                { changeDependencyDependencyId = depId'
                , changeDependencyChangeId = changeId'
                , changeDependencyDependsOnId = depId
                , changeDependencyDependencyType = depType
                , changeDependencyRequired = True
                , changeDependencyMetadata = Nothing
                , changeDependencyCreated = now
                }
        runSqlPool (insertEntity dep) pool) dependencies

-- | Generate a patch set for a change
generatePatchSet :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Change ID
                 -> m (Maybe (Entity Revision))
generatePatchSet = undefined  -- TODO: Implement patch set generation

-- | Helper function to generate a unique change ID
generateChangeId :: Text -> Text -> UTCTime -> Text
generateChangeId projectId branch timestamp =
    "I" <> Text.filter isAllowed (projectId <> "-" <> branch <> "-" <> showt timestamp)
  where
    showt = Text.pack . show
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

-- | Helper function to generate a unique dependency ID
generateDependencyId :: Text -> Text -> UTCTime -> Text
generateDependencyId changeId dependsOnId timestamp =
    "D" <> Text.filter isAllowed (changeId <> "-" <> dependsOnId <> "-" <> showt timestamp)
  where
    showt = Text.pack . show
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
