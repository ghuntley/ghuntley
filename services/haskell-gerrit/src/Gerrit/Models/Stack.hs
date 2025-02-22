-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

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

module Gerrit.Models.Stack
    ( -- * Types
      ChangeStack(..)
    , ChangeStackId
    , StackStatus(..)
    , StackDependency(..)
    , StackDependencyId
    , RelationType(..)
    , StackState(..)
    , StackStateId
    , RebaseState(..)
    , ConflictState(..)
    -- * Operations
    , createStack
    , updateStack
    , getStackById
    , listStacks
    , addDependency
    , removeDependency
    , getDependencies
    , updateStackState
    , getStackState
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Change (Change)

-- | Stack status
data StackStatus
    = StackOpen
    | StackSubmitting
    | StackSubmitted
    | StackAbandoned
    deriving (Show, Read, Eq, Generic)
derivePersistField "StackStatus"

-- | Dependency relation type
data RelationType
    = DirectDependency
    | IndirectDependency
    | WeakDependency
    deriving (Show, Read, Eq, Generic)
derivePersistField "RelationType"

-- | Rebase state
data RebaseState
    = RebaseNeeded
    | RebaseInProgress
    | RebaseCompleted
    | RebaseFailed Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "RebaseState"

-- | Conflict state
data ConflictState
    = NoConflicts
    | ConflictsDetected
    | ConflictsResolved
    | ConflictsUnresolvable
    deriving (Show, Read, Eq, Generic)
derivePersistField "ConflictState"

-- | Define the stack entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
ChangeStack
    stackId Text
    name Text
    description Text Maybe
    ownerId Text
    repositoryId Text
    baseBranch Text
    status StackStatus
    created UTCTime
    updated UTCTime
    UniqueStackId stackId
    deriving Show Eq Generic

StackDependency
    dependencyId Text
    stackId Text
    parentChangeId Text
    childChangeId Text
    relationType RelationType
    created UTCTime
    UniqueDependencyId dependencyId
    UniqueStackDependency stackId parentChangeId childChangeId
    Foreign ChangeStack stackId References change_stacks OnDeleteCascade
    Foreign Change parentChangeId References changes OnDeleteCascade
    Foreign Change childChangeId References changes OnDeleteCascade
    deriving Show Eq Generic

StackState
    stateId Text
    stackId Text
    changeId Text
    status Text
    rebaseState RebaseState Maybe
    conflictState ConflictState Maybe
    lastSyncHash Text Maybe
    created UTCTime
    updated UTCTime
    UniqueStateId stateId
    UniqueStackState stackId changeId
    Foreign ChangeStack stackId References change_stacks OnDeleteCascade
    Foreign Change changeId References changes OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new change stack
createStack :: MonadIO m
           => ConnectionPool
           -> Text  -- ^ Name
           -> Maybe Text  -- ^ Description
           -> Text  -- ^ Owner ID
           -> Text  -- ^ Repository ID
           -> Text  -- ^ Base branch
           -> m (Entity ChangeStack)
createStack pool name desc ownerId repoId baseBranch = do
    now <- liftIO getCurrentTime
    let stackId = generateStackId name ownerId now
    let stack = ChangeStack
            { changeStackStackId = stackId
            , changeStackName = name
            , changeStackDescription = desc
            , changeStackOwnerId = ownerId
            , changeStackRepositoryId = repoId
            , changeStackBaseBranch = baseBranch
            , changeStackStatus = StackOpen
            , changeStackCreated = now
            , changeStackUpdated = now
            }
    runSqlPool (insertEntity stack) pool

-- | Update stack
updateStack :: MonadIO m
           => ConnectionPool
           -> Entity ChangeStack
           -> Text  -- ^ New name
           -> Maybe Text  -- ^ New description
           -> Text  -- ^ New base branch
           -> StackStatus  -- ^ New status
           -> m (Entity ChangeStack)
updateStack pool (Entity key stack) newName newDesc newBaseBranch newStatus = do
    now <- liftIO getCurrentTime
    let updatedStack = stack
            { changeStackName = newName
            , changeStackDescription = newDesc
            , changeStackBaseBranch = newBaseBranch
            , changeStackStatus = newStatus
            , changeStackUpdated = now
            }
    runSqlPool (replace key updatedStack) pool
    return $ Entity key updatedStack

-- | Get stack by ID
getStackById :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Stack ID
             -> m (Maybe (Entity ChangeStack))
getStackById pool stackId =
    runSqlPool (getBy $ UniqueStackId stackId) pool

-- | List stacks with filters
listStacks :: MonadIO m
           => ConnectionPool
           -> Maybe Text  -- ^ Owner ID filter
           -> Maybe Text  -- ^ Repository ID filter
           -> Maybe StackStatus  -- ^ Status filter
           -> Int  -- ^ Offset
           -> Int  -- ^ Limit
           -> m [Entity ChangeStack]
listStacks pool mOwnerId mRepoId mStatus offset limit = do
    let filters = concat
            [ maybe [] (\ownerId -> [ChangeStackOwnerId ==. ownerId]) mOwnerId
            , maybe [] (\repoId -> [ChangeStackRepositoryId ==. repoId]) mRepoId
            , maybe [] (\status -> [ChangeStackStatus ==. status]) mStatus
            ]
    runSqlPool (selectList filters [Desc ChangeStackCreated, OffsetBy offset, LimitTo limit]) pool

-- | Add stack dependency
addDependency :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Stack ID
              -> Text  -- ^ Parent change ID
              -> Text  -- ^ Child change ID
              -> RelationType  -- ^ Relation type
              -> m (Entity StackDependency)
addDependency pool stackId parentId childId relType = do
    now <- liftIO getCurrentTime
    let depId = generateDependencyId stackId parentId childId now
    let dep = StackDependency
            { stackDependencyDependencyId = depId
            , stackDependencyStackId = stackId
            , stackDependencyParentChangeId = parentId
            , stackDependencyChildChangeId = childId
            , stackDependencyRelationType = relType
            , stackDependencyCreated = now
            }
    runSqlPool (insertEntity dep) pool

-- | Remove stack dependency
removeDependency :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Stack ID
                 -> Text  -- ^ Parent change ID
                 -> Text  -- ^ Child change ID
                 -> m ()
removeDependency pool stackId parentId childId =
    runSqlPool (deleteBy $ UniqueStackDependency stackId parentId childId) pool

-- | Get stack dependencies
getDependencies :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Stack ID
                -> m [Entity StackDependency]
getDependencies pool stackId =
    runSqlPool (selectList [StackDependencyStackId ==. stackId] [Asc StackDependencyCreated]) pool

-- | Update stack state
updateStackState :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Stack ID
                 -> Text  -- ^ Change ID
                 -> Text  -- ^ Status
                 -> Maybe RebaseState  -- ^ Rebase state
                 -> Maybe ConflictState  -- ^ Conflict state
                 -> Maybe Text  -- ^ Last sync hash
                 -> m (Entity StackState)
updateStackState pool stackId changeId status rebaseState conflictState lastSyncHash = do
    now <- liftIO getCurrentTime
    let stateId = generateStateId stackId changeId now
    let state = StackState
            { stackStateStateId = stateId
            , stackStateStackId = stackId
            , stackStateChangeId = changeId
            , stackStateStatus = status
            , stackStateRebaseState = rebaseState
            , stackStateConflictState = conflictState
            , stackStateLastSyncHash = lastSyncHash
            , stackStateCreated = now
            , stackStateUpdated = now
            }
    runSqlPool (upsert state [StackStateUpdated =. now]) pool

-- | Get stack state
getStackState :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Stack ID
              -> Text  -- ^ Change ID
              -> m (Maybe (Entity StackState))
getStackState pool stackId changeId =
    runSqlPool (getBy $ UniqueStackState stackId changeId) pool

-- Helper functions for generating IDs
generateStackId :: Text -> Text -> UTCTime -> Text
generateStackId name ownerId timestamp =
    "stack_" <> Text.filter isAllowed (name <> "_" <> ownerId) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateDependencyId :: Text -> Text -> Text -> UTCTime -> Text
generateDependencyId stackId parentId childId timestamp =
    "dep_" <> Text.filter isAllowed (stackId <> "_" <> parentId <> "_" <> childId) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateStateId :: Text -> Text -> UTCTime -> Text
generateStateId stackId changeId timestamp =
    "state_" <> Text.filter isAllowed (stackId <> "_" <> changeId) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
