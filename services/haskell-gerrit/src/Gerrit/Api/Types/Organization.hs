-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Types.Organization where

import Data.Aeson
import Data.Text (Text)
import GHC.Generics

import Gerrit.Models.Organization (Visibility(..), OrganizationRole(..), TeamRole(..))

-- | Request to create an organization
data CreateOrganizationRequest = CreateOrganizationRequest
    { corEnterpriseId :: Text
    , corName :: Text
    , corDisplayName :: Text
    , corDescription :: Text
    , corVisibility :: Visibility
    } deriving (Show, Generic)

instance FromJSON CreateOrganizationRequest
instance ToJSON CreateOrganizationRequest

-- | Request to update an organization
data UpdateOrganizationRequest = UpdateOrganizationRequest
    { uorName :: Text
    , uorDisplayName :: Text
    , uorDescription :: Text
    , uorVisibility :: Visibility
    } deriving (Show, Generic)

instance FromJSON UpdateOrganizationRequest
instance ToJSON UpdateOrganizationRequest

-- | Request to add a member to an organization
data AddMemberRequest = AddMemberRequest
    { amrUserId :: Text
    , amrRole :: OrganizationRole
    } deriving (Show, Generic)

instance FromJSON AddMemberRequest
instance ToJSON AddMemberRequest

-- | Request to update a member's role
data UpdateRoleRequest = UpdateRoleRequest
    { urrRole :: OrganizationRole
    } deriving (Show, Generic)

instance FromJSON UpdateRoleRequest
instance ToJSON UpdateRoleRequest

-- | Request to create a team
data CreateTeamRequest = CreateTeamRequest
    { ctrName :: Text
    , ctrDescription :: Text
    } deriving (Show, Generic)

instance FromJSON CreateTeamRequest
instance ToJSON CreateTeamRequest

-- | Request to update a team
data UpdateTeamRequest = UpdateTeamRequest
    { utrName :: Text
    , utrDescription :: Text
    } deriving (Show, Generic)

instance FromJSON UpdateTeamRequest
instance ToJSON UpdateTeamRequest

-- | Request to add a member to a team
data AddTeamMemberRequest = AddTeamMemberRequest
    { atmrUserId :: Text
    , atmrRole :: TeamRole
    } deriving (Show, Generic)

instance FromJSON AddTeamMemberRequest
instance ToJSON AddTeamMemberRequest

-- | Request to update a team member's role
data UpdateTeamRoleRequest = UpdateTeamRoleRequest
    { utrrRole :: TeamRole
    } deriving (Show, Generic)

instance FromJSON UpdateTeamRoleRequest
instance ToJSON UpdateTeamRoleRequest

-- | Generic success response
data SuccessResponse = SuccessResponse
    { success :: Bool
    } deriving (Show, Generic)

instance ToJSON SuccessResponse

-- | Generic error response
data ErrorResponse = ErrorResponse
    { error :: Text
    } deriving (Show, Generic)

instance ToJSON ErrorResponse
