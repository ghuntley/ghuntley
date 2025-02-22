-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.StackService
    ( -- * Types
      StackService(..)
    , StackError(..)
      -- * Service operations
    , initStackService
    , createStack
    , updateStack
    , deleteStack
    , getStack
    , listStacks
    , addChangeToStack
    , removeChangeFromStack
    , reorderStack
    , rebaseStack
    , submitStack
    , abandonStack
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (getCurrentTime)

import Gerrit.Models.ChangeStack
import Gerrit.Models.StackDependency
import Gerrit.Models.StackState
import Gerrit.Services.GitService (GitService)
import qualified Gerrit.Services.GitService as Git
import Gerrit.Services.NotificationService (NotificationService)
import qualified Gerrit.Services.NotificationService as Notification
import Gerrit.Services.MetricsService (MetricsService)
import qualified Gerrit.Services.MetricsService as Metrics

-- | Stack service errors
data StackError
    = StackNotFound Text
    | ChangeNotFound Text
    | InvalidDependency Text
    | CyclicDependency Text
    | RebaseConflict Text
    | SubmitError Text
    | DatabaseError Text
    deriving (Show, Eq)

-- | Stack service
data StackService = StackService
    { stackGitService :: GitService
    , stackNotificationService :: NotificationService
    , stackMetricsService :: MetricsService
    }

-- | Initialize stack service
initStackService :: MonadIO m
                => GitService
                -> NotificationService
                -> MetricsService
                -> m StackService
initStackService gitService notificationService metricsService =
    return StackService
        { stackGitService = gitService
        , stackNotificationService = notificationService
        , stackMetricsService = metricsService
        }

-- | Create a new stack
createStack :: MonadIO m
            => StackService
            -> Text  -- ^ Name
            -> Maybe Text  -- ^ Description
            -> Text  -- ^ Owner ID
            -> Text  -- ^ Project ID
            -> Text  -- ^ Branch
            -> Maybe Value  -- ^ Additional metadata
            -> m (Either StackError (Entity ChangeStack))
createStack service name desc ownerId projectId branch metadata = do
    -- Record metrics
    Metrics.incrementCounter
        (stackMetricsService service)
        "stack_create_total"
        [("project", projectId)]

    -- Create stack
    result <- runDB $ createStack name desc ownerId projectId branch metadata
    case result of
        Left err -> do
            Metrics.incrementCounter
                (stackMetricsService service)
                "stack_create_error_total"
                [("project", projectId), ("error", "database_error")]
            return $ Left $ DatabaseError $ Text.pack $ show err
        Right stack -> do
            -- Send notification
            Notification.sendNotification
                (stackNotificationService service)
                "stack_created"
                (entityKey stack)
                ownerId
            return $ Right stack

-- | Update stack details
updateStack :: MonadIO m
            => StackService
            -> Text  -- ^ Stack ID
            -> Text  -- ^ New name
            -> Maybe Text  -- ^ New description
            -> Maybe Value  -- ^ New metadata
            -> m (Either StackError (Entity ChangeStack))
updateStack service stackId name desc metadata = do
    -- Get existing stack
    mStack <- runDB $ getStackById stackId
    case mStack of
        Nothing -> return $ Left $ StackNotFound stackId
        Just stack@(Entity key _) -> do
            -- Update stack
            now <- liftIO getCurrentTime
            let updatedStack = stack
                    { changeStackName = name
                    , changeStackDescription = desc
                    , changeStackMetadata = metadata
                    , changeStackUpdated = now
                    }
            runDB $ replace key updatedStack
            return $ Right $ Entity key updatedStack

-- | Delete a stack
deleteStack :: MonadIO m
            => StackService
            -> Text  -- ^ Stack ID
            -> m (Either StackError ())
deleteStack service stackId = do
    -- Get existing stack
    mStack <- runDB $ getStackById stackId
    case mStack of
        Nothing -> return $ Left $ StackNotFound stackId
        Just (Entity _ stack) -> do
            -- Delete dependencies
            runDB $ deleteWhere [StackDependencyStackId ==. stackId]
            -- Delete stack
            runDB $ deleteBy $ UniqueStackId stackId
            -- Record metrics
            Metrics.incrementCounter
                (stackMetricsService service)
                "stack_delete_total"
                [("project", changeStackProjectId stack)]
            return $ Right ()

-- | Get stack by ID
getStack :: MonadIO m
         => StackService
         -> Text  -- ^ Stack ID
         -> m (Either StackError (Entity ChangeStack))
getStack _ stackId = do
    mStack <- runDB $ getStackById stackId
    return $ case mStack of
        Nothing -> Left $ StackNotFound stackId
        Just stack -> Right stack

-- | List stacks with filtering
listStacks :: MonadIO m
           => StackService
           -> Maybe Text  -- ^ Owner ID
           -> Maybe Text  -- ^ Project ID
           -> Maybe StackStatus  -- ^ Status
           -> Int  -- ^ Offset
           -> Int  -- ^ Limit
           -> m [Entity ChangeStack]
listStacks _ = runDB . listStacks

-- | Add a change to a stack
addChangeToStack :: MonadIO m
                => StackService
                -> Text  -- ^ Stack ID
                -> Text  -- ^ Change ID
                -> [Text]  -- ^ Dependencies (change IDs)
                -> m (Either StackError ())
addChangeToStack service stackId changeId deps = do
    -- Validate stack exists
    mStack <- runDB $ getStackById stackId
    case mStack of
        Nothing -> return $ Left $ StackNotFound stackId
        Just (Entity _ stack) -> do
            -- Validate dependencies
            let addDeps = mapM_ (\depId -> createDependency
                    stackId
                    changeId
                    depId
                    DirectDependency
                    0  -- Position will be updated by reorderDependencies
                    ) deps
            result <- runDB $ do
                addDeps
                validateDependencies stackId
            case result of
                Left err -> return $ Left $ CyclicDependency err
                Right _ -> do
                    -- Update positions
                    changes <- getStackChanges stackId
                    reorderDependencies stackId changes
                    -- Record metrics
                    Metrics.incrementCounter
                        (stackMetricsService service)
                        "stack_change_add_total"
                        [("project", changeStackProjectId stack)]
                    return $ Right ()

-- | Remove a change from a stack
removeChangeFromStack :: MonadIO m
                     => StackService
                     -> Text  -- ^ Stack ID
                     -> Text  -- ^ Change ID
                     -> m (Either StackError ())
removeChangeFromStack service stackId changeId = do
    -- Validate stack exists
    mStack <- runDB $ getStackById stackId
    case mStack of
        Nothing -> return $ Left $ StackNotFound stackId
        Just (Entity _ stack) -> do
            -- Remove dependencies
            runDB $ do
                deleteWhere
                    [ StackDependencyStackId ==. stackId
                    , StackDependencyChangeId ==. changeId
                    ]
                deleteWhere
                    [ StackDependencyStackId ==. stackId
                    , StackDependencyDependsOnId ==. changeId
                    ]
            -- Record metrics
            Metrics.incrementCounter
                (stackMetricsService service)
                "stack_change_remove_total"
                [("project", changeStackProjectId stack)]
            return $ Right ()

-- | Reorder changes in a stack
reorderStack :: MonadIO m
             => StackService
             -> Text  -- ^ Stack ID
             -> [Text]  -- ^ Ordered list of change IDs
             -> m (Either StackError ())
reorderStack service stackId changeIds = do
    -- Validate stack exists
    mStack <- runDB $ getStackById stackId
    case mStack of
        Nothing -> return $ Left $ StackNotFound stackId
        Just (Entity _ stack) -> do
            -- Update positions
            reorderDependencies stackId changeIds
            -- Record metrics
            Metrics.incrementCounter
                (stackMetricsService service)
                "stack_reorder_total"
                [("project", changeStackProjectId stack)]
            return $ Right ()

-- | Rebase a stack
rebaseStack :: MonadIO m
            => StackService
            -> Text  -- ^ Stack ID
            -> m (Either StackError ())
rebaseStack service stackId = do
    -- Validate stack exists
    mStack <- runDB $ getStackById stackId
    case mStack of
        Nothing -> return $ Left $ StackNotFound stackId
        Just (Entity _ stack) -> do
            -- Get ordered changes
            changes <- getStackChanges stackId
            -- Rebase each change
            result <- mapM (Git.rebaseChange (stackGitService service)) changes
            case sequence result of
                Left err -> do
                    Metrics.incrementCounter
                        (stackMetricsService service)
                        "stack_rebase_error_total"
                        [("project", changeStackProjectId stack)]
                    return $ Left $ RebaseConflict err
                Right _ -> do
                    Metrics.incrementCounter
                        (stackMetricsService service)
                        "stack_rebase_total"
                        [("project", changeStackProjectId stack)]
                    return $ Right ()

-- | Submit a stack
submitStack :: MonadIO m
            => StackService
            -> Text  -- ^ Stack ID
            -> m (Either StackError ())
submitStack service stackId = do
    -- Validate stack exists
    mStack <- runDB $ getStackById stackId
    case mStack of
        Nothing -> return $ Left $ StackNotFound stackId
        Just (Entity _ stack) -> do
            -- Update status
            updateStackStatus stackId StackSubmitting
            -- Get ordered changes
            changes <- getStackChanges stackId
            -- Submit each change
            result <- mapM (Git.submitChange (stackGitService service)) changes
            case sequence result of
                Left err -> do
                    -- Revert status
                    updateStackStatus stackId StackReady
                    Metrics.incrementCounter
                        (stackMetricsService service)
                        "stack_submit_error_total"
                        [("project", changeStackProjectId stack)]
                    return $ Left $ SubmitError err
                Right _ -> do
                    -- Update status
                    updateStackStatus stackId StackSubmitted
                    Metrics.incrementCounter
                        (stackMetricsService service)
                        "stack_submit_total"
                        [("project", changeStackProjectId stack)]
                    return $ Right ()

-- | Abandon a stack
abandonStack :: MonadIO m
             => StackService
             -> Text  -- ^ Stack ID
             -> m (Either StackError ())
abandonStack service stackId = do
    -- Validate stack exists
    mStack <- runDB $ getStackById stackId
    case mStack of
        Nothing -> return $ Left $ StackNotFound stackId
        Just (Entity _ stack) -> do
            -- Update status
            updateStackStatus stackId StackAbandoned
            -- Record metrics
            Metrics.incrementCounter
                (stackMetricsService service)
                "stack_abandon_total"
                [("project", changeStackProjectId stack)]
            return $ Right ()
