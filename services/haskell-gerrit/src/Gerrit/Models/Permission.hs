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

module Gerrit.Models.Permission where

import Data.Aeson
import Data.Text (Text)
import Data.Time
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

-- Core types for RBAC
data Role = Owner | Admin | Member | Guest
    deriving (Show, Eq, Generic)

instance ToJSON Role
instance FromJSON Role

data PermissionType = Read | Write | Execute | Delete | Grant
    deriving (Show, Eq, Generic)

instance ToJSON PermissionType
instance FromJSON PermissionType

data ResourceType = ChangeResource | RevisionResource | CommentResource | VoteResource
                 | OrganizationResource | EnterpriseResource | AdminResource
                 | AlertResource | StackResource | BillingResource
    deriving (Show, Eq, Generic)

instance ToJSON ResourceType
instance FromJSON ResourceType

data ActionType = Create | Read | Update | Delete | Grant | Revoke
                | Enable | Disable | Configure
    deriving (Show, Eq, Generic)

instance ToJSON ActionType
instance FromJSON ActionType

-- Persistent models for RBAC
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Permission
    permissionId Text
    userId Text
    resourceId Text
    resourceType ResourceType
    permissionType PermissionType
    grantedBy Text
    grantedAt UTCTime
    expiresAt UTCTime Maybe
    UniquePermissionId permissionId
    deriving Show Eq Generic

RoleAssignment
    roleId Text
    userId Text
    resourceId Text
    role Role
    assignedBy Text
    assignedAt UTCTime
    expiresAt UTCTime Maybe
    UniqueRoleId roleId
    deriving Show Eq Generic

PermissionGroup
    groupId Text
    name Text
    description Text Maybe
    createdBy Text
    createdAt UTCTime
    UniqueGroupId groupId
    deriving Show Eq Generic

GroupPermission
    groupId Text
    permissionType PermissionType
    resourceType ResourceType
    grantedBy Text
    grantedAt UTCTime
    Foreign PermissionGroup groupId References permissionGroups OnDeleteCascade
    deriving Show Eq Generic

GroupMembership
    groupId Text
    userId Text
    addedBy Text
    addedAt UTCTime
    Foreign PermissionGroup groupId References permissionGroups OnDeleteCascade
    UniqueGroupMembership groupId userId
    deriving Show Eq Generic
|]

-- Helper functions for permission management
checkPermission :: MonadIO m
                => Text  -- ^ User ID
                -> ResourceType
                -> PermissionType
                -> m (Either Text Bool)
checkPermission userId resourceType permType = do
    -- Check direct permissions
    directPerms <- runDB $ selectList [PermissionUserId ==. userId
                                    , PermissionResourceType ==. resourceType
                                    , PermissionPermissionType ==. permType
                                    , PermissionExpiresAt >. Just now
                                    ] []
    -- Check group permissions
    groupPerms <- runDB $ do
        memberships <- selectList [GroupMembershipUserId ==. userId] []
        let groupIds = map (groupMembershipGroupId . entityVal) memberships
        groupPerms <- selectList [GroupPermissionGroupId <-. groupIds
                               , GroupPermissionResourceType ==. resourceType
                               , GroupPermissionPermissionType ==. permType] []
        return groupPerms

    return $ Right (not (null directPerms) || not (null groupPerms))
  where
    now = undefined -- Replace with actual current time in implementation

assignRole :: MonadIO m
           => Text  -- ^ User ID
           -> Text  -- ^ Resource ID
           -> Role
           -> Text  -- ^ Assigned by
           -> m (Either Text ())
assignRole userId resourceId role assignedBy = do
    roleId <- generateRoleId
    now <- getCurrentTime
    runDB $ insert_ RoleAssignment
        { roleAssignmentRoleId = roleId
        , roleAssignmentUserId = userId
        , roleAssignmentResourceId = resourceId
        , roleAssignmentRole = role
        , roleAssignmentAssignedBy = assignedBy
        , roleAssignmentAssignedAt = now
        , roleAssignmentExpiresAt = Nothing
        }
    return $ Right ()
  where
    generateRoleId = undefined -- Replace with actual ID generation in implementation

revokeRole :: MonadIO m
           => Text  -- ^ User ID
           -> Text  -- ^ Resource ID
           -> Role
           -> m (Either Text ())
revokeRole userId resourceId role = do
    runDB $ deleteWhere [RoleAssignmentUserId ==. userId
                       , RoleAssignmentResourceId ==. resourceId
                       , RoleAssignmentRole ==. role]
    return $ Right ()

-- Helper functions for group management
createPermissionGroup :: MonadIO m
                     => Text  -- ^ Group name
                     -> Maybe Text  -- ^ Description
                     -> Text  -- ^ Created by
                     -> m (Either Text Text)  -- ^ Returns group ID
createPermissionGroup name desc createdBy = do
    groupId <- generateGroupId
    now <- getCurrentTime
    runDB $ insert_ PermissionGroup
        { permissionGroupGroupId = groupId
        , permissionGroupName = name
        , permissionGroupDescription = desc
        , permissionGroupCreatedBy = createdBy
        , permissionGroupCreatedAt = now
        }
    return $ Right groupId
  where
    generateGroupId = undefined -- Replace with actual ID generation in implementation

addUserToGroup :: MonadIO m
               => Text  -- ^ Group ID
               -> Text  -- ^ User ID
               -> Text  -- ^ Added by
               -> m (Either Text ())
addUserToGroup groupId userId addedBy = do
    now <- getCurrentTime
    runDB $ insert_ GroupMembership
        { groupMembershipGroupId = groupId
        , groupMembershipUserId = userId
        , groupMembershipAddedBy = addedBy
        , groupMembershipAddedAt = now
        }
    return $ Right ()

removeUserFromGroup :: MonadIO m
                    => Text  -- ^ Group ID
                    -> Text  -- ^ User ID
                    -> m (Either Text ())
removeUserFromGroup groupId userId = do
    runDB $ deleteWhere [GroupMembershipGroupId ==. groupId
                       , GroupMembershipUserId ==. userId]
    return $ Right ()
