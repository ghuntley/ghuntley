-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Types.Stack where

import Data.Aeson
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import GHC.Generics

import Gerrit.Models.Stack (RelationType(..), StackStatus(..))

-- | Request to create a stack
data CreateStackRequest = CreateStackRequest
    { csrName :: Text
    , csrDescription :: Maybe Text
    , csrOwnerId :: Text
    , csrBaseBranch :: Text
    } deriving (Show, Generic)

instance FromJSON CreateStackRequest
instance ToJSON CreateStackRequest

-- | Request to update a stack
data UpdateStackRequest = UpdateStackRequest
    { usrName :: Text
    , usrDescription :: Maybe Text
    , usrBaseBranch :: Text
    } deriving (Show, Generic)

instance FromJSON UpdateStackRequest
instance ToJSON UpdateStackRequest

-- | Request to add a change to a stack
data AddChangeRequest = AddChangeRequest
    { acrParentId :: Text
    , acrChangeId :: Text
    , acrRelationType :: RelationType
    } deriving (Show, Generic)

instance FromJSON AddChangeRequest
instance ToJSON AddChangeRequest

-- | Request to reorder changes in a stack
data ReorderStackRequest = ReorderStackRequest
    { rsrChangeIds :: [Text]  -- Changes in desired order
    } deriving (Show, Generic)

instance FromJSON ReorderStackRequest
instance ToJSON ReorderStackRequest

-- | Stack dependency graph node
data GraphNode = GraphNode
    { gnId :: Text
    , gnType :: Text
    , gnLabel :: Text
    , gnStatus :: Text
    } deriving (Show, Generic)

instance FromJSON GraphNode
instance ToJSON GraphNode

-- | Stack dependency graph edge
data GraphEdge = GraphEdge
    { geSource :: Text
    , geTarget :: Text
    , geType :: RelationType
    } deriving (Show, Generic)

instance FromJSON GraphEdge
instance ToJSON GraphEdge

-- | Stack dependency graph
data DependencyGraph = DependencyGraph
    { dgNodes :: [GraphNode]
    , dgEdges :: [GraphEdge]
    } deriving (Show, Generic)

instance FromJSON DependencyGraph
instance ToJSON DependencyGraph

-- | Stack conflict information
data StackConflict = StackConflict
    { scChangeId :: Text
    , scConflictingFiles :: [Text]
    , scResolutionStatus :: Text
    } deriving (Show, Generic)

instance FromJSON StackConflict
instance ToJSON StackConflict

-- | Stack rebase status
data RebaseStatus = RebaseStatus
    { rsChangeId :: Text
    , rsStatus :: Text
    , rsMessage :: Maybe Text
    } deriving (Show, Generic)

instance FromJSON RebaseStatus
instance ToJSON RebaseStatus

-- | Stack submission status
data SubmissionStatus = SubmissionStatus
    { ssChangeId :: Text
    , ssStatus :: Text
    , ssMessage :: Maybe Text
    } deriving (Show, Generic)

instance FromJSON SubmissionStatus
instance ToJSON SubmissionStatus

-- | Stack synchronization status
data SyncStatus = SyncStatus
    { syncChangeId :: Text
    , syncStatus :: Text
    , syncMessage :: Maybe Text
    , syncHash :: Maybe Text
    } deriving (Show, Generic)

instance FromJSON SyncStatus
instance ToJSON SyncStatus

-- | Stack operation response
data StackResponse = StackResponse
    { srSuccess :: Bool
    , srMessage :: Maybe Text
    , srDetails :: Maybe Value
    } deriving (Show, Generic)

instance FromJSON StackResponse
instance ToJSON StackResponse
