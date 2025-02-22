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

module Gerrit.Models.CommentType
    ( -- * Types
      CommentType(..)
    , CommentCategory(..)
    , CommentSeverity(..)
    , CommentVisibility(..)
      -- * Operations
    , isInlineComment
    , isThreadComment
    , isReviewComment
    , isSuggestionComment
    , isSystemComment
    , getCommentCategory
    , getCommentSeverity
    , getCommentVisibility
    ) where

import Data.Aeson (FromJSON(..), ToJSON(..))
import Data.Text (Text)
import Database.Persist
import Database.Persist.TH
import GHC.Generics

-- | Comment category
data CommentCategory
    = Code
    | Documentation
    | Style
    | Test
    | Build
    | Performance
    | Security
    | Other Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "CommentCategory"

-- | Comment severity
data CommentSeverity
    = Trivial
    | Minor
    | Major
    | Critical
    | Blocker
    deriving (Show, Read, Eq, Generic, Ord)
derivePersistField "CommentSeverity"

-- | Comment visibility
data CommentVisibility
    = Public
    | Private
    | Draft
    | System
    deriving (Show, Read, Eq, Generic)
derivePersistField "CommentVisibility"

-- | Comment type
data CommentType
    = InlineComment
        { category :: CommentCategory
        , severity :: CommentSeverity
        , visibility :: CommentVisibility
        }
    | ThreadComment
        { category :: CommentCategory
        , severity :: CommentSeverity
        , visibility :: CommentVisibility
        , parentId :: Maybe Text
        }
    | ReviewComment
        { category :: CommentCategory
        , severity :: CommentSeverity
        , visibility :: CommentVisibility
        , reviewPhase :: Text
        }
    | SuggestionComment
        { category :: CommentCategory
        , severity :: CommentSeverity
        , visibility :: CommentVisibility
        , suggestedCode :: Text
        }
    | SystemComment
        { category :: CommentCategory
        , visibility :: CommentVisibility
        , systemEvent :: Text
        }
    deriving (Show, Read, Eq, Generic)
derivePersistField "CommentType"

-- | Check if comment is an inline comment
isInlineComment :: CommentType -> Bool
isInlineComment (InlineComment {}) = True
isInlineComment _ = False

-- | Check if comment is a thread comment
isThreadComment :: CommentType -> Bool
isThreadComment (ThreadComment {}) = True
isThreadComment _ = False

-- | Check if comment is a review comment
isReviewComment :: CommentType -> Bool
isReviewComment (ReviewComment {}) = True
isReviewComment _ = False

-- | Check if comment is a suggestion comment
isSuggestionComment :: CommentType -> Bool
isSuggestionComment (SuggestionComment {}) = True
isSuggestionComment _ = False

-- | Check if comment is a system comment
isSystemComment :: CommentType -> Bool
isSystemComment (SystemComment {}) = True
isSystemComment _ = False

-- | Get comment category
getCommentCategory :: CommentType -> CommentCategory
getCommentCategory (InlineComment {category = c}) = c
getCommentCategory (ThreadComment {category = c}) = c
getCommentCategory (ReviewComment {category = c}) = c
getCommentCategory (SuggestionComment {category = c}) = c
getCommentCategory (SystemComment {category = c}) = c

-- | Get comment severity
getCommentSeverity :: CommentType -> Maybe CommentSeverity
getCommentSeverity (InlineComment {severity = s}) = Just s
getCommentSeverity (ThreadComment {severity = s}) = Just s
getCommentSeverity (ReviewComment {severity = s}) = Just s
getCommentSeverity (SuggestionComment {severity = s}) = Just s
getCommentSeverity (SystemComment {}) = Nothing

-- | Get comment visibility
getCommentVisibility :: CommentType -> CommentVisibility
getCommentVisibility (InlineComment {visibility = v}) = v
getCommentVisibility (ThreadComment {visibility = v}) = v
getCommentVisibility (ReviewComment {visibility = v}) = v
getCommentVisibility (SuggestionComment {visibility = v}) = v
getCommentVisibility (SystemComment {visibility = v}) = v
