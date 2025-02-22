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
import Gerrit.Models.Change
import Gerrit.Models.Comment
import Gerrit.Models.Revision
import Gerrit.Models.Vote

-- | Default database path
defaultDbPath :: FilePath
defaultDbPath = "/var/lib/gerrit/gerrit.db"

-- | Convert a Change to a ChangeResponse
toChangeResponse :: Change -> Maybe RevisionResponse -> ChangeResponse
toChangeResponse change mRevision = ChangeResponse
    { changeId = changeId change
    , projectId = projectId change
    , branch = branch change
    , subject = subject change
    , description = description change
    , ownerId = ownerId change
    , status = status change
    , created = created change
    , updated = updated change
    , currentRevision = mRevision
    }

-- | Convert a Revision to a RevisionResponse
toRevisionResponse :: Revision -> RevisionResponse
toRevisionResponse revision = RevisionResponse
    { revisionId = revisionId revision
    , changeId = changeId revision
    , number = number revision
    , commitId = commitId revision
    , uploaderId = uploaderId revision
    , description = description revision
    , created = created revision
    }

-- | Convert a Comment to a CommentResponse
toCommentResponse :: Comment -> CommentResponse
toCommentResponse comment = CommentResponse
    { commentId = commentId comment
    , revisionId = revisionId comment
    , authorId = authorId comment
    , commentType = commentType comment
    , file = file comment
    , line = line comment
    , message = message comment
    , resolved = resolved comment
    , created = created comment
    , updated = updated comment
    }

-- | Convert a Vote to a VoteResponse
toVoteResponse :: Vote -> VoteResponse
toVoteResponse vote = VoteResponse
    { voteId = voteId vote
    , revisionId = revisionId vote
    , reviewerId = reviewerId vote
    , label = label vote
    , value = value vote
    , message = message vote
    , created = created vote
    , updated = updated vote
    }

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

-- | List all changes
listChanges :: Maybe Text -> App [ChangeInfo]
listChanges Nothing = throwError err401
listChanges (Just token) = do
    -- Verify token
    _ <- authenticateToken token

    -- Get all changes from database
    changes <- runDB configPool $ selectList [] [Desc ChangeCreatedAt]
    forM changes $ \(Entity changeId change) -> do
        author <- runDB configPool $ get404 $ changeAuthorId change
        mCurrentRevision <- runDB configPool $ selectFirst
            [RevisionChangeId ==. changeId]
            [Desc RevisionNumber]
        mRevisionWithAuthor <- forM mCurrentRevision $ \(Entity _ revision) -> do
            revAuthor <- runDB configPool $ get404 $ revisionAuthorId revision
            return (revision, revAuthor)
        return $ changeToInfo change author mRevisionWithAuthor

-- | Get a specific change
getChange :: Maybe Text -> Text -> App ChangeInfo
getChange Nothing _ = throwError err401
getChange (Just token) changeIdText = do
    -- Verify token
    _ <- authenticateToken token

    -- Parse change ID
    changeId <- maybe (throwError err400) return $ fromPathPiece changeIdText

    -- Get change from database
    change <- runDB configPool $ get404 changeId
    author <- runDB configPool $ get404 $ changeAuthorId change
    mCurrentRevision <- runDB configPool $ selectFirst
        [RevisionChangeId ==. changeId]
        [Desc RevisionNumber]
    mRevisionWithAuthor <- forM mCurrentRevision $ \(Entity _ revision) -> do
        revAuthor <- runDB configPool $ get404 $ revisionAuthorId revision
        return (revision, revAuthor)
    return $ changeToInfo change author mRevisionWithAuthor

-- | List all revisions for a change
listRevisions :: Maybe Text -> Text -> App [RevisionInfo]
listRevisions Nothing _ = throwError err401
listRevisions (Just token) changeIdText = do
    -- Verify token
    _ <- authenticateToken token

    -- Parse change ID
    changeId <- maybe (throwError err400) return $ fromPathPiece changeIdText

    -- Get revisions from database
    revisions <- runDB configPool $ selectList
        [RevisionChangeId ==. changeId]
        [Asc RevisionNumber]
    forM revisions $ \(Entity _ revision) -> do
        author <- runDB configPool $ get404 $ revisionAuthorId revision
        return $ revisionToInfo (revision, author)

