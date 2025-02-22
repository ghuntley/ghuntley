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

module Gerrit.Models.ChangeStack
    ( -- * Types
      ChangeStack(..)
    , StackId
    , StackStatus(..)
      -- * Operations
    , createStack
    , updateStackStatus
    , getStackById
    , listStacks
    , addChangeToStack
    , removeChangeFromStack
    , reorderStack
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

-- | Stack status
data StackStatus
    = StackDraft      -- ^ Stack is being drafted
    | StackReady      -- ^ Stack is ready for review
    | StackReviewing  -- ^ Stack is being reviewed
    | StackApproved   -- ^ Stack is approved
    | StackSubmitting -- ^ Stack is being submitted
    | StackSubmitted  -- ^ Stack has been submitted
    | StackAbandoned  -- ^ Stack has been abandoned
    deriving (Show, Read, Eq, Generic)
derivePersistField "StackStatus"

-- | Define the ChangeStack entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
ChangeStack
    stackId Text
    name Text
    description Text Maybe
    ownerId Text
    projectId Text
    branch Text
    status StackStatus
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueStackId stackId
    deriving Show Eq Generic
|]

-- | Create a new change stack
createStack :: MonadIO m
            => Text  -- ^ Name
            -> Maybe Text  -- ^ Description
            -> Text  -- ^ Owner ID
            -> Text  -- ^ Project ID
            -> Text  -- ^ Branch
            -> Maybe Value  -- ^ Additional metadata
            -> m (Entity ChangeStack)
createStack name desc ownerId projectId branch metadata = do
    now <- liftIO getCurrentTime
    let stackId = generateStackId name ownerId now
    let stack = ChangeStack
            { changeStackStackId = stackId
            , changeStackName = name
            , changeStackDescription = desc
            , changeStackOwnerId = ownerId
            , changeStackProjectId = projectId
            , changeStackBranch = branch
            , changeStackStatus = StackDraft
            , changeStackMetadata = metadata
            , changeStackCreated = now
            , changeStackUpdated = now
            }
    runDB $ insertEntity stack

-- | Update stack status
updateStackStatus :: MonadIO m
                 => Text  -- ^ Stack ID
                 -> StackStatus  -- ^ New status
                 -> m (Maybe (Entity ChangeStack))
updateStackStatus stackId status = do
    now <- liftIO getCurrentTime
    runDB $ do
        mStack <- getBy $ UniqueStackId stackId
        case mStack of
            Nothing -> return Nothing
            Just (Entity key stack) -> do
                let updatedStack = stack
                        { changeStackStatus = status
                        , changeStackUpdated = now
                        }
                replace key updatedStack
                return $ Just $ Entity key updatedStack

-- | Get stack by ID
getStackById :: MonadIO m
             => Text  -- ^ Stack ID
             -> m (Maybe (Entity ChangeStack))
getStackById stackId =
    runDB $ getBy $ UniqueStackId stackId

-- | List stacks with filtering
listStacks :: MonadIO m
           => Maybe Text  -- ^ Owner ID
           -> Maybe Text  -- ^ Project ID
           -> Maybe StackStatus  -- ^ Status
           -> Int  -- ^ Offset
           -> Int  -- ^ Limit
           -> m [Entity ChangeStack]
listStacks mOwnerId mProjectId mStatus offset limit = do
    let filters = concat
            [ maybe [] (\oid -> [ChangeStackOwnerId ==. oid]) mOwnerId
            , maybe [] (\pid -> [ChangeStackProjectId ==. pid]) mProjectId
            , maybe [] (\s -> [ChangeStackStatus ==. s]) mStatus
            ]
    runDB $ selectList filters [Desc ChangeStackCreated, OffsetBy offset, LimitTo limit]

-- | Add a change to a stack
addChangeToStack :: MonadIO m
                => Text  -- ^ Stack ID
                -> Text  -- ^ Change ID
                -> m ()
addChangeToStack stackId changeId = do
    -- Implementation will be in StackDependency module
    return ()

-- | Remove a change from a stack
removeChangeFromStack :: MonadIO m
                     => Text  -- ^ Stack ID
                     -> Text  -- ^ Change ID
                     -> m ()
removeChangeFromStack stackId changeId = do
    -- Implementation will be in StackDependency module
    return ()

-- | Reorder changes in a stack
reorderStack :: MonadIO m
             => Text  -- ^ Stack ID
             -> [Text]  -- ^ Ordered list of change IDs
             -> m ()
reorderStack stackId changeIds = do
    -- Implementation will be in StackDependency module
    return ()

-- Helper functions for generating IDs
generateStackId :: Text -> Text -> UTCTime -> Text
generateStackId name ownerId timestamp =
    "stack_" <> Text.filter isAllowed name <> "_" <> Text.filter isAllowed ownerId <>
    "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
