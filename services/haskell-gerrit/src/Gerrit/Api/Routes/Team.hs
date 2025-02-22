-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.Team
    ( teamRoutes
    ) where

import Web.Scotty.Trans

import Gerrit.Api.Error (ApiError)
import Gerrit.Api.Handlers.Team
import Gerrit.Services.TeamService (TeamService)

-- | Team routes
teamRoutes :: TeamService -> ScottyT ApiError IO ()
teamRoutes service = do
    -- Teams
    post "/api/teams" $
        handleCreateTeam service

    get "/api/teams" $
        handleListTeams service

    get "/api/teams/:team_id" $
        handleGetTeam service

    put "/api/teams/:team_id" $
        handleUpdateTeam service

    delete "/api/teams/:team_id" $
        handleDeleteTeam service

    -- Team Members
    post "/api/teams/:team_id/members" $
        handleAddTeamMember service

    get "/api/teams/:team_id/members" $
        handleGetTeamMembers service

    delete "/api/teams/:team_id/members/:user_id" $
        handleRemoveTeamMember service

    put "/api/teams/:team_id/members/:user_id/role" $
        handleUpdateMemberRole service

    -- Team Hierarchy
    get "/api/teams/:team_id/hierarchy" $
        handleGetTeamHierarchy service
