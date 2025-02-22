{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.CommentService
    ( -- * Types
      CommentService(..)
    , CommentError(..)
      -- * Operations
    , initCommentService
    , createComment
    , updateComment
    , getComment
    , listComments
    , resolveComment
    , unresolveComment
    , deleteComment
    , getFileComments
    , getThreadComments
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql

import Gerrit.Models.Comment
import Gerrit.Models.Revision (Revision)
import Gerrit.Services.NotificationService (NotificationService)
import Gerrit.Services.MetricsService (MetricsService)

-- | Comment service errors
data CommentError
    = CommentNotFound Text
    | RevisionNotFound Text
    | InvalidComment Text
    | DatabaseError Text
    | ValidationError Text
    | PermissionDenied Text
    deriving (Show, Eq)

-- | Comment service
data CommentService = CommentService
    { commentPool :: ConnectionPool
    , notificationService :: NotificationService
    , metricsService :: MetricsService
    }

-- | Initialize the comment service
initCommentService :: ConnectionPool
                  -> NotificationService
                  -> MetricsService
                  -> CommentService
initCommentService pool notifService metricsService =
    CommentService
        { commentPool = pool
        , notificationService = notifService
        , metricsService = metricsService
        }

-- | Create a new comment
createComment :: MonadIO m
              => CommentService
              -> Text  -- ^ Revision ID
              -> Text  -- ^ Author ID
              -> Text  -- ^ Message
              -> CommentType  -- ^ Comment type
              -> Maybe Text  -- ^ File path (for inline comments)
              -> Maybe Int  -- ^ Line number (for inline comments)
              -> m (Either CommentError (Entity Comment))
createComment CommentService{..} revisionId authorId message commentType filePath lineNumber = do
    -- Validate revision exists
    revisionExists <- runSqlPool (exists [RevisionRevisionId ==. revisionId]) commentPool
    if not revisionExists
        then return $ Left $ RevisionNotFound revisionId
        else do
            -- Validate comment
            case validateComment message commentType filePath lineNumber of
                Left err -> return $ Left err
                Right _ -> do
                    -- Create comment
                    result <- createComment commentPool revisionId authorId message commentType filePath lineNumber
                    -- Send notification
                    liftIO $ notifyCommentCreated notificationService result
                    -- Record metrics
                    liftIO $ recordCommentMetrics metricsService "create"
                    return $ Right result

-- | Update a comment
updateComment :: MonadIO m
              => CommentService
              -> Text  -- ^ Comment ID
              -> Text  -- ^ New message
              -> m (Either CommentError (Entity Comment))
updateComment CommentService{..} commentId newMessage = do
    -- Get existing comment
    maybeComment <- runSqlPool (getBy $ UniqueCommentId commentId) commentPool
    case maybeComment of
        Nothing -> return $ Left $ CommentNotFound commentId
        Just comment -> do
            -- Validate new message
            case validateMessage newMessage of
                Left err -> return $ Left err
                Right _ -> do
                    -- Update comment
                    result <- updateComment commentPool comment newMessage
                    -- Send notification
                    liftIO $ notifyCommentUpdated notificationService result
                    -- Record metrics
                    liftIO $ recordCommentMetrics metricsService "update"
                    return $ Right result

-- | Get a comment by ID
getComment :: MonadIO m
           => CommentService
           -> Text  -- ^ Comment ID
           -> m (Either CommentError (Entity Comment))
getComment CommentService{..} commentId = do
    maybeComment <- runSqlPool (getBy $ UniqueCommentId commentId) commentPool
    return $ case maybeComment of
        Nothing -> Left $ CommentNotFound commentId
        Just comment -> Right comment

-- | List comments for a revision
listComments :: MonadIO m
             => CommentService
             -> Text  -- ^ Revision ID
             -> m (Either CommentError [Entity Comment])
listComments CommentService{..} revisionId = do
    -- Validate revision exists
    revisionExists <- runSqlPool (exists [RevisionRevisionId ==. revisionId]) commentPool
    if not revisionExists
        then return $ Left $ RevisionNotFound revisionId
        else do
            comments <- getRevisionComments commentPool revisionId
            return $ Right comments

-- | Resolve a comment
resolveComment :: MonadIO m
               => CommentService
               -> Text  -- ^ Comment ID
               -> Text  -- ^ Resolver ID
               -> m (Either CommentError (Entity Comment))
resolveComment CommentService{..} commentId resolverId = do
    now <- liftIO getCurrentTime
    maybeComment <- runSqlPool (getBy $ UniqueCommentId commentId) commentPool
    case maybeComment of
        Nothing -> return $ Left $ CommentNotFound commentId
        Just (Entity key comment) -> do
            let updatedComment = comment
                    { commentResolved = True
                    , commentResolvedBy = Just resolverId
                    , commentResolvedAt = Just now
                    , commentUpdated = now
                    }
            runSqlPool (replace key updatedComment) commentPool
            let result = Entity key updatedComment
            -- Send notification
            liftIO $ notifyCommentResolved notificationService result
            -- Record metrics
            liftIO $ recordCommentMetrics metricsService "resolve"
            return $ Right result

-- | Unresolve a comment
unresolveComment :: MonadIO m
                 => CommentService
                 -> Text  -- ^ Comment ID
                 -> m (Either CommentError (Entity Comment))
unresolveComment CommentService{..} commentId = do
    now <- liftIO getCurrentTime
    maybeComment <- runSqlPool (getBy $ UniqueCommentId commentId) commentPool
    case maybeComment of
        Nothing -> return $ Left $ CommentNotFound commentId
        Just (Entity key comment) -> do
            let updatedComment = comment
                    { commentResolved = False
                    , commentResolvedBy = Nothing
                    , commentResolvedAt = Nothing
                    , commentUpdated = now
                    }
            runSqlPool (replace key updatedComment) commentPool
            let result = Entity key updatedComment
            -- Send notification
            liftIO $ notifyCommentUnresolved notificationService result
            -- Record metrics
            liftIO $ recordCommentMetrics metricsService "unresolve"
            return $ Right result

-- | Delete a comment
deleteComment :: MonadIO m
              => CommentService
              -> Text  -- ^ Comment ID
              -> m (Either CommentError ())
deleteComment CommentService{..} commentId = do
    maybeComment <- runSqlPool (getBy $ UniqueCommentId commentId) commentPool
    case maybeComment of
        Nothing -> return $ Left $ CommentNotFound commentId
        Just comment -> do
            runSqlPool (delete $ entityKey comment) commentPool
            -- Send notification
            liftIO $ notifyCommentDeleted notificationService comment
            -- Record metrics
            liftIO $ recordCommentMetrics metricsService "delete"
            return $ Right ()

-- | Get comments for a specific file
getFileComments :: MonadIO m
                => CommentService
                -> Text  -- ^ Revision ID
                -> Text  -- ^ File path
                -> m (Either CommentError [Entity Comment])
getFileComments CommentService{..} revisionId filePath = do
    -- Validate revision exists
    revisionExists <- runSqlPool (exists [RevisionRevisionId ==. revisionId]) commentPool
    if not revisionExists
        then return $ Left $ RevisionNotFound revisionId
        else do
            comments <- getFileComments commentPool revisionId filePath
            return $ Right comments

-- | Get comments in a thread (replies to a comment)
getThreadComments :: MonadIO m
                  => CommentService
                  -> Text  -- ^ Parent comment ID
                  -> m (Either CommentError [Entity Comment])
getThreadComments CommentService{..} parentId = do
    -- Get comments that are replies to the parent
    comments <- runSqlPool (selectList
        [CommentCommentType ==. Reply parentId]
        [Asc CommentCreated]) commentPool
    return $ Right comments

-- | Helper function to validate a comment
validateComment :: Text -> CommentType -> Maybe Text -> Maybe Int -> Either CommentError ()
validateComment message commentType filePath lineNumber = do
    validateMessage message
    case commentType of
        Inline ->
            case (filePath, lineNumber) of
                (Nothing, _) -> Left $ ValidationError "Inline comments require a file path"
                (_, Nothing) -> Left $ ValidationError "Inline comments require a line number"
                _ -> Right ()
        Reply _ -> Right ()
        General -> Right ()

-- | Helper function to validate a comment message
validateMessage :: Text -> Either CommentError ()
validateMessage message
    | Text.null message = Left $ ValidationError "Comment message cannot be empty"
    | Text.length message > 65535 = Left $ ValidationError "Comment message is too long"
    | otherwise = Right ()

-- | Helper function to notify about comment creation
notifyCommentCreated :: NotificationService -> Entity Comment -> IO ()
notifyCommentCreated = undefined  -- TODO: Implement notification

-- | Helper function to notify about comment updates
notifyCommentUpdated :: NotificationService -> Entity Comment -> IO ()
notifyCommentUpdated = undefined  -- TODO: Implement notification

-- | Helper function to notify about comment resolution
notifyCommentResolved :: NotificationService -> Entity Comment -> IO ()
notifyCommentResolved = undefined  -- TODO: Implement notification

-- | Helper function to notify about comment unresolution
notifyCommentUnresolved :: NotificationService -> Entity Comment -> IO ()
notifyCommentUnresolved = undefined  -- TODO: Implement notification

-- | Helper function to notify about comment deletion
notifyCommentDeleted :: NotificationService -> Entity Comment -> IO ()
notifyCommentDeleted = undefined  -- TODO: Implement notification

-- | Helper function to record comment metrics
recordCommentMetrics :: MetricsService -> Text -> IO ()
recordCommentMetrics = undefined  -- TODO: Implement metrics recording
