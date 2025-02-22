-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Organization
    ( handleListOrganizations
    , handleCreateOrganization
    , handleGetOrganization
    , handleUpdateOrganization
    , handleDeleteOrganization
    , handleListMembers
    , handleAddMember
    , handleRemoveMember
    , handleUpdateMemberRole
    , handleListTeams
    , handleCreateTeam
    , handleGetTeam
    , handleUpdateTeam
    , handleDeleteTeam
    , handleListTeamMembers
    , handleAddTeamMember
    , handleRemoveTeamMember
    , handleUpdateTeamMemberRole
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime)
import Network.HTTP.Types.Status
import Web.Yesod

import Gerrit.Models.Organization
import Gerrit.Api.Types

-- | List organizations
handleListOrganizations :: Connection -> Handler Value
handleListOrganizations conn = do
    orgs <- listOrganizations conn
    return $ toJSON orgs

-- | Create organization
handleCreateOrganization :: Connection -> CreateOrganizationRequest -> Handler Value
handleCreateOrganization conn CreateOrganizationRequest{..} = do
    now <- liftIO getCurrentTime
    let org = Organization
            { orgId = generateId "org"
            , orgName = corName
            , orgDisplayName = corDisplayName
            , orgDescription = corDescription
            , orgVisibility = corVisibility
            , orgCreated = now
            , orgUpdated = now
            }
    org' <- createOrganization conn org
    return $ toJSON org'

-- | Get organization by ID
handleGetOrganization :: Connection -> Text -> Handler Value
handleGetOrganization conn orgId = do
    mOrg <- getOrganization conn orgId
    case mOrg of
        Just org -> return $ toJSON org
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Organization not found" :: Text)]

-- | Update organization
handleUpdateOrganization :: Connection -> Text -> UpdateOrganizationRequest -> Handler Value
handleUpdateOrganization conn orgId UpdateOrganizationRequest{..} = do
    mOrg <- getOrganization conn orgId
    case mOrg of
        Just org -> do
            let org' = org
                    { orgName = uorName
                    , orgDisplayName = uorDisplayName
                    , orgDescription = uorDescription
                    , orgVisibility = uorVisibility
                    }
            org'' <- updateOrganization conn org'
            return $ toJSON org''
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Organization not found" :: Text)]

-- | Delete organization
handleDeleteOrganization :: Connection -> Text -> Handler Value
handleDeleteOrganization conn orgId = do
    deleteOrganization conn orgId
    return $ object ["success" .= True]

-- | List organization members
handleListMembers :: Connection -> Text -> Handler Value
handleListMembers conn orgId = do
    members <- listOrganizationMembers conn orgId
    return $ toJSON members

-- | Add organization member
handleAddMember :: Connection -> Text -> AddMemberRequest -> Handler Value
handleAddMember conn orgId AddMemberRequest{..} = do
    now <- liftIO getCurrentTime
    let member = OrganizationMember
            { omId = generateId "mem"
            , omOrganizationId = orgId
            , omUserId = amrUserId
            , omRole = amrRole
            , omCreated = now
            , omUpdated = now
            }
    member' <- addOrganizationMember conn member
    return $ toJSON member'

-- | Remove organization member
handleRemoveMember :: Connection -> Text -> Text -> Handler Value
handleRemoveMember conn orgId userId = do
    removeOrganizationMember conn orgId userId
    return $ object ["success" .= True]

-- | Update member role
handleUpdateMemberRole :: Connection -> Text -> Text -> UpdateRoleRequest -> Handler Value
handleUpdateMemberRole conn orgId userId UpdateRoleRequest{..} = do
    updateMemberRole conn orgId userId urrRole
    return $ object ["success" .= True]

-- | List organization teams
handleListTeams :: Connection -> Text -> Handler Value
handleListTeams conn orgId = do
    teams <- listTeams conn orgId
    return $ toJSON teams

-- | Create team
handleCreateTeam :: Connection -> Text -> CreateTeamRequest -> Handler Value
handleCreateTeam conn orgId CreateTeamRequest{..} = do
    now <- liftIO getCurrentTime
    let team = OrganizationTeam
            { otId = generateId "team"
            , otOrganizationId = orgId
            , otName = ctrName
            , otDescription = ctrDescription
            , otCreated = now
            , otUpdated = now
            }
    team' <- createTeam conn team
    return $ toJSON team'

-- | Get team by ID
handleGetTeam :: Connection -> Text -> Text -> Handler Value
handleGetTeam conn orgId teamId = do
    mTeam <- getTeam conn teamId
    case mTeam of
        Just team
            | otOrganizationId team == orgId ->
                return $ toJSON team
            | otherwise -> sendResponseStatus status403 $
                object ["error" .= ("Team does not belong to organization" :: Text)]
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Team not found" :: Text)]

-- | Update team
handleUpdateTeam :: Connection -> Text -> Text -> UpdateTeamRequest -> Handler Value
handleUpdateTeam conn orgId teamId UpdateTeamRequest{..} = do
    mTeam <- getTeam conn teamId
    case mTeam of
        Just team
            | otOrganizationId team == orgId -> do
                let team' = team
                        { otName = utrName
                        , otDescription = utrDescription
                        }
                team'' <- updateTeam conn team'
                return $ toJSON team''
            | otherwise -> sendResponseStatus status403 $
                object ["error" .= ("Team does not belong to organization" :: Text)]
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Team not found" :: Text)]

-- | Delete team
handleDeleteTeam :: Connection -> Text -> Text -> Handler Value
handleDeleteTeam conn orgId teamId = do
    mTeam <- getTeam conn teamId
    case mTeam of
        Just team
            | otOrganizationId team == orgId -> do
                deleteTeam conn teamId
                return $ object ["success" .= True]
            | otherwise -> sendResponseStatus status403 $
                object ["error" .= ("Team does not belong to organization" :: Text)]
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Team not found" :: Text)]

-- | List team members
handleListTeamMembers :: Connection -> Text -> Handler Value
handleListTeamMembers conn teamId = do
    members <- listTeamMembers conn teamId
    return $ toJSON members

-- | Add team member
handleAddTeamMember :: Connection -> Text -> AddTeamMemberRequest -> Handler Value
handleAddTeamMember conn teamId AddTeamMemberRequest{..} = do
    now <- liftIO getCurrentTime
    let member = TeamMember
            { tmId = generateId "tmem"
            , tmTeamId = teamId
            , tmUserId = atmrUserId
            , tmRole = atmrRole
            , tmCreated = now
            }
    member' <- addTeamMember conn member
    return $ toJSON member'

-- | Remove team member
handleRemoveTeamMember :: Connection -> Text -> Text -> Handler Value
handleRemoveTeamMember conn teamId userId = do
    removeTeamMember conn teamId userId
    return $ object ["success" .= True]

-- | Update team member role
handleUpdateTeamMemberRole :: Connection -> Text -> Text -> UpdateTeamRoleRequest -> Handler Value
handleUpdateTeamMemberRole conn teamId userId UpdateTeamRoleRequest{..} = do
    updateTeamMemberRole conn teamId userId utrrRole
    return $ object ["success" .= True]

-- Helper functions

generateId :: Text -> Text
generateId prefix = undefined  -- TODO: Implement ID generation
