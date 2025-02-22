-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE EmptyDataDecls             #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveGeneric              #-}

module Gerrit.Models.Types
    ( -- * Core Types
      EntityId
    , Timestamp(..)
    , UserId
    , ProjectId
    , ChangeId
    , RevisionId
    , CommentId
    , VoteId
    , OrganizationId
    , EnterpriseId
    , AdminId
    , AlertId
    , StackId
    , AuditLogId
    , BillingId
      -- * Shared Types
    , ChangeStatus(..)
    , Visibility(..)
    , Role(..)
    , Permission(..)
    , ResourceType(..)
    , ActionType(..)
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO)
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

-- | Core ID type
type EntityId = Text

-- | Timestamp wrapper for created/updated fields
data Timestamp = Timestamp
    { createdAt :: UTCTime
    , updatedAt :: UTCTime
    } deriving (Show, Eq, Generic)

-- | Type aliases for entity IDs
type UserId = EntityId
type ProjectId = EntityId
type ChangeId = EntityId
type RevisionId = EntityId
type CommentId = EntityId
type VoteId = EntityId
type OrganizationId = EntityId
type EnterpriseId = EntityId
type AdminId = EntityId
type AlertId = EntityId
type StackId = EntityId
type AuditLogId = EntityId
type BillingId = EntityId

-- | Change status
data ChangeStatus
    = Draft
    | Open
    | Merged
    | Abandoned
    | Deferred
    deriving (Show, Read, Eq, Generic)
derivePersistField "ChangeStatus"

-- | Resource visibility
data Visibility
    = Public
    | Private
    | Internal
    deriving (Show, Read, Eq, Generic)
derivePersistField "Visibility"

-- | User/Member roles
data Role
    = Owner
    | Admin
    | Member
    | Guest
    deriving (Show, Read, Eq, Generic)
derivePersistField "Role"

-- | Resource permissions
data Permission
    = Read
    | Write
    | Execute
    | Delete
    | Grant
    deriving (Show, Read, Eq, Generic)
derivePersistField "Permission"

-- | Resource types
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

-- | Action types for audit logging
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

-- | Base entity for common fields
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
BaseEntity
    createdAt UTCTime
    updatedAt UTCTime
    deriving Show Eq Generic
|]
