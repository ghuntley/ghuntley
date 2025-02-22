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

module Gerrit.Models.Team
    ( -- * Types
      Team(..)
    , TeamId
    , TeamRole(..)
    , TeamVisibility(..)
      -- * Operations
    , createTeam
    , updateTeam
    , deleteTeam
    , getTeamById
    , listTeams
    , addTeamMember
    , removeTeamMember
    , updateMemberRole
    , getTeamMembers
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Organization (Organization)

-- | Team roles
data TeamRole
    = TeamOwner      -- ^ Can manage team settings and members
    | TeamAdmin      -- ^ Can manage team resources
    | TeamMaintainer -- ^ Can approve changes
    | TeamDeveloper  -- ^ Can submit changes
    | TeamViewer     -- ^ Can view team resources
    deriving (Show, Read, Eq, Generic)
derivePersistField "TeamRole"

-- | Team visibility
data TeamVisibility
    = TeamPublic    -- ^ Visible to all
    | TeamPrivate   -- ^ Visible to members only
    | TeamRestricted -- ^ Visible to specific roles
    deriving (Show, Read, Eq, Generic)
derivePersistField "TeamVisibility"

-- | Define the Team entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Team
    teamId Text
    name Text
    description Text Maybe
    organizationId Text
    visibility TeamVisibility
    parentTeamId Text Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueTeamId teamId
    UniqueTeamName organizationId name
    Foreign Organization organizationId References organizations OnDeleteCascade
    deriving Show Eq Generic

TeamMember
    teamId Text
    userId Text
    role TeamRole
    addedBy Text
    addedAt UTCTime
    metadata Value Maybe
    UniqueTeamMembership teamId userId
    Foreign Team teamId References teams OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new team
createTeam :: MonadIO m
           => Text  -- ^ Name
           -> Maybe Text  -- ^ Description
           -> Text  -- ^ Organization ID
           -> TeamVisibility  -- ^ Visibility
           -> Maybe Text  -- ^ Parent team ID
           -> Maybe Value  -- ^ Additional metadata
           -> m (Entity Team)
createTeam name desc orgId visibility parentId metadata = do
    now <- liftIO getCurrentTime
    let teamId = generateTeamId name orgId now
    let team = Team
            { teamTeamId = teamId
            , teamName = name
            , teamDescription = desc
            , teamOrganizationId = orgId
            , teamVisibility = visibility
            , teamParentTeamId = parentId
            , teamMetadata = metadata
            , teamCreated = now
            , teamUpdated = now
            }
    runDB $ insertEntity team

-- | Update team details
updateTeam :: MonadIO m
           => Entity Team
           -> Text  -- ^ Name
           -> Maybe Text  -- ^ Description
           -> TeamVisibility  -- ^ Visibility
           -> Maybe Text  -- ^ Parent team ID
           -> Maybe Value  -- ^ Additional metadata
           -> m (Entity Team)
updateTeam (Entity key team) name desc visibility parentId metadata = do
    now <- liftIO getCurrentTime
    let updatedTeam = team
            { teamName = name
            , teamDescription = desc
            , teamVisibility = visibility
            , teamParentTeamId = parentId
            , teamMetadata = metadata
            , teamUpdated = now
            }
    runDB $ replace key updatedTeam
    return $ Entity key updatedTeam

-- | Delete a team
deleteTeam :: MonadIO m
           => Entity Team
           -> m ()
deleteTeam (Entity key _) =
    runDB $ delete key

-- | Get team by ID
getTeamById :: MonadIO m
            => Text  -- ^ Team ID
            -> m (Maybe (Entity Team))
getTeamById teamId =
    runDB $ getBy $ UniqueTeamId teamId

-- | List teams with filtering
listTeams :: MonadIO m
          => Text  -- ^ Organization ID
          -> Maybe TeamVisibility  -- ^ Filter by visibility
          -> Int   -- ^ Offset
          -> Int   -- ^ Limit
          -> m [Entity Team]
listTeams orgId mVisibility offset limit = do
    let filters = (TeamOrganizationId ==. orgId) :
                 maybe [] (\v -> [TeamVisibility ==. v]) mVisibility
    runDB $ selectList filters [Asc TeamName, OffsetBy offset, LimitTo limit]

-- | Add a member to a team
addTeamMember :: MonadIO m
              => Text  -- ^ Team ID
              -> Text  -- ^ User ID
              -> TeamRole  -- ^ Role
              -> Text  -- ^ Added by
              -> Maybe Value  -- ^ Additional metadata
              -> m (Entity TeamMember)
addTeamMember teamId userId role addedBy metadata = do
    now <- liftIO getCurrentTime
    let member = TeamMember
            { teamMemberTeamId = teamId
            , teamMemberUserId = userId
            , teamMemberRole = role
            , teamMemberAddedBy = addedBy
            , teamMemberAddedAt = now
            , teamMemberMetadata = metadata
            }
    runDB $ insertEntity member

-- | Remove a member from a team
removeTeamMember :: MonadIO m
                 => Text  -- ^ Team ID
                 -> Text  -- ^ User ID
                 -> m ()
removeTeamMember teamId userId =
    runDB $ deleteWhere [TeamMemberTeamId ==. teamId, TeamMemberUserId ==. userId]

-- | Update a member's role
updateMemberRole :: MonadIO m
                 => Text  -- ^ Team ID
                 -> Text  -- ^ User ID
                 -> TeamRole  -- ^ New role
                 -> m (Maybe (Entity TeamMember))
updateMemberRole teamId userId newRole = do
    runDB $ do
        mMember <- getBy $ UniqueTeamMembership teamId userId
        case mMember of
            Nothing -> return Nothing
            Just (Entity key member) -> do
                let updatedMember = member { teamMemberRole = newRole }
                replace key updatedMember
                return $ Just $ Entity key updatedMember

-- | Get team members
getTeamMembers :: MonadIO m
               => Text  -- ^ Team ID
               -> Maybe TeamRole  -- ^ Filter by role
               -> m [Entity TeamMember]
getTeamMembers teamId mRole = do
    let filters = (TeamMemberTeamId ==. teamId) :
                 maybe [] (\r -> [TeamMemberRole ==. r]) mRole
    runDB $ selectList filters [Asc TeamMemberAddedAt]

-- Helper functions for generating IDs
generateTeamId :: Text -> Text -> UTCTime -> Text
generateTeamId name orgId timestamp =
    "team_" <> Text.filter isAllowed name <> "_" <> Text.filter isAllowed orgId <>
    "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
