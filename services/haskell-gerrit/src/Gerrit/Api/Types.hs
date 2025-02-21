-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Types where

import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Servant.API
import Gerrit.Models.Types (ReviewStatus, VoteValue)

-- | API types for requests and responses

data CreateProjectRequest = CreateProjectRequest
    { cprName :: Text
    , cprDescription :: Maybe Text
    } deriving (Show, Generic)

instance ToJSON CreateProjectRequest
instance FromJSON CreateProjectRequest

data CreateChangeRequest = CreateChangeRequest
    { ccrProject :: Text
    , ccrBranch :: Text
    , ccrSubject :: Text
    , ccrMessage :: Text
    } deriving (Show, Generic)

instance ToJSON CreateChangeRequest
instance FromJSON CreateChangeRequest

data ChangeInfo = ChangeInfo
    { ciId :: Text
    , ciProject :: Text
    , ciBranch :: Text
    , ciSubject :: Text
    , ciMessage :: Text
    , ciAuthor :: UserInfo
    , ciStatus :: ReviewStatus
    , ciCreatedAt :: UTCTime
    , ciUpdatedAt :: UTCTime
    , ciCurrentRevision :: Maybe RevisionInfo
    } deriving (Show, Generic)

instance ToJSON ChangeInfo
instance FromJSON ChangeInfo

data RevisionInfo = RevisionInfo
    { riNumber :: Int
    , riCommitHash :: Text
    , riParentHash :: Text
    , riAuthor :: UserInfo
    , riCreatedAt :: UTCTime
    } deriving (Show, Generic)

instance ToJSON RevisionInfo
instance FromJSON RevisionInfo

data UserInfo = UserInfo
    { uiId :: Text
    , uiEmail :: Text
    , uiName :: Text
    } deriving (Show, Generic)

instance ToJSON UserInfo
instance FromJSON UserInfo

data ReviewInput = ReviewInput
    { riMessage :: Maybe Text
    , riVote :: VoteValue
    } deriving (Show, Generic)

instance ToJSON ReviewInput
instance FromJSON ReviewInput

data CommentInput = CommentInput
    { ciFilePath :: Maybe Text
    , ciLineNumber :: Maybe Int
    , ciMessage :: Text
    } deriving (Show, Generic)

instance ToJSON CommentInput
instance FromJSON CommentInput

-- | API type definitions using servant

type AuthHeader = Header "Authorization" Text

-- | Project API
type ProjectAPI =
    "projects" :>
        (    AuthHeader :> ReqBody '[JSON] CreateProjectRequest :> Post '[JSON] Text
        :<|> AuthHeader :> Capture "project" Text :> Get '[JSON] ProjectInfo
        :<|> AuthHeader :> Get '[JSON] [ProjectInfo]
        )

-- | Change API
type ChangeAPI =
    "changes" :>
        (    AuthHeader :> ReqBody '[JSON] CreateChangeRequest :> Post '[JSON] ChangeInfo
        :<|> AuthHeader :> Capture "change-id" Text :> Get '[JSON] ChangeInfo
        :<|> AuthHeader :> Get '[JSON] [ChangeInfo]
        :<|> AuthHeader :> Capture "change-id" Text :> "revisions" :> Get '[JSON] [RevisionInfo]
        :<|> AuthHeader :> Capture "change-id" Text :> "review" :> ReqBody '[JSON] ReviewInput :> Post '[JSON] ()
        :<|> AuthHeader :> Capture "change-id" Text :> "submit" :> Post '[JSON] ()
        )

-- | Comment API
type CommentAPI =
    "changes" :> Capture "change-id" Text :> "revisions" :> Capture "revision-id" Text :> "comments" :>
        (    AuthHeader :> ReqBody '[JSON] CommentInput :> Post '[JSON] ()
        :<|> AuthHeader :> Get '[JSON] [CommentInfo]
        )

-- | Complete API
type GerritAPI = ProjectAPI :<|> ChangeAPI :<|> CommentAPI

-- Additional types needed for responses

data ProjectInfo = ProjectInfo
    { piName :: Text
    , piDescription :: Maybe Text
    , piOwner :: UserInfo
    , piCreatedAt :: UTCTime
    } deriving (Show, Generic)

instance ToJSON ProjectInfo
instance FromJSON ProjectInfo

data CommentInfo = CommentInfo
    { cmId :: Text
    , cmAuthor :: UserInfo
    , cmFilePath :: Maybe Text
    , cmLineNumber :: Maybe Int
    , cmMessage :: Text
    , cmCreatedAt :: UTCTime
    } deriving (Show, Generic)

instance ToJSON CommentInfo
instance FromJSON CommentInfo