-- | Review a change
reviewChange :: Maybe Text -> Text -> ReviewInput -> App ()
reviewChange Nothing _ _ = throwError err401
reviewChange (Just token) changeIdText ReviewInput{..} = do
    -- Verify token and get user
    reviewer <- authenticateToken token

    -- Parse change ID
    changeId <- maybe (throwError err400) return $ fromPathPiece changeIdText

    -- Get change
    change <- runDB configPool $ get404 changeId

    -- Check if user has review permissions
    hasPermission <- runDB configPool $ exists [
        PermissionProjectId ==. changeProjectId change,
        PermissionUserId ==. userToKey reviewer,
        PermissionCanReview ==. True]
    unless hasPermission $ throwError err403

    -- Create review
    now <- liftIO getCurrentTime
    _ <- runDB configPool $ insert Review
        { reviewChangeId = changeId
        , reviewReviewerId = userToKey reviewer
        , reviewVote = riVote
        , reviewMessage = riMessage
        , reviewCreatedAt = now
        }

    -- Update change status if necessary
    when (riVote == PlusTwo) $ do
        runDB configPool $ update changeId [ChangeStatus =. Approved]

    when (riVote == MinusTwo) $ do
        runDB configPool $ update changeId [ChangeStatus =. Rejected]

-- | Submit a change
submitChange :: Maybe Text -> Text -> App ()
submitChange Nothing _ = throwError err401
submitChange (Just token) changeIdText = do
    -- Verify token and get user
    user <- authenticateToken token

    -- Parse change ID
    changeId <- maybe (throwError err400) return $ fromPathPiece changeIdText

    -- Get change
    change <- runDB configPool $ get404 changeId

    -- Check if user has submit permissions
    hasPermission <- runDB configPool $ exists [
        PermissionProjectId ==. changeProjectId change,
        PermissionUserId ==. userToKey user,
        PermissionCanSubmit ==. True]
    unless hasPermission $ throwError err403

    -- Check if change is approved
    unless (changeStatus change == Approved) $
        throwError err400 { errBody = "Change must be approved before submitting" }

    -- Get project and latest revision
    project <- runDB configPool $ get404 $ changeProjectId change
    mRevision <- runDB configPool $ selectFirst
        [RevisionChangeId ==. changeId]
        [Desc RevisionNumber]
    revision <- maybe (throwError err500) (return . entityVal) mRevision

    -- Merge change in Git
    gitPath <- asks configGitBasePath
    let repo = gitPath </> unpack (projectName project)
    result <- liftIO $ Git.mergeChange repo
        ("changes/" <> changeBranch change)
        "master"
    case result of
        Left err -> throwError err500 { errBody = "Git error: " <> show err }
        Right _ -> return ()

-- | Create a comment on a revision
createComment :: Text -> Text -> Maybe Text -> CommentInput -> App ()
createComment changeIdText revisionIdText Nothing _ = throwError err401
createComment changeIdText revisionIdText (Just token) CommentInput{..} = do
    -- Verify token and get user
    author <- authenticateToken token

    -- Parse IDs
    changeId <- maybe (throwError err400) return $ fromPathPiece changeIdText
    revisionId <- maybe (throwError err400) return $ fromPathPiece revisionIdText

    -- Check if revision exists and belongs to change
    revision <- runDB configPool $ get404 revisionId
    unless (revisionChangeId revision == changeId) $
        throwError err400 { errBody = "Revision does not belong to change" }

    -- Create comment
    now <- liftIO getCurrentTime
    _ <- runDB configPool $ insert Comment
        { commentRevisionId = revisionId
        , commentAuthorId = userToKey author
        , commentLineNumber = ciLineNumber
        , commentFilePath = ciFilePath
        , commentMessage = ciMessage
        , commentCreatedAt = now
        }
    return ()

