{-|
Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Gerrit.Models.Tag where

import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Tag type
data TagType =
    LightweightTag  -- ^ Simple reference to a commit
  | AnnotatedTag    -- ^ Full tag object with metadata
  deriving (Show, Read, Eq, Generic)

instance ToJSON TagType
instance FromJSON TagType

derivePersistField "TagType"

-- | Tag verification status
data TagVerification =
    Unverified
  | VerifiedGood     -- ^ Signature is valid
  | VerifiedBad      -- ^ Signature is invalid
  | VerificationError Text  -- ^ Error during verification
  deriving (Show, Read, Eq, Generic)

instance ToJSON TagVerification
instance FromJSON TagVerification

derivePersistField "TagVerification"

-- | Tag signing configuration
data SigningConfig = SigningConfig
  { keyId :: Text              -- ^ GPG key ID
  , signatureAlgorithm :: Text -- ^ Signature algorithm
  , expiryDate :: Maybe UTCTime -- ^ Signature expiry date
  } deriving (Show, Generic)

instance ToJSON SigningConfig
instance FromJSON SigningConfig

derivePersistField "SigningConfig"

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Tag
    tagId Text
    repoId Text
    name Text
    tagType TagType
    targetCommit Text
    message Text Maybe
    tagger Text
    signature Text Maybe
    verification TagVerification
    signingConfig SigningConfig Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueTagId tagId
    UniqueRepoTag repoId name
    Foreign Repository repoId References repositories OnDeleteCascade
    deriving Show Eq Generic

TagRelease
    releaseId Text
    tagId Text
    version Text
    title Text
    description Text Maybe
    releaseNotes Text Maybe
    assets Value Maybe  -- ^ List of release assets
    isPrerelease Bool default=false
    isDraft Bool default=false
    publishedBy Text
    publishedAt UTCTime
    metadata Value Maybe
    UniqueReleaseId releaseId
    UniqueTagRelease tagId
    Foreign Tag tagId References tags OnDeleteCascade
    deriving Show Eq Generic

TagProtection
    protectionId Text
    repoId Text
    pattern Text  -- ^ Tag name pattern
    allowCreation Bool default=true
    allowDeletion Bool default=false
    requireSigning Bool default=false
    allowedSigners [Text] default=[]
    protectedBranches [Text] default=[]
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueProtectionId protectionId
    Foreign Repository repoId References repositories OnDeleteCascade
    deriving Show Eq Generic

TagActivity
    activityId Text
    tagId Text
    activityType Text  -- ^ create, delete, sign, verify, etc.
    performedBy Text
    details Value
    timestamp UTCTime
    UniqueActivityId activityId
    Foreign Tag tagId References tags OnDeleteCascade
    deriving Show Eq Generic
|]

instance ToJSON (Entity Tag)
instance ToJSON Tag
instance FromJSON Tag

instance ToJSON (Entity TagRelease)
instance ToJSON TagRelease
instance FromJSON TagRelease

instance ToJSON (Entity TagProtection)
instance ToJSON TagProtection
instance FromJSON TagProtection

instance ToJSON (Entity TagActivity)
instance ToJSON TagActivity
instance FromJSON TagActivity
