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

module Gerrit.Models.StackDependency
    ( -- * Types
      StackDependency(..)
    , DependencyId
    , RelationType(..)
      -- * Operations
    , addDependency
    , removeDependency
    , getDependencyById
    , listDependencies
    , validateDependencies
    , updateDependencyType
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Change (Change)
import Gerrit.Models.ChangeStack (ChangeStack)

-- | Dependency relation type
data RelationType
    = DirectDependency    -- ^ Direct parent-child relationship
    | IndirectDependency  -- ^ Transitive dependency
    | WeakDependency     -- ^ Soft dependency that can be broken
    deriving (Show, Read, Eq, Generic)
derivePersistField "RelationType"

-- | Define the StackDependency entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
StackDependency
    dependencyId Text
    stackId Text
    parentChangeId Text
    childChangeId Text
    relationType RelationType
    metadata Value Maybe
    created UTCTime
    UniqueDependencyId dependencyId
    UniqueStackDependency stackId parentChangeId childChangeId
    Foreign ChangeStack stackId References changeStacks OnDeleteCascade
    Foreign Change parentChangeId References changes OnDeleteCascade
    Foreign Change childChangeId References changes OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Add a new dependency between changes in a stack
addDependency :: MonadIO m
              => Text  -- ^ Stack ID
              -> Text  -- ^ Parent change ID
              -> Text  -- ^ Child change ID
              -> RelationType  -- ^ Relation type
              -> Maybe Value  -- ^ Additional metadata
              -> m (Entity StackDependency)
addDependency stackId' parentId childId relType metadata = do
    now <- liftIO getCurrentTime
    let depId = generateDependencyId stackId' parentId childId now
    let dep = StackDependency
            { stackDependencyDependencyId = depId
            , stackDependencyStackId = stackId'
            , stackDependencyParentChangeId = parentId
            , stackDependencyChildChangeId = childId
            , stackDependencyRelationType = relType
            , stackDependencyMetadata = metadata
            , stackDependencyCreated = now
            }
    runDB $ insertEntity dep

-- | Remove a dependency
removeDependency :: MonadIO m
                 => Text  -- ^ Stack ID
                 -> Text  -- ^ Parent change ID
                 -> Text  -- ^ Child change ID
                 -> m ()
removeDependency stackId' parentId childId =
    runDB $ deleteWhere
        [ StackDependencyStackId ==. stackId'
        , StackDependencyParentChangeId ==. parentId
        , StackDependencyChildChangeId ==. childId
        ]

-- | Get dependency by ID
getDependencyById :: MonadIO m
                  => Text  -- ^ Dependency ID
                  -> m (Maybe (Entity StackDependency))
getDependencyById depId =
    runDB $ getBy $ UniqueDependencyId depId

-- | List dependencies with filtering
listDependencies :: MonadIO m
                 => Text  -- ^ Stack ID
                 -> Maybe RelationType  -- ^ Filter by relation type
                 -> m [Entity StackDependency]
listDependencies stackId' mRelType = do
    let filters = (StackDependencyStackId ==. stackId') :
                 maybe [] (\relType -> [StackDependencyRelationType ==. relType]) mRelType
    runDB $ selectList filters [Asc StackDependencyCreated]

-- | Validate dependencies in a stack
validateDependencies :: MonadIO m
                    => Text  -- ^ Stack ID
                    -> m [(Text, Text, Text)]  -- ^ List of (parent, child, error) tuples for invalid dependencies
validateDependencies stackId' = do
    deps <- listDependencies stackId' Nothing
    -- This would involve checking for:
    -- 1. Circular dependencies
    -- 2. Missing changes
    -- 3. Changes not part of the stack
    -- 4. Invalid parent-child relationships
    -- For now, just a placeholder implementation
    return []

-- | Update dependency type
updateDependencyType :: MonadIO m
                    => Text  -- ^ Dependency ID
                    -> RelationType  -- ^ New relation type
                    -> m (Maybe (Entity StackDependency))
updateDependencyType depId relType = do
    runDB $ do
        mDep <- getBy $ UniqueDependencyId depId
        case mDep of
            Nothing -> return Nothing
            Just (Entity key dep) -> do
                let updatedDep = dep { stackDependencyRelationType = relType }
                replace key updatedDep
                return $ Just $ Entity key updatedDep

-- Helper functions for generating IDs
generateDependencyId :: Text -> Text -> Text -> UTCTime -> Text
generateDependencyId stackId parentId childId timestamp =
    "dep_" <> Text.filter isAllowed stackId <> "_" <> Text.filter isAllowed parentId <>
    "_" <> Text.filter isAllowed childId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