-- | List comments for a revision
listComments :: Text -> Text -> Maybe Text -> App [CommentInfo]
listComments changeIdText revisionIdText Nothing = throwError err401
listComments changeIdText revisionIdText (Just token) = do
    -- Verify token
    _ <- authenticateToken token

    -- Parse IDs
    changeId <- maybe (throwError err400) return $ fromPathPiece changeIdText
    revisionId <- maybe (throwError err400) return $ fromPathPiece revisionIdText

    -- Check if revision exists and belongs to change
    revision <- runDB configPool $ get404 revisionId
    unless (revisionChangeId revision == changeId) $
        throwError err400 { errBody = "Revision does not belong to change" }

    -- Get comments
    comments <- runDB configPool $ selectList
        [CommentRevisionId ==. revisionId]
        [Asc CommentCreatedAt]
    forM comments $ \(Entity commentId comment) -> do
        author <- runDB configPool $ get404 $ commentAuthorId comment
        return CommentInfo
            { cmId = keyToText commentId
            , cmAuthor = userToInfo author
            , cmFilePath = commentFilePath comment
            , cmLineNumber = commentLineNumber comment
            , cmMessage = commentMessage comment
            , cmCreatedAt = commentCreatedAt comment
            }

-- | Change handlers

-- | List changes with pagination
handleListChanges :: Maybe Int -> Maybe Int -> Handler (Response [ChangeResponse])
handleListChanges mOffset mLimit = do
    let offset = fromMaybe 0 mOffset
    let limit = fromMaybe 50 mLimit
    changes <- liftIO $ listChanges' defaultDbPath offset limit
    responses <- mapM addLatestRevision changes
    pure $ Response True Nothing responses
  where
    addLatestRevision change = do
        mRevision <- liftIO $ getLatestRevision' defaultDbPath (changeId change)
        pure $ toChangeResponse change (toRevisionResponse <$> mRevision)

-- | Create a new change
handleCreateChange :: CreateChangeRequest -> Handler (Response ChangeResponse)
handleCreateChange req = do
    -- TODO: Get owner ID from auth context
    let ownerId = "current-user"  -- Placeholder
    change <- liftIO $ createChange defaultDbPath
        (projectId req)
        (branch req)
        (subject req)
        (description req)
        ownerId
    pure $ Response True Nothing (toChangeResponse change Nothing)

-- | Get a specific change
handleGetChange :: Text -> Handler (Response ChangeResponse)
handleGetChange changeId' = do
    mChange <- liftIO $ getChangeById defaultDbPath changeId'
    case mChange of
        Nothing -> throwError err404
        Just change -> do
            mRevision <- liftIO $ getLatestRevision' defaultDbPath changeId'
            pure $ Response True Nothing (toChangeResponse change (toRevisionResponse <$> mRevision))

-- | Update change status
handleUpdateChangeStatus :: Text -> ChangeStatus -> Handler (Response ChangeResponse)
handleUpdateChangeStatus changeId' newStatus = do
    mChange <- liftIO $ getChangeById defaultDbPath changeId'
    case mChange of
        Nothing -> throwError err404
        Just change -> do
            updatedChange <- liftIO $ updateChangeStatus defaultDbPath change newStatus
            mRevision <- liftIO $ getLatestRevision' defaultDbPath changeId'
            pure $ Response True Nothing (toChangeResponse updatedChange (toRevisionResponse <$> mRevision))

-- | Revision handlers

-- | List revisions for a change
handleListRevisions :: Text -> Handler (Response [RevisionResponse])
handleListRevisions changeId' = do
    revisions <- liftIO $ getChangeRevisions' defaultDbPath changeId'
    pure $ Response True Nothing (map toRevisionResponse revisions)

-- | Create a new revision
handleCreateRevision :: Text -> CreateRevisionRequest -> Handler (Response RevisionResponse)
handleCreateRevision changeId' req = do
    -- TODO: Get uploader ID from auth context
    let uploaderId = "current-user"  -- Placeholder
    revision <- liftIO $ createRevision defaultDbPath
        changeId'
        (commitId req)
        uploaderId
        (description req)
    pure $ Response True Nothing (toRevisionResponse revision)

