-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers
    ( createProject
    , getProject
    , listProjects
    , createChange
    , getChange
    , listChanges
    , listRevisions
    , reviewChange
    , submitChange
    , createComment
    , listComments
    ) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import Data.Text (Text)
import Data.Time (getCurrentTime)
import Database.Persist
import Servant

import Gerrit.Api.Types
import Gerrit.Models.Types
import Gerrit.Database.Connection (runDB)
import qualified Gerrit.Git.Operations as Git

-- | Create a new project
createProject :: Maybe Text -> CreateProjectRequest -> App Text
createProject Nothing _ = throwError err401
createProject (Just token) CreateProjectRequest{..} = do
    -- Verify token and get user
    user <- authenticateToken token

    -- Initialize Git repository
    gitPath <- asks configGitBasePath
    result <- liftIO $ Git.initRepository gitPath cprName
    case result of
        Left err -> throwError err500 { errBody = "Git error: " <> show err }
        Right _ -> do
            -- Create project in database
            now <- liftIO getCurrentTime
            projectId <- runDB configPool $ insert Project
                { projectName = cprName
                , projectDescription = cprDescription
                , projectOwnerUserId = userToKey user
                , projectCreatedAt = now
                }
            return $ keyToText projectId

-- | Get project information
getProject :: Maybe Text -> Text -> App ProjectInfo
getProject Nothing _ = throwError err401
getProject (Just token) projectName = do
    -- Verify token
    _ <- authenticateToken token

    -- Get project from database
    project <- runDB configPool $ getBy $ UniqueProjectName projectName
    case project of
        Nothing -> throwError err404
        Just (Entity _ Project{..}) -> do
            owner <- runDB configPool $ get404 projectOwnerUserId
            return $ ProjectInfo
                { piName = projectName
                , piDescription = projectDescription
                , piOwner = userToInfo owner
                , piCreatedAt = projectCreatedAt
                }

-- | List all projects
listProjects :: Maybe Text -> App [ProjectInfo]
listProjects Nothing = throwError err401
listProjects (Just token) = do
    -- Verify token
    _ <- authenticateToken token

    -- Get all projects from database
    projects <- runDB configPool $ selectList [] []
    mapM entityToProjectInfo projects

-- | Create a new change
createChange :: Maybe Text -> CreateChangeRequest -> App ChangeInfo
createChange Nothing _ = throwError err401
createChange (Just token) CreateChangeRequest{..} = do
    -- Verify token and get user
    user <- authenticateToken token

    -- Get project
    project <- runDB configPool $ getBy404 $ UniqueProjectName ccrProject

    -- Create change in Git
    gitPath <- asks configGitBasePath
    now <- liftIO getCurrentTime
    changeId <- generateChangeId

    result <- liftIO $ Git.createChange (gitPath </> ccrProject) changeId ccrBranch
    case result of
        Left err -> throwError err500 { errBody = "Git error: " <> show err }
        Right _ -> do
            -- Create change in database
            changeId <- runDB configPool $ insert Change
                { changeProjectId = entityKey project
                , changeBranch = ccrBranch
                , changeSubject = ccrSubject
                , changeMessage = ccrMessage
                , changeAuthorId = userToKey user
                , changeStatus = Draft
                , changeCreatedAt = now
                , changeUpdatedAt = now
                }
            change <- runDB configPool $ get404 changeId
            changeToInfo change user Nothing

-- Helper functions

-- | Convert a User entity to UserInfo
userToInfo :: User -> UserInfo
userToInfo User{..} = UserInfo
    { uiId = keyToText $ UserKey userEmail
    , uiEmail = userEmail
    , uiName = userName
    }

-- | Convert a Change entity to ChangeInfo
changeToInfo :: Change -> User -> Maybe Revision -> ChangeInfo
changeToInfo Change{..} author mRevision = ChangeInfo
    { ciId = keyToText changeId
    , ciProject = projectName
    , ciBranch = changeBranch
    , ciSubject = changeSubject
    , ciMessage = changeMessage
    , ciAuthor = userToInfo author
    , ciStatus = changeStatus
    , ciCreatedAt = changeCreatedAt
    , ciUpdatedAt = changeUpdatedAt
    , ciCurrentRevision = revisionToInfo <$> mRevision
    }

-- | Convert a Revision entity to RevisionInfo
revisionToInfo :: (Revision, User) -> RevisionInfo
revisionToInfo (Revision{..}, author) = RevisionInfo
    { riNumber = revisionNumber
    , riCommitHash = revisionCommitHash
    , riParentHash = revisionParentHash
    , riAuthor = userToInfo author
    , riCreatedAt = revisionCreatedAt
    }

-- | Convert an entity to ProjectInfo
entityToProjectInfo :: Entity Project -> App ProjectInfo
entityToProjectInfo (Entity _ project) = do
    owner <- runDB configPool $ get404 $ projectOwnerUserId project
    return $ ProjectInfo
        { piName = projectName project
        , piDescription = projectDescription project
        , piOwner = userToInfo owner
        , piCreatedAt = projectCreatedAt project
        }

-- | Authenticate a token and return the user
authenticateToken :: Text -> App User
authenticateToken token = do
    -- In a real implementation, this would verify the JWT token
    -- and look up the user in the database
    throwError err500 { errBody = "Authentication not implemented" }

-- | Generate a unique change ID
generateChangeId :: App Text
generateChangeId = do
    -- In a real implementation, this would generate a unique ID
    -- using UUID or similar
    throwError err500 { errBody = "Change ID generation not implemented" }

-- Remaining handler stubs (to be implemented)

listChanges :: Maybe Text -> App [ChangeInfo]
listChanges = undefined

getChange :: Maybe Text -> Text -> App ChangeInfo
getChange = undefined

listRevisions :: Maybe Text -> Text -> App [RevisionInfo]
listRevisions = undefined

reviewChange :: Maybe Text -> Text -> ReviewInput -> App ()
reviewChange = undefined

submitChange :: Maybe Text -> Text -> App ()
submitChange = undefined

createComment :: Text -> Text -> Maybe Text -> CommentInput -> App ()
createComment = undefined

listComments :: Text -> Text -> Maybe Text -> App [CommentInfo]
listComments = undefined
