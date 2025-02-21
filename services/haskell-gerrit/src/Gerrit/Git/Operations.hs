-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Git.Operations
    ( initRepository
    , createChange
    , updateChange
    , fetchChange
    , mergeChange
    , GitError(..)
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Except (ExceptT, throwError, runExceptT)
import Data.Text (Text)
import qualified Data.Text as T
import System.Git.Simple
import System.FilePath ((</>))
import System.Directory (createDirectoryIfMissing)

-- | Possible Git operation errors
data GitError
    = RepositoryNotFound Text
    | BranchNotFound Text
    | CommitError Text
    | MergeConflict Text
    | InvalidReference Text
    | GitCommandError Text
    deriving (Show, Eq)

-- | Initialize a new Git repository for a project
initRepository :: MonadIO m => FilePath -> Text -> ExceptT GitError m Repository
initRepository baseDir projectName = do
    let repoPath = baseDir </> T.unpack projectName
    liftIO $ createDirectoryIfMissing True repoPath
    repo <- liftIO $ initGitRepository repoPath
    -- Initialize with empty commit to establish master branch
    withRepository repo $ do
        void $ git ["commit", "--allow-empty", "-m", "Initial commit"]
        git ["checkout", "-b", "master"]
    return repo

-- | Create a new change (branch) from master
createChange :: MonadIO m
             => Repository
             -> Text  -- ^ Change ID
             -> Text  -- ^ Branch name
             -> ExceptT GitError m ()
createChange repo changeId branchName = do
    withRepository repo $ do
        -- Ensure we're on master and it's up to date
        git ["checkout", "master"]
        git ["pull", "origin", "master"]

        -- Create new branch for the change
        let changeBranch = "changes/" <> branchName
        git ["checkout", "-b", changeBranch]

        -- Add change ID to commit message template
        let changeIdMsg = "Change-Id: " <> changeId
        liftIO $ writeFile (repoPath repo </> ".git" </> "hooks" </> "commit-msg") changeIdMsg

-- | Update an existing change with new commits
updateChange :: MonadIO m
             => Repository
             -> Text  -- ^ Branch name
             -> ExceptT GitError m ()
updateChange repo branchName = do
    withRepository repo $ do
        let changeBranch = "changes/" <> branchName
        exists <- doesBranchExist changeBranch
        unless exists $ throwError $ BranchNotFound branchName
        git ["checkout", changeBranch]

-- | Fetch a change from remote
fetchChange :: MonadIO m
            => Repository
            -> Text  -- ^ Change reference
            -> ExceptT GitError m ()
fetchChange repo changeRef = do
    withRepository repo $ do
        git ["fetch", "origin", changeRef]

-- | Merge a change into the target branch (usually master)
mergeChange :: MonadIO m
            => Repository
            -> Text  -- ^ Source branch
            -> Text  -- ^ Target branch
            -> ExceptT GitError m ()
mergeChange repo sourceBranch targetBranch = do
    withRepository repo $ do
        -- Switch to target branch
        git ["checkout", targetBranch]

        -- Try to merge
        result <- runExceptT $ git ["merge", "--no-ff", sourceBranch]
        case result of
            Left err -> throwError $ MergeConflict $ T.pack $ show err
            Right _ -> return ()

-- Helper functions

-- | Check if a branch exists
doesBranchExist :: MonadIO m => Text -> m Bool
doesBranchExist branch = do
    result <- runExceptT $ git ["rev-parse", "--verify", branch]
    return $ case result of
        Left _ -> False
        Right _ -> True

-- | Run a Git command and handle errors
git :: MonadIO m => [Text] -> ExceptT GitError m Text
git args = do
    result <- liftIO $ runGit args
    case result of
        Left err -> throwError $ GitCommandError $ T.pack $ show err
        Right output -> return output