-- | Get a specific revision
handleGetRevision :: Text -> Text -> Handler (Response RevisionResponse)
handleGetRevision _ revisionId' = do
    mRevision <- liftIO $ getRevision' defaultDbPath revisionId'
    case mRevision of
        Nothing -> throwError err404
        Just revision -> pure $ Response True Nothing (toRevisionResponse revision)

-- | Comment handlers

-- | List comments for a revision
handleListComments :: Text -> Text -> Handler (Response [CommentResponse])
handleListComments _ revisionId' = do
    comments <- liftIO $ getRevisionComments defaultDbPath revisionId'
    pure $ Response True Nothing (map toCommentResponse comments)

-- | Create a new comment
handleCreateComment :: Text -> Text -> CreateCommentRequest -> Handler (Response CommentResponse)
handleCreateComment _ revisionId' req = do
    -- TODO: Get author ID from auth context
    let authorId = "current-user"  -- Placeholder
    comment <- liftIO $ createComment defaultDbPath
        revisionId'
        authorId
        (commentType req)
        (file req)
        (line req)
        (message req)
    pure $ Response True Nothing (toCommentResponse comment)

-- | Get a specific comment
handleGetComment :: Text -> Text -> Text -> Handler (Response CommentResponse)
handleGetComment _ _ commentId' = do
    mComment <- liftIO $ getCommentById defaultDbPath commentId'
    case mComment of
        Nothing -> throwError err404
        Just comment -> pure $ Response True Nothing (toCommentResponse comment)

-- | Update comment resolved status
handleUpdateCommentResolved :: Text -> Text -> Text -> Bool -> Handler (Response CommentResponse)
handleUpdateCommentResolved _ _ commentId' resolved' = do
    mComment <- liftIO $ getCommentById defaultDbPath commentId'
    case mComment of
        Nothing -> throwError err404
        Just comment -> do
            updatedComment <- liftIO $ updateCommentResolved defaultDbPath comment resolved'
            pure $ Response True Nothing (toCommentResponse updatedComment)

-- | Get file comments
handleGetFileComments :: Text -> Text -> Text -> Handler (Response [CommentResponse])
handleGetFileComments _ revisionId' file' = do
    comments <- liftIO $ getFileComments defaultDbPath revisionId' file'
    pure $ Response True Nothing (map toCommentResponse comments)

-- | Vote handlers

-- | List votes for a revision
handleListVotes :: Text -> Text -> Handler (Response [VoteResponse])
handleListVotes _ revisionId' = do
    votes <- liftIO $ getRevisionVotes defaultDbPath revisionId'
    pure $ Response True Nothing (map toVoteResponse votes)

-- | Create/Update a vote
handleCreateVote :: Text -> Text -> CreateVoteRequest -> Handler (Response VoteResponse)
handleCreateVote _ revisionId' req = do
    -- TODO: Get reviewer ID from auth context
    let reviewerId = "current-user"  -- Placeholder
    vote <- liftIO $ createVote defaultDbPath
        revisionId'
        reviewerId
        (label req)
        (value req)
        (message req)
    pure $ Response True Nothing (toVoteResponse vote)

-- | Get votes by reviewer
handleGetReviewerVotes :: Text -> Text -> Text -> Handler (Response [VoteResponse])
handleGetReviewerVotes _ revisionId' reviewerId' = do
    votes <- liftIO $ getReviewerVotes defaultDbPath revisionId' reviewerId'
    pure $ Response True Nothing (map toVoteResponse votes)

-- | Get votes by label
handleGetLabelVotes :: Text -> Text -> VoteLabel -> Handler (Response [VoteResponse])
handleGetLabelVotes _ revisionId' label' = do
    votes <- liftIO $ getLabelVotes defaultDbPath revisionId' label'
    pure $ Response True Nothing (map toVoteResponse votes)

-- | Check if revision can be submitted
handleCheckSubmit :: Text -> Text -> Handler (Response Bool)
handleCheckSubmit _ revisionId' = do
    canSubmit <- liftIO $ canSubmitRevision defaultDbPath revisionId'
    pure $ Response True Nothing canSubmit
