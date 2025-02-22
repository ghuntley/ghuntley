-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Stack
    ( -- * Handlers
      handleCreateStack
    , handleUpdateStack
    , handleDeleteStack
    , handleGetStack
    , handleListStacks
    , handleAddChangeToStack
    , handleRemoveChangeFromStack
    , handleReorderStack
    , handleRebaseStack
    , handleSubmitStack
    , handleAbandonStack
    , handleListStackChanges
    , handleGetStackDependencies
    , handleSubmitUpTo
    , handleCheckConflicts
    , handleResolveConflicts
    , handleSyncStack
    , handleGetStackGraph
    , handleSplitStack
    , handleMergeStacks
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad (void, forM)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime)
import Database.PostgreSQL.Simple (Connection)
import Network.HTTP.Types.Status
import Web.Yesod
import Web.Scotty.Trans

import Gerrit.Models.Stack
import Gerrit.Models.Change
import Gerrit.Models.Types
import Gerrit.VCS.Types
import Gerrit.Api.Types.Stack
import Gerrit.Api.Types
import Gerrit.Services.StackService (StackService, StackError(..))
import qualified Gerrit.Services.StackService as Stack

-- | Request types
data CreateStackRequest = CreateStackRequest
    { createName :: Text
    , createDescription :: Maybe Text
    , createProjectId :: Text
    , createBranch :: Text
    , createMetadata :: Maybe Value
    }

data UpdateStackRequest = UpdateStackRequest
    { updateName :: Text
    , updateDescription :: Maybe Text
    , updateMetadata :: Maybe Value
    }

data AddChangeRequest = AddChangeRequest
    { addChangeId :: Text
    , addDependencies :: [Text]
    }

data ReorderStackRequest = ReorderStackRequest
    { reorderChangeIds :: [Text]
    }

-- | List stacks in a project
handleListStacks :: Connection -> Text -> Handler Value
handleListStacks conn projectId = do
    stacks <- listStacks conn projectId
    return $ toJSON stacks

-- | Create a new stack
handleCreateStack :: MonadIO m
                 => StackService
                 -> ActionT Error m ()
handleCreateStack service = do
    -- Parse request
    CreateStackRequest{..} <- jsonData

    -- Get user ID from auth context
    userId <- requireUserId

    -- Create stack
    result <- Stack.createStack
        service
        createName
        createDescription
        userId
        createProjectId
        createBranch
        createMetadata

    case result of
        Left err -> do
            status badRequest400
            json $ object ["error" .= show err]
        Right stack -> do
            status created201
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= stack
                ]

-- | Get stack details
handleGetStack :: MonadIO m
               => StackService
               -> Text  -- ^ Stack ID
               -> ActionT Error m ()
handleGetStack service stackId = do
    result <- Stack.getStack service stackId
    case result of
        Left err -> do
            status notFound404
            json $ object ["error" .= show err]
        Right stack -> do
            status ok200
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= stack
                ]

-- | Update stack
handleUpdateStack :: MonadIO m
                 => StackService
                 -> Text  -- ^ Stack ID
                 -> ActionT Error m ()
handleUpdateStack service stackId = do
    -- Parse request
    UpdateStackRequest{..} <- jsonData

    -- Update stack
    result <- Stack.updateStack
        service
        stackId
        updateName
        updateDescription
        updateMetadata

    case result of
        Left err -> do
            status badRequest400
            json $ object ["error" .= show err]
        Right stack -> do
            status ok200
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= stack
                ]

-- | Delete stack
handleDeleteStack :: MonadIO m
                 => StackService
                 -> Text  -- ^ Stack ID
                 -> ActionT Error m ()
handleDeleteStack service stackId = do
    result <- Stack.deleteStack service stackId
    case result of
        Left err -> do
            status badRequest400
            json $ object ["error" .= show err]
        Right () -> do
            status ok200
            json $ object ["status" .= ("success" :: Text)]

-- | List changes in a stack
handleListStackChanges :: Connection -> Text -> Handler Value
handleListStackChanges conn stackId = do
    deps <- getStackDependencies conn stackId
    changes <- forM deps $ \dep -> do
        mChange <- getChange conn (depChildChangeId dep)
        pure $ case mChange of
            Just change -> object
                [ "change" .= change
                , "dependency" .= dep
                ]
            Nothing -> object
                [ "error" .= ("Change not found" :: Text)
                , "dependency" .= dep
                ]
    return $ toJSON changes

-- | Add change to stack
handleAddChangeToStack :: MonadIO m
                      => StackService
                      -> Text  -- ^ Stack ID
                      -> ActionT Error m ()
