{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Models.Comment
    ( -- * Types
      Comment(..)
    , CommentId
    , CommentType(..)
      -- * Operations
    , createComment
    , updateComment
    , getCommentById
    , getRevisionComments
    , getAuthorComments
    , getFileComments
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Revision (Revision)

-- | Comment type
data CommentType
    = Inline     -- ^ Comment on a specific line of code
    | General    -- ^ General comment on the change/revision
    | Reply Text -- ^ Reply to another comment
    deriving (Show, Read, Eq, Generic)
derivePersistField "CommentType"

-- | Define the Comment entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Comment
    commentId Text
    revisionId Text
    authorId Text
    commentType CommentType
    message Text
    filePath Text Maybe
    lineNumber Int Maybe
    resolved Bool default=false
    resolvedBy Text Maybe
    resolvedAt UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueCommentId commentId
    Foreign Revision revisionId References revisions OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new comment
createComment :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Revision ID
              -> Text  -- ^ Author ID
              -> Text  -- ^ Message
              -> CommentType  -- ^ Comment type
              -> Maybe Text  -- ^ File path (for inline comments)
              -> Maybe Int  -- ^ Line number (for inline comments)
              -> m (Entity Comment)
createComment pool revisionId' authorId' message' commentType' filePath' lineNumber' = do
    now <- liftIO getCurrentTime
    let commentId' = generateCommentId revisionId' authorId' now
    let comment = Comment
            { commentCommentId = commentId'
            , commentRevisionId = revisionId'
            , commentAuthorId = authorId'
            , commentCommentType = commentType'
            , commentMessage = message'
            , commentFilePath = filePath'
            , commentLineNumber = lineNumber'
            , commentResolved = False
            , commentResolvedBy = Nothing
            , commentResolvedAt = Nothing
            , commentCreated = now
            , commentUpdated = now
            }
    runSqlPool (insertEntity comment) pool

-- | Update a comment's message
updateComment :: MonadIO m
              => ConnectionPool
              -> Entity Comment
              -> Text  -- ^ New message
              -> m (Entity Comment)
updateComment pool (Entity key comment) newMessage = do
    now <- liftIO getCurrentTime
    let updatedComment = comment
            { commentMessage = newMessage
            , commentUpdated = now
            }
    runSqlPool (replace key updatedComment) pool
    return $ Entity key updatedComment

-- | Get a comment by ID
getCommentById :: MonadIO m
               => ConnectionPool
               -> Text  -- ^ Comment ID
               -> m (Maybe (Entity Comment))
getCommentById pool commentId' =
    runSqlPool (getBy $ UniqueCommentId commentId') pool

-- | Get all comments for a revision
getRevisionComments :: MonadIO m
                    => ConnectionPool
                    -> Text  -- ^ Revision ID
                    -> m [Entity Comment]
getRevisionComments pool revisionId' =
    runSqlPool (selectList [CommentRevisionId ==. revisionId'] [Asc CommentCreated]) pool

-- | Get comments by author
getAuthorComments :: MonadIO m
                  => ConnectionPool
                  -> Text  -- ^ Revision ID
                  -> Text  -- ^ Author ID
                  -> m [Entity Comment]
getAuthorComments pool revisionId' authorId' =
    runSqlPool (selectList
        [ CommentRevisionId ==. revisionId'
        , CommentAuthorId ==. authorId'
        ] [Asc CommentCreated]) pool

-- | Get comments for a specific file
getFileComments :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Revision ID
                -> Text  -- ^ File path
                -> m [Entity Comment]
getFileComments pool revisionId' filePath' =
    runSqlPool (selectList
        [ CommentRevisionId ==. revisionId'
        , CommentFilePath ==. Just filePath'
        ] [Asc CommentLineNumber, Asc CommentCreated]) pool

-- | Helper function to generate a unique comment ID
generateCommentId :: Text -> Text -> UTCTime -> Text
generateCommentId revisionId authorId timestamp =
    "c" <> Text.filter isAllowed (revisionId <> "-" <> authorId <> "-" <> showt timestamp)
  where
    showt = Text.pack . show
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
