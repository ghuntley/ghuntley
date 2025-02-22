{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Models.Organization
    ( -- * Types
      Organization(..)
    , OrganizationId
    , OrganizationMember(..)
    , OrganizationMemberId
    , OrganizationTeam(..)
    , OrganizationTeamId
    , TeamMember(..)
    , TeamMemberId
    , OrganizationRole(..)
    , TeamRole(..)
    , Visibility(..)
      -- * Operations
    , createOrganization
    , getOrganizationById
    , updateOrganization
    , deleteOrganization
    , listOrganizations
    , listEnterpriseOrganizations
    , addOrganizationMember
    , removeOrganizationMember
    , updateMemberRole
    , listOrganizationMembers
    , createTeam
    , getTeamById
    , updateTeam
    , deleteTeam
    , listTeams
    , addTeamMember
    , removeTeamMember
    , updateTeamMemberRole
    , listTeamMembers
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.Text (Text)
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import qualified Data.Text as Text
import GHC.Generics

import Gerrit.Models.Types

-- | Organization visibility
data Visibility
    = Public
    | Private
    deriving (Show, Read, Eq, Generic)

derivePersistField "Visibility"

instance ToJSON Visibility
instance FromJSON Visibility

-- | Organization roles
data OrganizationRole
    = OrgOwner
    | OrgAdmin
    | OrgMember
    deriving (Show, Read, Eq, Generic)

derivePersistField "OrganizationRole"

instance ToJSON OrganizationRole
instance FromJSON OrganizationRole

-- | Team roles
data TeamRole
    = TeamMaintainer
    | TeamMember
    deriving (Show, Read, Eq, Generic)

derivePersistField "TeamRole"

instance ToJSON TeamRole
instance FromJSON TeamRole

-- | Organization
data Organization = Organization
    { organizationOrgId :: Text
    , organizationName :: Text
    , organizationDescription :: Maybe Text
    , organizationCreated :: UTCTime
    , organizationUpdated :: UTCTime
    } deriving (Show, Eq, Generic)

instance ToJSON Organization
instance FromJSON Organization

-- | Organization member
data OrganizationMember = OrganizationMember
    { organizationMemberOrgId :: Text
    , organizationMemberUserId :: Text
    , organizationMemberRole :: OrganizationRole
    , organizationMemberCreated :: UTCTime
    , organizationMemberUpdated :: UTCTime
    } deriving (Show, Eq, Generic)

instance ToJSON OrganizationMember
instance FromJSON OrganizationMember

-- | Organization team
data OrganizationTeam = OrganizationTeam
    { organizationTeamOrgId :: Text
    , organizationTeamName :: Text
    , organizationTeamDescription :: Maybe Text
    , organizationTeamCreated :: UTCTime
    , organizationTeamUpdated :: UTCTime
    } deriving (Show, Eq, Generic)

instance ToJSON OrganizationTeam
instance FromJSON OrganizationTeam

-- | Team member
data TeamMember = TeamMember
    { teamMemberTeamId :: Text
    , teamMemberUserId :: Text
    , teamMemberRole :: TeamRole
    , teamMemberCreated :: UTCTime
    } deriving (Show, Eq, Generic)

instance ToJSON TeamMember
instance FromJSON TeamMember

-- | Create a new organization
createOrganization :: MonadIO m
                   => ConnectionPool
                   -> Text  -- ^ Organization ID
                   -> Text  -- ^ Name
                   -> Text  -- ^ Display Name
                   -> Maybe Text  -- ^ Description
                   -> Visibility
                   -> m (Entity Organization)
createOrganization pool orgId' name' displayName' description' visibility' = do
    now <- liftIO getCurrentTime
    let org = Organization
            { organizationOrgId = orgId'
            , organizationName = name'
            , organizationDescription = description'
            , organizationCreated = now
            , organizationUpdated = now
            }
    runSqlPool (insertEntity org) pool

-- | Get organization by ID
getOrganizationById :: MonadIO m
                    => ConnectionPool
                    -> Text  -- ^ Organization ID
                    -> m (Maybe (Entity Organization))
getOrganizationById pool orgId' =
    runSqlPool (getBy $ UniqueOrgId orgId') pool

-- | Update organization
updateOrganization :: MonadIO m
                   => ConnectionPool
                   -> Entity Organization
                   -> Text  -- ^ New name
                   -> Maybe Text  -- ^ New description
                   -> m (Entity Organization)
updateOrganization pool (Entity orgKey org) newName newDesc = do
    now <- liftIO getCurrentTime
    let updatedOrg = org
            { organizationName = newName
            , organizationDescription = newDesc
            , organizationUpdated = now
            }
    runSqlPool (replace orgKey updatedOrg) pool
    return $ Entity orgKey updatedOrg

-- | Delete organization
deleteOrganization :: MonadIO m
                   => ConnectionPool
                   -> Text  -- ^ Organization ID
                   -> m ()
deleteOrganization pool orgId' =
    runSqlPool (deleteBy $ UniqueOrgId orgId') pool

-- | List all organizations
listOrganizations :: MonadIO m
                  => ConnectionPool
                  -> Int  -- ^ Limit
                  -> Int  -- ^ Offset
                  -> m [Entity Organization]
listOrganizations pool limit offset =
    runSqlPool (selectList [] [Asc OrganizationName, LimitTo limit, OffsetBy offset]) pool

-- | List organizations for a specific enterprise
listEnterpriseOrganizations :: MonadIO m
                           => ConnectionPool
                           -> Text  -- ^ Enterprise ID
                           -> m [Entity Organization]
listEnterpriseOrganizations pool enterpriseId' =
    runSqlPool (selectList [OrganizationEnterpriseId ==. enterpriseId'] [Asc OrganizationName]) pool

-- | Add organization member
addOrganizationMember :: MonadIO m
                      => ConnectionPool
                      -> Text  -- ^ Organization ID
                      -> Text  -- ^ User ID
                      -> OrganizationRole
                      -> m (Entity OrganizationMember)
addOrganizationMember pool orgId' userId' role = do
    now <- liftIO getCurrentTime
    let member = OrganizationMember
            { organizationMemberOrgId = orgId'
            , organizationMemberUserId = userId'
            , organizationMemberRole = role
            , organizationMemberCreated = now
            , organizationMemberUpdated = now
            }
    runSqlPool (insertEntity member) pool

-- | Remove organization member
removeOrganizationMember :: MonadIO m
                        => ConnectionPool
                        -> Text  -- ^ Organization ID
                        -> Text  -- ^ User ID
                        -> m ()
removeOrganizationMember pool orgId' userId' =
    runSqlPool (deleteWhere
        [ OrganizationMemberOrgId ==. orgId'
        , OrganizationMemberUserId ==. userId'
        ]) pool

-- | Update member role
updateMemberRole :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Organization ID
                 -> Text  -- ^ User ID
                 -> OrganizationRole
                 -> m ()
updateMemberRole pool orgId' userId' newRole = do
    now <- liftIO getCurrentTime
    runSqlPool (updateWhere
        [ OrganizationMemberOrgId ==. orgId'
        , OrganizationMemberUserId ==. userId'
        ]
        [ OrganizationMemberRole =. newRole
        , OrganizationMemberUpdated =. now
        ]) pool

-- | List organization members
listOrganizationMembers :: MonadIO m
                       => ConnectionPool
                       -> Text  -- ^ Organization ID
                       -> m [Entity OrganizationMember]
listOrganizationMembers pool orgId' =
    runSqlPool (selectList [OrganizationMemberOrgId ==. orgId'] [Asc OrganizationMemberCreated]) pool

-- | Create team
createTeam :: MonadIO m
           => ConnectionPool
           -> Text  -- ^ Organization ID
           -> Text  -- ^ Team name
           -> Maybe Text  -- ^ Description
           -> m (Entity OrganizationTeam)
createTeam pool orgId' name' description' = do
    now <- liftIO getCurrentTime
    let team = OrganizationTeam
            { organizationTeamOrgId = orgId'
            , organizationTeamName = name'
            , organizationTeamDescription = description'
            , organizationTeamCreated = now
            , organizationTeamUpdated = now
            }
    runSqlPool (insertEntity team) pool

-- | Get team by ID
getTeamById :: MonadIO m
            => ConnectionPool
            -> Text  -- ^ Team ID
            -> m (Maybe (Entity OrganizationTeam))
getTeamById pool teamId' =
    runSqlPool (getBy $ UniqueTeamId teamId') pool

-- | Update team
updateTeam :: MonadIO m
           => ConnectionPool
           -> Entity OrganizationTeam
           -> Text  -- ^ New name
           -> Maybe Text  -- ^ New description
           -> m (Entity OrganizationTeam)
updateTeam pool (Entity teamKey team) newName newDesc = do
    now <- liftIO getCurrentTime
    let updatedTeam = team
            { organizationTeamName = newName
            , organizationTeamDescription = newDesc
            , organizationTeamUpdated = now
            }
    runSqlPool (replace teamKey updatedTeam) pool
    return $ Entity teamKey updatedTeam

-- | Delete team
deleteTeam :: MonadIO m
           => ConnectionPool
           -> Text  -- ^ Team ID
           -> m ()
deleteTeam pool teamId' =
    runSqlPool (deleteBy $ UniqueTeamId teamId') pool

-- | List teams
listTeams :: MonadIO m
          => ConnectionPool
          -> Text  -- ^ Organization ID
          -> m [Entity OrganizationTeam]
listTeams pool orgId' =
    runSqlPool (selectList [OrganizationTeamOrgId ==. orgId'] [Asc OrganizationTeamName]) pool

-- | Add team member
addTeamMember :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Team ID
              -> Text  -- ^ User ID
              -> TeamRole
              -> m (Entity TeamMember)
addTeamMember pool teamId' userId' role = do
    now <- liftIO getCurrentTime
    let member = TeamMember
            { teamMemberTeamId = teamId'
            , teamMemberUserId = userId'
            , teamMemberRole = role
            , teamMemberCreated = now
            }
    runSqlPool (insertEntity member) pool

-- | Remove team member
removeTeamMember :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Team ID
                 -> Text  -- ^ User ID
                 -> m ()
removeTeamMember pool teamId' userId' =
    runSqlPool (deleteWhere
        [ TeamMemberTeamId ==. teamId'
        , TeamMemberUserId ==. userId'
        ]) pool

-- | Update team member role
updateTeamMemberRole :: MonadIO m
                    => ConnectionPool
                    -> Text  -- ^ Team ID
                    -> Text  -- ^ User ID
                    -> TeamRole
                    -> m ()
updateTeamMemberRole pool teamId' userId' newRole =
    runSqlPool (updateWhere
        [ TeamMemberTeamId ==. teamId'
        , TeamMemberUserId ==. userId'
        ]
        [ TeamMemberRole =. newRole
        ]) pool

-- | List team members
listTeamMembers :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Team ID
                -> m [Entity TeamMember]
listTeamMembers pool teamId' =
    runSqlPool (selectList [TeamMemberTeamId ==. teamId'] [Asc TeamMemberCreated]) pool