handleAddChangeToStack service stackId = do
    -- Parse request
    AddChangeRequest{..} <- jsonData

    -- Add change
    result <- Stack.addChangeToStack
        service
        stackId
        addChangeId
        addDependencies

    case result of
        Left err -> do
            status badRequest400
            json $ object ["error" .= show err]
        Right () -> do
            status ok200
            json $ object ["status" .= ("success" :: Text)]

-- | Remove change from stack
handleRemoveChangeFromStack :: MonadIO m
                           => StackService
                           -> Text  -- ^ Stack ID
                           -> Text  -- ^ Change ID
                           -> ActionT Error m ()
handleRemoveChangeFromStack service stackId changeId = do
    result <- Stack.removeChangeFromStack service stackId changeId
    case result of
        Left err -> do
            status badRequest400
            json $ object ["error" .= show err]
        Right () -> do
            status ok200
            json $ object ["status" .= ("success" :: Text)]

-- | Reorder changes in stack
handleReorderStack :: MonadIO m
                   => StackService
                   -> Text  -- ^ Stack ID
                   -> ActionT Error m ()
handleReorderStack service stackId = do
    -- Parse request
    ReorderStackRequest{..} <- jsonData

    -- Reorder stack
    result <- Stack.reorderStack service stackId reorderChangeIds
    case result of
        Left err -> do
            status badRequest400
            json $ object ["error" .= show err]
        Right () -> do
            status ok200
            json $ object ["status" .= ("success" :: Text)]

-- | Rebase entire stack
handleRebaseStack :: MonadIO m
                  => StackService
                  -> Text  -- ^ Stack ID
                  -> ActionT Error m ()
handleRebaseStack service stackId = do
    result <- Stack.rebaseStack service stackId
    case result of
        Left err -> do
            status badRequest400
            json $ object ["error" .= show err]
        Right () -> do
            status ok200
            json $ object ["status" .= ("success" :: Text)]

-- | Get stack dependencies
handleGetStackDependencies :: Connection -> Text -> Handler Value
handleGetStackDependencies conn stackId = do
    deps <- getStackDependencies conn stackId
    return $ toJSON deps

-- | Submit entire stack
handleSubmitStack :: MonadIO m
                  => StackService
                  -> Text  -- ^ Stack ID
                  -> ActionT Error m ()
handleSubmitStack service stackId = do
    result <- Stack.submitStack service stackId
    case result of
        Left err -> do
            status badRequest400
            json $ object ["error" .= show err]
        Right () -> do
            status ok200
            json $ object ["status" .= ("success" :: Text)]

-- | Submit stack up to specific change
handleSubmitUpTo :: Connection -> Text -> Text -> Handler Value
handleSubmitUpTo conn stackId changeId = do
    -- TODO: Implement partial stack submission logic
    return $ object ["success" .= True]

-- | Check for conflicts in stack
handleCheckConflicts :: Connection -> Text -> Handler Value
handleCheckConflicts conn stackId = do
    -- TODO: Implement conflict detection logic
    return $ object ["success" .= True]

-- | Resolve stack conflicts
handleResolveConflicts :: Connection -> Text -> Handler Value
handleResolveConflicts conn stackId = do
    -- TODO: Implement conflict resolution logic
    return $ object ["success" .= True]

-- | Sync stack with remote
handleSyncStack :: Connection -> Text -> Handler Value
handleSyncStack conn stackId = do
    -- TODO: Implement stack synchronization logic
    return $ object ["success" .= True]

-- | Get stack dependency graph
handleGetStackGraph :: Connection -> Text -> Handler Value
handleGetStackGraph conn stackId = do
    deps <- getStackDependencies conn stackId
    -- Convert dependencies to graph format
    let nodes = [] -- TODO: Create graph nodes
        edges = [] -- TODO: Create graph edges
    return $ object
        [ "nodes" .= nodes
        , "edges" .= edges
        ]

-- | Split stack at change
handleSplitStack :: Connection -> Text -> Text -> Handler Value
handleSplitStack conn stackId changeId = do
    -- TODO: Implement stack splitting logic
    return $ object ["success" .= True]

-- | Merge two stacks
handleMergeStacks :: Connection -> Text -> Text -> Handler Value
handleMergeStacks conn stackId1 stackId2 = do
    -- TODO: Implement stack merging logic
    return $ object ["success" .= True]

-- | Handler to abandon a stack
handleAbandonStack :: MonadIO m
                   => StackService
                   -> Text  -- ^ Stack ID
                   -> ActionT Error m ()
handleAbandonStack service stackId = do
    result <- Stack.abandonStack service stackId
    case result of
        Left err -> do
            status badRequest400
            json $ object ["error" .= show err]
        Right () -> do
            status ok200
            json $ object ["status" .= ("success" :: Text)]

-- Helper functions

generateId :: Text -> Text
generateId prefix = undefined  -- TODO: Implement ID generation
