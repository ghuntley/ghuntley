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

module Gerrit.Models.SecurityPolicy
    ( -- * Types
      SecurityPolicy(..)
    , SecurityPolicyId
    , Role(..)
    , Permission(..)
    , ResourceType(..)
    , ActionType(..)
    , ValidationError(..)
      -- * Operations
    , createSecurityPolicy
    , updateSecurityPolicy
    , getSecurityPolicyById
    , listSecurityPolicies
    , assignRole
    , revokeRole
    , checkPermission
    , requirePermission
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

-- | Role type
data Role
    = Owner
    | Admin
    | Member
    | Guest
    deriving (Show, Read, Eq, Generic)
derivePersistField "Role"

-- | Permission type
data Permission
    = Read
    | Write
    | Execute
    | Delete
    | Grant
    deriving (Show, Read, Eq, Generic)
derivePersistField "Permission"

-- | Resource type
data ResourceType
    = ChangeResource
    | RevisionResource
    | CommentResource
    | VoteResource
    | OrganizationResource
    | EnterpriseResource
    | AdminResource
    | AlertResource
    | StackResource
    | BillingResource
    deriving (Show, Read, Eq, Generic)
derivePersistField "ResourceType"

-- | Action type
data ActionType
    = Create
    | Read
    | Update
    | Delete
    | Grant
    | Revoke
    | Enable
    | Disable
    | Configure
    deriving (Show, Read, Eq, Generic)
derivePersistField "ActionType"

-- | Validation error
data ValidationError
    = InvalidInput Text
    | MissingField Text
    | InvalidFormat Text
    | ValueOutOfRange Text
    | UnauthorizedAccess Text
    deriving (Show, Eq, Generic)

-- | Define the security policy entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
SecurityPolicy
    policyId Text
    name Text
    description Text
    resourceType ResourceType
    role Role
    permissions [Permission]
    actions [ActionType]
    validationRules Value Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueSecurityPolicyId policyId
    UniqueSecurityPolicyName name
    deriving Show Eq Generic

RoleAssignment
    assignmentId Text
    userId Text
    resourceId Text
    role Role
    assignedBy Text
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueRoleAssignmentId assignmentId
    UniqueUserResourceRole userId resourceId role
    deriving Show Eq Generic
|]

-- | Create security policy
createSecurityPolicy :: MonadIO m
                    => Text  -- ^ Name
                    -> Text  -- ^ Description
                    -> ResourceType  -- ^ Resource type
                    -> Role  -- ^ Role
                    -> [Permission]  -- ^ Permissions
                    -> [ActionType]  -- ^ Actions
                    -> Maybe Value  -- ^ Validation rules
                    -> Maybe Value  -- ^ Additional metadata
                    -> m (Entity SecurityPolicy)
createSecurityPolicy name description resourceType role permissions actions validationRules metadata = do
    now <- liftIO getCurrentTime
    let policyId = generatePolicyId name now
    let policy = SecurityPolicy
            { securityPolicyPolicyId = policyId
            , securityPolicyName = name
            , securityPolicyDescription = description
            , securityPolicyResourceType = resourceType
            , securityPolicyRole = role
            , securityPolicyPermissions = permissions
            , securityPolicyActions = actions
            , securityPolicyValidationRules = validationRules
            , securityPolicyMetadata = metadata
            , securityPolicyCreated = now
            , securityPolicyUpdated = now
            }
    runDB $ insertEntity policy

-- | Update security policy
updateSecurityPolicy :: MonadIO m
                    => Entity SecurityPolicy
                    -> Text  -- ^ Name
                    -> Text  -- ^ Description
                    -> ResourceType  -- ^ Resource type
                    -> Role  -- ^ Role
                    -> [Permission]  -- ^ Permissions
                    -> [ActionType]  -- ^ Actions
                    -> Maybe Value  -- ^ Validation rules
                    -> Maybe Value  -- ^ Additional metadata
                    -> m (Entity SecurityPolicy)
