{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Comment
    ( -- * Handlers
      handleCreateComment
    , handleUpdateComment
    , handleGetComment
    , handleListComments
    , handleResolveComment
    , handleUnresolveComment
    , handleDeleteComment
    , handleGetFileComments
    , handleGetThreadComments
    ) where

import Control.Monad.IO.Class (MonadIO)
import Data.Aeson
import Data.Text (Text)
import Web.Scotty.Trans

import Gerrit.Api.Error
import Gerrit.Models.Comment
import Gerrit.Services.CommentService

-- | Request body for creating a comment
data CreateCommentRequest = CreateCommentRequest
    { createRevisionId :: Text
    , createMessage :: Text
    , createCommentType :: CommentType
    , createFilePath :: Maybe Text
    , createLineNumber :: Maybe Int
    } deriving (Show)

instance FromJSON CreateCommentRequest where
    parseJSON = withObject "CreateCommentRequest" $ \v -> CreateCommentRequest
        <$> v .: "revision_id"
        <*> v .: "message"
        <*> v .: "comment_type"
        <*> v .:? "file_path"
        <*> v .:? "line_number"

-- | Request body for updating a comment
data UpdateCommentRequest = UpdateCommentRequest
    { updateMessage :: Text
    } deriving (Show)

instance FromJSON UpdateCommentRequest where
    parseJSON = withObject "UpdateCommentRequest" $ \v -> UpdateCommentRequest
        <$> v .: "message"

-- | Handle creating a new comment
handleCreateComment :: MonadIO m
                   => CommentService
                   -> ActionT ApiError m ()
handleCreateComment service = do
    userId <- requireUserId
    CreateCommentRequest{..} <- jsonData
    result <- lift $ createComment service
        createRevisionId
        userId
        createMessage
        createCommentType
        createFilePath
        createLineNumber
    case result of
        Left err -> handleCommentError err
        Right comment -> json comment

-- | Handle updating a comment
handleUpdateComment :: MonadIO m
                   => CommentService
                   -> Text  -- ^ Comment ID
                   -> ActionT ApiError m ()
handleUpdateComment service commentId = do
    UpdateCommentRequest{..} <- jsonData
    result <- lift $ updateComment service commentId updateMessage
    case result of
        Left err -> handleCommentError err
        Right comment -> json comment

-- | Handle getting a comment
handleGetComment :: MonadIO m
                => CommentService
                -> Text  -- ^ Comment ID
                -> ActionT ApiError m ()
handleGetComment service commentId = do
    result <- lift $ getComment service commentId
    case result of
        Left err -> handleCommentError err
        Right comment -> json comment

-- | Handle listing comments for a revision
handleListComments :: MonadIO m
                  => CommentService
                  -> ActionT ApiError m ()
handleListComments service = do
    revisionId <- param "revision_id"
    result <- lift $ listComments service revisionId
    case result of
        Left err -> handleCommentError err
        Right comments -> json comments

-- | Handle resolving a comment
handleResolveComment :: MonadIO m
                    => CommentService
                    -> Text  -- ^ Comment ID
                    -> ActionT ApiError m ()
handleResolveComment service commentId = do
    userId <- requireUserId
    result <- lift $ resolveComment service commentId userId
    case result of
        Left err -> handleCommentError err
        Right comment -> json comment

-- | Handle unresolving a comment
handleUnresolveComment :: MonadIO m
                      => CommentService
                      -> Text  -- ^ Comment ID
                      -> ActionT ApiError m ()
handleUnresolveComment service commentId = do
    result <- lift $ unresolveComment service commentId
    case result of
        Left err -> handleCommentError err
        Right comment -> json comment

-- | Handle deleting a comment
handleDeleteComment :: MonadIO m
                   => CommentService
                   -> Text  -- ^ Comment ID
                   -> ActionT ApiError m ()
handleDeleteComment service commentId = do
    result <- lift $ deleteComment service commentId
    case result of
        Left err -> handleCommentError err
        Right _ -> status noContent204

-- | Handle getting comments for a file
handleGetFileComments :: MonadIO m
                     => CommentService
                     -> ActionT ApiError m ()
handleGetFileComments service = do
    revisionId <- param "revision_id"
    filePath <- param "file_path"
    result <- lift $ getFileComments service revisionId filePath
    case result of
        Left err -> handleCommentError err
        Right comments -> json comments

-- | Handle getting comments in a thread
handleGetThreadComments :: MonadIO m
                       => CommentService
                       -> Text  -- ^ Parent comment ID
                       -> ActionT ApiError m ()
handleGetThreadComments service parentId = do
    result <- lift $ getThreadComments service parentId
    case result of
        Left err -> handleCommentError err
        Right comments -> json comments

-- | Helper function to handle comment errors
handleCommentError :: MonadIO m => CommentError -> ActionT ApiError m ()
handleCommentError err = case err of
    CommentNotFound msg -> notFound $ "Comment not found: " <> msg
    RevisionNotFound msg -> notFound $ "Revision not found: " <> msg
    InvalidComment msg -> badRequest $ "Invalid comment: " <> msg
    DatabaseError msg -> internalError $ "Database error: " <> msg
    ValidationError msg -> badRequest $ "Validation error: " <> msg
    PermissionDenied msg -> forbidden $ "Permission denied: " <> msg

-- | Helper function to require a user ID from the request
requireUserId :: MonadIO m => ActionT ApiError m Text
requireUserId = do
    maybeUserId <- header "X-User-Id"
    case maybeUserId of
        Nothing -> unauthorized "User ID not provided"
        Just userId -> return userId
