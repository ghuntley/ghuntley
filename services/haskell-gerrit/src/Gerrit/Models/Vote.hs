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

module Gerrit.Models.Vote
    ( -- * Types
      Vote(..)
    , VoteId
    , VoteValue(..)
    , VoteCategory(..)
      -- * Operations
    , createVote
    , updateVote
    , getVoteById
    , getRevisionVotes
    , getUserVotes
    , deleteVote
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

-- | Vote value
data VoteValue
    = VoteNegativeTwo   -- ^ -2: Do not submit
    | VoteNegativeOne   -- ^ -1: Needs improvement
    | VoteZero          -- ^ 0: No score
    | VotePositiveOne   -- ^ +1: Looks good
    | VotePositiveTwo   -- ^ +2: Approved
    deriving (Show, Read, Eq, Ord, Generic)
derivePersistField "VoteValue"

-- | Vote category
data VoteCategory
    = CodeReview        -- ^ Code review vote
    | VerifiedBuild     -- ^ Build verification vote
    | SecurityReview    -- ^ Security review vote
    | QAReview         -- ^ QA review vote
    | ProductReview    -- ^ Product review vote
    | CustomCategory Text  -- ^ Custom vote category
    deriving (Show, Read, Eq, Generic)
derivePersistField "VoteCategory"

-- | Define the Vote entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Vote
    voteId Text
    revisionId Text
    voterId Text
    value VoteValue
    category VoteCategory
    message Text Maybe
    created UTCTime
    updated UTCTime
    UniqueVoteId voteId
    UniqueVoterRevisionCategory voterId revisionId category
    Foreign Revision revisionId References revisions OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new vote
createVote :: MonadIO m
           => ConnectionPool
           -> Text  -- ^ Revision ID
           -> Text  -- ^ Voter ID
           -> VoteValue  -- ^ Vote value
           -> VoteCategory  -- ^ Vote category
           -> Maybe Text  -- ^ Optional message
           -> m (Entity Vote)
createVote pool revisionId' voterId' value' category' message' = do
    now <- liftIO getCurrentTime
    let voteId' = generateVoteId revisionId' voterId' category' now
    let vote = Vote
            { voteVoteId = voteId'
            , voteRevisionId = revisionId'
            , voteVoterId = voterId'
            , voteValue = value'
            , voteCategory = category'
            , voteMessage = message'
            , voteCreated = now
            , voteUpdated = now
            }
    runSqlPool (insertBy vote) >>= \case
        Left (Entity key _) -> do
            -- Update existing vote
            let updatedVote = vote { voteUpdated = now }
            runSqlPool (replace key updatedVote) pool
            return $ Entity key updatedVote
        Right entity -> return entity

-- | Update a vote
updateVote :: MonadIO m
           => ConnectionPool
           -> Entity Vote
           -> VoteValue  -- ^ New vote value
           -> Maybe Text  -- ^ New message
           -> m (Entity Vote)
updateVote pool (Entity key vote) newValue newMessage = do
    now <- liftIO getCurrentTime
    let updatedVote = vote
            { voteValue = newValue
            , voteMessage = newMessage
            , voteUpdated = now
            }
    runSqlPool (replace key updatedVote) pool
    return $ Entity key updatedVote

-- | Get a vote by ID
getVoteById :: MonadIO m
            => ConnectionPool
            -> Text  -- ^ Vote ID
            -> m (Maybe (Entity Vote))
getVoteById pool voteId' =
    runSqlPool (getBy $ UniqueVoteId voteId') pool

-- | Get all votes for a revision
getRevisionVotes :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Revision ID
                 -> m [Entity Vote]
getRevisionVotes pool revisionId' =
    runSqlPool (selectList [VoteRevisionId ==. revisionId'] [Asc VoteCreated]) pool

-- | Get votes by user
getUserVotes :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Voter ID
             -> m [Entity Vote]
getUserVotes pool voterId' =
    runSqlPool (selectList [VoteVoterId ==. voterId'] [Desc VoteCreated]) pool

-- | Delete a vote
deleteVote :: MonadIO m
           => ConnectionPool
           -> Entity Vote
           -> m ()
deleteVote pool (Entity key _) =
    runSqlPool (delete key) pool

-- | Helper function to generate a unique vote ID
generateVoteId :: Text -> Text -> VoteCategory -> UTCTime -> Text
generateVoteId revisionId voterId category timestamp =
    "v" <> Text.filter isAllowed (revisionId <> "-" <> voterId <> "-" <> categoryStr <> "-" <> showt timestamp)
  where
    showt = Text.pack . show
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
    categoryStr = case category of
        CodeReview -> "code"
        VerifiedBuild -> "verified"
        SecurityReview -> "security"
        QAReview -> "qa"
        ProductReview -> "product"
        CustomCategory t -> Text.filter isAllowed t
