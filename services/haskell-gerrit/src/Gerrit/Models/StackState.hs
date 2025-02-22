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

module Gerrit.Models.StackState
    ( -- * Types
      StackState(..)
    , StateId
    , ChangeState(..)
      -- * Operations
    , updateState
    , getStateById
    , listStates
    , getChangeState
    , updateChangeState
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

-- | Change state in a stack
data ChangeState
    = ChangeStateNew       -- ^ Change is new in the stack
    | ChangeStateReady     -- ^ Change is ready for review
    | ChangeStateReviewing -- ^ Change is being reviewed
    | ChangeStateApproved  -- ^ Change is approved
    | ChangeStateRejected  -- ^ Change is rejected
    | ChangeStateSubmitted -- ^ Change is submitted
    | ChangeStateAbandoned -- ^ Change is abandoned
    deriving (Show, Read, Eq, Generic)
derivePersistField "ChangeState"

-- | Define the StackState entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
StackState
    stateId Text
    stackId Text
    changeId Text
    state ChangeState
    rebaseState RebaseState Maybe
    conflictState ConflictState Maybe
    lastSyncHash Text Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueStateId stateId
    UniqueStackState stackId changeId
    Foreign ChangeStack stackId References changeStacks OnDeleteCascade
    Foreign Change changeId References changes OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Update state of a change in a stack
updateState :: MonadIO m
            => Text  -- ^ Stack ID
            -> Text  -- ^ Change ID
            -> ChangeState  -- ^ New state
            -> Maybe RebaseState  -- ^ Rebase state
            -> Maybe ConflictState  -- ^ Conflict state
            -> Maybe Text  -- ^ Last sync hash
            -> Maybe Value  -- ^ Additional metadata
            -> m (Entity StackState)
updateState stackId' changeId state' rebase conflict syncHash metadata = do
    now <- liftIO getCurrentTime
    let stateId' = generateStateId stackId' changeId now
    let state = StackState
            { stackStateStateId = stateId'
            , stackStateStackId = stackId'
            , stackStateChangeId = changeId
            , stackStateState = state'
            , stackStateRebaseState = rebase
            , stackStateConflictState = conflict
            , stackStateLastSyncHash = syncHash
            , stackStateMetadata = metadata
            , stackStateCreated = now
            , stackStateUpdated = now
            }
    runDB $ insertBy state >>= \case
        Left (Entity key _) -> do
            update key
                [ StackStateState =. state'
                , StackStateRebaseState =. rebase
                , StackStateConflictState =. conflict
                , StackStateLastSyncHash =. syncHash
                , StackStateMetadata =. metadata
                , StackStateUpdated =. now
                ]
            getEntity key
        Right entity -> return entity

-- | Get state by ID
getStateById :: MonadIO m
             => Text  -- ^ State ID
             -> m (Maybe (Entity StackState))
getStateById stateId' =
    runDB $ getBy $ UniqueStateId stateId'

-- | List states for a stack
listStates :: MonadIO m
           => Text  -- ^ Stack ID
           -> m [Entity StackState]
listStates stackId' =
    runDB $ selectList [StackStateStackId ==. stackId'] [Asc StackStateCreated]

-- | Get state for a specific change in a stack
getChangeState :: MonadIO m
               => Text  -- ^ Stack ID
               -> Text  -- ^ Change ID
               -> m (Maybe (Entity StackState))
getChangeState stackId' changeId =
    runDB $ getBy $ UniqueStackState stackId' changeId

-- | Update state of a change
updateChangeState :: MonadIO m
                 => Text  -- ^ Stack ID
                 -> Text  -- ^ Change ID
                 -> ChangeState  -- ^ New state
                 -> m (Maybe (Entity StackState))
updateChangeState stackId' changeId state' = do
    now <- liftIO getCurrentTime
    runDB $ do
        mState <- getBy $ UniqueStackState stackId' changeId
        case mState of
            Nothing -> return Nothing
            Just (Entity key state) -> do
                let updatedState = state
                        { stackStateState = state'
                        , stackStateUpdated = now
                        }
                replace key updatedState
                return $ Just $ Entity key updatedState

-- Helper functions for generating IDs
generateStateId :: Text -> Text -> UTCTime -> Text
generateStateId stackId changeId timestamp =
    "state_" <> Text.filter isAllowed stackId <> "_" <> Text.filter isAllowed changeId <>
    "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
