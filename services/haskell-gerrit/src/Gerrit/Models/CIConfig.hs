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

module Gerrit.Models.CIConfig where

import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Repository (Repository)

-- | CI provider type
data CIProvider =
    Jenkins
  | GitHubActions
  | GitLabCI
  | CustomCI Text  -- ^ For custom CI implementations
  deriving (Show, Read, Eq, Generic)

instance ToJSON CIProvider
instance FromJSON CIProvider

derivePersistField "CIProvider"

-- | Build status
data BuildStatus =
    Queued
  | Running
  | Success
  | Failure
  | Error
  | Cancelled
  | Skipped
  deriving (Show, Read, Eq, Generic)

instance ToJSON BuildStatus
instance FromJSON BuildStatus

derivePersistField "BuildStatus"

-- | Jenkins specific configuration
data JenkinsConfig = JenkinsConfig
  { jenkinsUrl :: Text
  , jobName :: Text
  , authToken :: Text
  , buildParams :: Value
  , webhookSecret :: Maybe Text
  } deriving (Show, Generic)

instance ToJSON JenkinsConfig
instance FromJSON JenkinsConfig

derivePersistField "JenkinsConfig"

-- | GitHub Actions configuration
data GitHubActionsConfig = GitHubActionsConfig
  { workflowFile :: Text
  , environment :: Text
  , secrets :: Value
  , runners :: [Text]
  } deriving (Show, Generic)

instance ToJSON GitHubActionsConfig
instance FromJSON GitHubActionsConfig

derivePersistField "GitHubActionsConfig"

-- | GitLab CI configuration
data GitLabCIConfig = GitLabCIConfig
  { gitlabUrl :: Text
  , projectId :: Text
  , pipelineToken :: Text
  , variables :: Value
  } deriving (Show, Generic)

instance ToJSON GitLabCIConfig
instance FromJSON GitLabCIConfig

derivePersistField "GitLabCIConfig"

-- | CI configuration
data CIConfiguration = CIConfiguration
  { provider :: CIProvider
  , jenkinsConfig :: Maybe JenkinsConfig
  , githubConfig :: Maybe GitHubActionsConfig
  , gitlabConfig :: Maybe GitLabCIConfig
  , customConfig :: Maybe Value
  , buildTimeout :: Int  -- ^ Build timeout in seconds
  , retryCount :: Int
  , retryDelay :: Int  -- ^ Delay between retries in seconds
  , notifyOnSuccess :: Bool
  , notifyOnFailure :: Bool
  } deriving (Show, Generic)

instance ToJSON CIConfiguration
instance FromJSON CIConfiguration

derivePersistField "CIConfiguration"

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
CIConfig
    configId Text
    repoId Text
    enabled Bool default=true
    configuration CIConfiguration
    webhookUrl Text Maybe
    webhookSecret Text Maybe
    metadata Value Maybe
    createdBy Text
    created UTCTime
    updated UTCTime
    UniqueConfigId configId
    UniqueRepoConfig repoId
    Foreign Repository repoId References repositories OnDeleteCascade
    deriving Show Eq Generic

Build
    buildId Text
    configId Text
    changeId Text Maybe  -- ^ Associated change ID if any
    provider CIProvider
    status BuildStatus
    startTime UTCTime Maybe
    endTime UTCTime Maybe
    duration Int Maybe  -- ^ Build duration in seconds
    logs Text Maybe
    artifacts Value Maybe
    environment Value Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueBuildId buildId
    Foreign CIConfig configId References ci_configs OnDeleteCascade
    deriving Show Eq Generic

BuildStep
    stepId Text
    buildId Text
    name Text
    status BuildStatus
    startTime UTCTime Maybe
    endTime UTCTime Maybe
    duration Int Maybe
    logs Text Maybe
    metadata Value Maybe
    created UTCTime
    UniqueStepId stepId
    Foreign Build buildId References builds OnDeleteCascade
    deriving Show Eq Generic

BuildArtifact
    artifactId Text
    buildId Text
    name Text
    path Text
    size Int
    mimeType Text
    metadata Value Maybe
    created UTCTime
    UniqueArtifactId artifactId
    Foreign Build buildId References builds OnDeleteCascade
    deriving Show Eq Generic
|]

instance ToJSON (Entity CIConfig)
instance ToJSON CIConfig
instance FromJSON CIConfig

instance ToJSON (Entity Build)
instance ToJSON Build
instance FromJSON Build

instance ToJSON (Entity BuildStep)
instance ToJSON BuildStep
instance FromJSON BuildStep

instance ToJSON (Entity BuildArtifact)
instance ToJSON BuildArtifact
instance FromJSON BuildArtifact
