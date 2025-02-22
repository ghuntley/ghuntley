-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Team
    ( -- * Handlers
      handleCreateTeam
    , handleUpdateTeam
    , handleDeleteTeam
    , handleGetTeam
    , handleListTeams
    , handleAddTeamMember
    , handleRemoveTeamMember
    , handleUpdateMemberRole
    , handleGetTeamMembers
    , handleGetTeamHierarchy
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Network.HTTP.Types.Status
import Web.Scotty.Trans

import Gerrit.Api.Types
import Gerrit.Models.Team
import Gerrit.Services.TeamService (TeamService, TeamError(..))
import qualified Gerrit.Services.TeamService as TeamService

-- | Request types
data CreateTeamRequest = CreateTeamRequest
    { createTeamName :: Text
    , createTeamDescription :: Maybe Text
    , createTeamOrganizationId :: Text
    , createTeamVisibility :: TeamVisibility
    , createTeamParentId :: Maybe Text
    , createTeamMetadata :: Maybe Value
    }

data UpdateTeamRequest = UpdateTeamRequest
    { updateTeamName :: Text
    , updateTeamDescription :: Maybe Text
    , updateTeamVisibility :: TeamVisibility
    , updateTeamParentId :: Maybe Text
    , updateTeamMetadata :: Maybe Value
    }

data AddMemberRequest = AddMemberRequest
    { addMemberUserId :: Text
    , addMemberRole :: TeamRole
    , addMemberMetadata :: Maybe Value
    }

data UpdateMemberRequest = UpdateMemberRequest
    { updateMemberRole :: TeamRole
    }

-- | Handler to create a new team
handleCreateTeam :: MonadIO m
                => TeamService
                -> ActionT Error m ()
handleCreateTeam service = do
    -- Parse request
    CreateTeamRequest{..} <- jsonData

    -- Get user from context
    userId <- requireUser

    -- Create team
    result <- TeamService.createTeam
        service
        createTeamName
        createTeamDescription
        createTeamOrganizationId
        createTeamVisibility
        createTeamParentId
        createTeamMetadata
        userId

    case result of
        Left err -> handleTeamError err
        Right team -> do
            status created201
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= team
                ]

-- | Handler to update a team
handleUpdateTeam :: MonadIO m
                => TeamService
                -> ActionT Error m ()
handleUpdateTeam service = do
    -- Get team ID from path
    teamId <- param "team_id"

    -- Parse request
    UpdateTeamRequest{..} <- jsonData

    -- Get user from context
    userId <- requireUser

    -- Get team
    result <- TeamService.getTeamById service teamId
    case result of
        Left err -> handleTeamError err
        Right team -> do
            -- Update team
            updateResult <- TeamService.updateTeam
                service
                team
                updateTeamName
                updateTeamDescription
                updateTeamVisibility
                updateTeamParentId
                updateTeamMetadata
                userId

            case updateResult of
                Left err -> handleTeamError err
                Right updatedTeam -> do
                    status ok200
                    json $ object
                        [ "status" .= ("success" :: Text)
                        , "data" .= updatedTeam
                        ]

-- | Handler to delete a team
handleDeleteTeam :: MonadIO m
                => TeamService
                -> ActionT Error m ()
handleDeleteTeam service = do
    -- Get team ID from path
    teamId <- param "team_id"

    -- Get user from context
    userId <- requireUser

    -- Get team
    result <- TeamService.getTeamById service teamId
    case result of
        Left err -> handleTeamError err
        Right team -> do
            -- Delete team
            deleteResult <- TeamService.deleteTeam service team userId
            case deleteResult of
                Left err -> handleTeamError err
                Right _ -> do
                    status ok200
                    json $ object ["status" .= ("success" :: Text)]

-- | Handler to get a team
handleGetTeam :: MonadIO m
              => TeamService
              -> ActionT Error m ()
handleGetTeam service = do
    -- Get team ID from path
    teamId <- param "team_id"

    -- Get team
    result <- TeamService.getTeamById service teamId
    case result of
        Left err -> handleTeamError err
        Right team -> do
            status ok200
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= team
                ]