updateSecurityPolicy (Entity key policy) name description resourceType role permissions actions validationRules metadata = do
    now <- liftIO getCurrentTime
    let updatedPolicy = policy
            { securityPolicyName = name
            , securityPolicyDescription = description
            , securityPolicyResourceType = resourceType
            , securityPolicyRole = role
            , securityPolicyPermissions = permissions
            , securityPolicyActions = actions
            , securityPolicyValidationRules = validationRules
            , securityPolicyMetadata = metadata
            , securityPolicyUpdated = now
            }
    runDB $ replace key updatedPolicy
    return $ Entity key updatedPolicy

-- | Get security policy by ID
getSecurityPolicyById :: MonadIO m
                     => Text  -- ^ Policy ID
                     -> m (Maybe (Entity SecurityPolicy))
getSecurityPolicyById policyId =
    runDB $ getBy $ UniqueSecurityPolicyId policyId

-- | List security policies
listSecurityPolicies :: MonadIO m
                    => Maybe ResourceType  -- ^ Filter by resource type
                    -> Maybe Role  -- ^ Filter by role
                    -> Int   -- ^ Offset
                    -> Int   -- ^ Limit
                    -> m [Entity SecurityPolicy]
listSecurityPolicies mResourceType mRole offset limit = do
    let filters = concat
            [ maybe [] (\t -> [SecurityPolicyResourceType ==. t]) mResourceType
            , maybe [] (\r -> [SecurityPolicyRole ==. r]) mRole
            ]
    runDB $ selectList filters [Asc SecurityPolicyName, OffsetBy offset, LimitTo limit]

-- | Assign role to user
assignRole :: MonadIO m
          => Text  -- ^ User ID
          -> Text  -- ^ Resource ID
          -> Role  -- ^ Role
          -> Text  -- ^ Assigned by
          -> Maybe Value  -- ^ Additional metadata
          -> m (Entity RoleAssignment)
assignRole userId resourceId role assignedBy metadata = do
    now <- liftIO getCurrentTime
    let assignmentId = generateAssignmentId userId resourceId role now
    let assignment = RoleAssignment
            { roleAssignmentAssignmentId = assignmentId
            , roleAssignmentUserId = userId
            , roleAssignmentResourceId = resourceId
            , roleAssignmentRole = role
            , roleAssignmentAssignedBy = assignedBy
            , roleAssignmentMetadata = metadata
            , roleAssignmentCreated = now
            , roleAssignmentUpdated = now
            }
    runDB $ insertEntity assignment

-- | Revoke role from user
revokeRole :: MonadIO m
           => Text  -- ^ User ID
           -> Text  -- ^ Resource ID
           -> Role  -- ^ Role
           -> m ()
revokeRole userId resourceId role =
    runDB $ deleteBy $ UniqueUserResourceRole userId resourceId role

-- | Check permission
checkPermission :: MonadIO m
                => Text  -- ^ User ID
                -> ResourceType  -- ^ Resource type
                -> Permission  -- ^ Permission
                -> m (Either ValidationError Bool)
checkPermission userId resourceType permission = do
    policies <- runDB $ selectList
        [ SecurityPolicyResourceType ==. resourceType
        , SecurityPolicyPermissions <@. [permission]
        ] []
    assignments <- runDB $ selectList
        [ RoleAssignmentUserId ==. userId
        ] []
    return $ Right $ any (hasPermission policies) assignments
  where
    hasPermission policies (Entity _ assignment) =
        any (\(Entity _ policy) ->
            roleAssignmentRole assignment == securityPolicyRole policy
        ) policies

-- | Require permission
requirePermission :: MonadIO m
                 => Text  -- ^ User ID
                 -> ResourceType  -- ^ Resource type
                 -> Permission  -- ^ Permission
                 -> m (Either ValidationError ())
requirePermission userId resourceType permission = do
    result <- checkPermission userId resourceType permission
    return $ case result of
        Right True -> Right ()
        Right False -> Left $ UnauthorizedAccess "Insufficient permissions"
        Left err -> Left err

-- Helper functions for generating IDs
generatePolicyId :: Text -> UTCTime -> Text
generatePolicyId name timestamp =
    "sp_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateAssignmentId :: Text -> Text -> Role -> UTCTime -> Text
generateAssignmentId userId resourceId role timestamp =
    "ra_" <> Text.filter isAllowed (userId <> "_" <> resourceId <> "_" <> showRole role) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
    showRole = Text.pack . show

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
