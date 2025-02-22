-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}

module Gerrit.Api.Routes.Organization where

import Data.Text (Text)
import Web.Yesod

import Gerrit.Api.Handlers.Organization
import Gerrit.Api.Types.Organization

-- | Organization routes
mkYesodSubData "OrganizationApi" [parseRoutes|
/organizations                                    OrganizationsR         GET POST
/organizations/#Text                              OrganizationR          GET PUT DELETE
/organizations/#Text/members                      OrganizationMembersR   GET POST
/organizations/#Text/members/#Text                OrganizationMemberR    DELETE
/organizations/#Text/members/#Text/role           OrganizationMemberRoleR PUT
/organizations/#Text/teams                        TeamsR                 GET POST
/organizations/#Text/teams/#Text                  TeamR                  GET PUT DELETE
/organizations/#Text/teams/#Text/members          TeamMembersR           GET POST
/organizations/#Text/teams/#Text/members/#Text    TeamMemberR            DELETE
/organizations/#Text/teams/#Text/members/#Text/role TeamMemberRoleR      PUT
|]

instance YesodSubDispatch OrganizationApi (HandlerFor App) where
    yesodSubDispatch = $(mkYesodSubDispatch resourcesOrganizationApi)

-- | Organization handlers
getOrganizationsR :: Handler Value
getOrganizationsR = handleListOrganizations

postOrganizationsR :: Handler Value
postOrganizationsR = do
    req <- requireCheckJsonBody
    handleCreateOrganization req

getOrganizationR :: Text -> Handler Value
getOrganizationR = handleGetOrganization

putOrganizationR :: Text -> Handler Value
putOrganizationR orgId = do
    req <- requireCheckJsonBody
    handleUpdateOrganization orgId req

deleteOrganizationR :: Text -> Handler Value
deleteOrganizationR = handleDeleteOrganization

getOrganizationMembersR :: Text -> Handler Value
getOrganizationMembersR = handleListMembers

postOrganizationMembersR :: Text -> Handler Value
postOrganizationMembersR orgId = do
    req <- requireCheckJsonBody
    handleAddMember orgId req

deleteOrganizationMemberR :: Text -> Text -> Handler Value
deleteOrganizationMemberR = handleRemoveMember

putOrganizationMemberRoleR :: Text -> Text -> Handler Value
putOrganizationMemberRoleR orgId userId = do
    req <- requireCheckJsonBody
    handleUpdateMemberRole orgId userId req

getTeamsR :: Text -> Handler Value
getTeamsR = handleListTeams

postTeamsR :: Text -> Handler Value
postTeamsR orgId = do
    req <- requireCheckJsonBody
    handleCreateTeam orgId req

getTeamR :: Text -> Text -> Handler Value
getTeamR = handleGetTeam

putTeamR :: Text -> Text -> Handler Value
putTeamR orgId teamId = do
    req <- requireCheckJsonBody
    handleUpdateTeam orgId teamId req

deleteTeamR :: Text -> Text -> Handler Value
deleteTeamR = handleDeleteTeam

getTeamMembersR :: Text -> Text -> Handler Value
getTeamMembersR _ = handleListTeamMembers

postTeamMembersR :: Text -> Text -> Handler Value
postTeamMembersR _ teamId = do
    req <- requireCheckJsonBody
    handleAddTeamMember teamId req

deleteTeamMemberR :: Text -> Text -> Text -> Handler Value
deleteTeamMemberR _ = handleRemoveTeamMember

putTeamMemberRoleR :: Text -> Text -> Text -> Handler Value
putTeamMemberRoleR _ teamId userId = do
    req <- requireCheckJsonBody
    handleUpdateTeamMemberRole teamId userId req