-- | Handler to list teams
handleListTeams :: MonadIO m
                => TeamService
                -> ActionT Error m ()
handleListTeams service = do
    -- Get query parameters
    orgId <- param "organization_id"
    visibility <- (Just <$> param "visibility") `rescue` const (return Nothing)
    offset <- param "offset" `rescue` const (return 0)
    limit <- param "limit" `rescue` const (return 50)

    -- List teams
    teams <- TeamService.listTeams service orgId visibility offset limit

    -- Return response
    status ok200
    json $ object
        [ "status" .= ("success" :: Text)
        , "data" .= teams
        ]

-- | Handler to add a team member
handleAddTeamMember :: MonadIO m
                    => TeamService
                    -> ActionT Error m ()
handleAddTeamMember service = do
    -- Get team ID from path
    teamId <- param "team_id"

    -- Parse request
    AddMemberRequest{..} <- jsonData

    -- Get user from context
    userId <- requireUser

    -- Add member
    result <- TeamService.addTeamMember
        service
        teamId
        addMemberUserId
        addMemberRole
        userId
        addMemberMetadata

    case result of
        Left err -> handleTeamError err
        Right member -> do
            status created201
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= member
                ]

-- | Handler to remove a team member
handleRemoveTeamMember :: MonadIO m
                       => TeamService
                       -> ActionT Error m ()
handleRemoveTeamMember service = do
    -- Get team ID and user ID from path
    teamId <- param "team_id"
    memberId <- param "user_id"

    -- Get user from context
    userId <- requireUser

    -- Remove member
    result <- TeamService.removeTeamMember service teamId memberId userId
    case result of
        Left err -> handleTeamError err
        Right _ -> do
            status ok200
            json $ object ["status" .= ("success" :: Text)]

-- | Handler to update a member's role
handleUpdateMemberRole :: MonadIO m
                      => TeamService
                      -> ActionT Error m ()
handleUpdateMemberRole service = do
    -- Get team ID and user ID from path
    teamId <- param "team_id"
    memberId <- param "user_id"

    -- Parse request
    UpdateMemberRequest{..} <- jsonData

    -- Get user from context
    userId <- requireUser

    -- Update role
    result <- TeamService.updateMemberRole service teamId memberId updateMemberRole userId
    case result of
        Left err -> handleTeamError err
        Right member -> do
            status ok200
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= member
                ]

-- | Handler to get team members
handleGetTeamMembers :: MonadIO m
                    => TeamService
                    -> ActionT Error m ()
handleGetTeamMembers service = do
    -- Get team ID from path
    teamId <- param "team_id"

    -- Get role filter from query
    role <- (Just <$> param "role") `rescue` const (return Nothing)

    -- Get members
    members <- TeamService.getTeamMembers service teamId role

    -- Return response
    status ok200
    json $ object
        [ "status" .= ("success" :: Text)
        , "data" .= members
        ]

-- | Handler to get team hierarchy
handleGetTeamHierarchy :: MonadIO m
                      => TeamService
                      -> ActionT Error m ()
handleGetTeamHierarchy service = do
    -- Get team ID from path
    teamId <- param "team_id"

    -- Get hierarchy
    result <- TeamService.getTeamHierarchy service teamId
    case result of
        Left err -> handleTeamError err
        Right hierarchy -> do
            status ok200
            json $ object
                [ "status" .= ("success" :: Text)
                , "data" .= hierarchy
                ]

-- | Helper function to handle team errors
handleTeamError :: MonadIO m => TeamError -> ActionT Error m ()
handleTeamError err = case err of
    TeamNotFound msg -> do
        status notFound404
        json $ object ["error" .= msg]
    MemberNotFound msg -> do
        status notFound404
        json $ object ["error" .= msg]
    InvalidRole msg -> do
        status badRequest400
        json $ object ["error" .= msg]
    InvalidVisibility msg -> do
        status badRequest400
        json $ object ["error" .= msg]
    CyclicHierarchy msg -> do
        status badRequest400
        json $ object ["error" .= msg]
    AccessDenied msg -> do
        status forbidden403
        json $ object ["error" .= msg]
    DatabaseError msg -> do
        status internalServerError500
        json $ object ["error" .= msg]
