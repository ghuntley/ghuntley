-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Models.Types where

import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH
import GHC.Generics (Generic)
import Data.UUID (UUID)

-- | Review status for a change
data ReviewStatus = Draft | UnderReview | Approved | Rejected
    deriving (Show, Read, Eq, Generic)
derivePersistField "ReviewStatus"

-- | Vote values for reviews
data VoteValue = MinusTwo | MinusOne | Zero | PlusOne | PlusTwo
    deriving (Show, Read, Eq, Generic, Ord)
derivePersistField "VoteValue"

-- | Database schema definition using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
User
    email Text
    name Text
    passwordHash Text
    isAdmin Bool
    createdAt UTCTime
    UniqueEmail email
    deriving Show Generic

Project
    name Text
    description Text Maybe
    ownerUserId UserId
    createdAt UTCTime
    UniqueProjectName name
    deriving Show Generic

Change
    projectId ProjectId
    branch Text
    subject Text
    message Text
    authorId UserId
    status ReviewStatus
    createdAt UTCTime
    updatedAt UTCTime
    deriving Show Generic

Revision
    changeId ChangeId
    number Int
    commitHash Text
    parentHash Text
    authorId UserId
    createdAt UTCTime
    deriving Show Generic

Review
    changeId ChangeId
    reviewerId UserId
    vote VoteValue
    message Text Maybe
    createdAt UTCTime
    deriving Show Generic

Comment
    revisionId RevisionId
    authorId UserId
    lineNumber Int Maybe
    filePath Text Maybe
    message Text
    createdAt UTCTime
    deriving Show Generic

Permission
    projectId ProjectId
    userId UserId
    canRead Bool
    canWrite Bool
    canReview Bool
    canSubmit Bool
    UniqueProjectUser projectId userId
    deriving Show Generic
|]
