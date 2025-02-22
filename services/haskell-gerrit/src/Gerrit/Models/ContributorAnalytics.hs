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

module Gerrit.Models.ContributorAnalytics
    ( -- * Types
      ContributorMetric(..)
    , ContributorMetricId
    , ContributorPerformance(..)
    , ContributorPerformanceId
    , ContributorExpertise(..)
    , ContributorExpertiseId
    , ContributorCollaboration(..)
    , ContributorCollaborationId
    , MetricPeriod(..)
    , ExpertiseLevel(..)
    , CollaborationType(..)
      -- * Operations
    , recordContributorMetric
    , getContributorMetricById
    , listContributorMetrics
    , updateContributorPerformance
    , getContributorPerformanceById
    , listContributorPerformance
    , updateContributorExpertise
    , getContributorExpertiseById
    , listContributorExpertise
    , recordCollaboration
    , getCollaborationById
    , listCollaborations
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
import Gerrit.Models.User (User)

-- | Metric period
data MetricPeriod
    = Daily
    | Weekly
    | Monthly
    | Quarterly
    | Yearly
    | Custom Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "MetricPeriod"

-- | Expertise level
data ExpertiseLevel
    = Novice
    | Intermediate
    | Expert
    | Authority
    deriving (Show, Read, Eq, Generic)
derivePersistField "ExpertiseLevel"

-- | Collaboration type
data CollaborationType
    = Review
    | PairProgramming
    | CodeContribution
    | Documentation
    | Mentoring
    deriving (Show, Read, Eq, Generic)
derivePersistField "CollaborationType"

-- | Define the contributor analytics entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
ContributorMetric
    metricId Text
    userId Text
    commitCount Int
    linesChanged Int
    reviewCount Int
    commentCount Int
    averageReviewTime Double
    mergeSuccessRate Double
    period MetricPeriod
    startDate UTCTime
    endDate UTCTime
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueMetricId metricId
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic

ContributorPerformance
    performanceId Text
    userId Text
    velocityScore Double
    qualityScore Double
    collaborationScore Double
    knowledgeSharingScore Double
    period MetricPeriod
    startDate UTCTime
    endDate UTCTime
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniquePerformanceId performanceId
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic

ContributorExpertise
    expertiseId Text
    userId Text
    technology Text
    level ExpertiseLevel
    confidenceScore Double
    lastActive UTCTime
    endorsements Int
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueExpertiseId expertiseId
    UniqueUserTechnology userId technology
    Foreign User userId References users OnDeleteCascade
    deriving Show Eq Generic

ContributorCollaboration
    collaborationId Text
    userId Text
    collaboratorId Text
    collaborationType CollaborationType
    frequency Int
    effectivenessScore Double
    period MetricPeriod
    startDate UTCTime
    endDate UTCTime
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueCollaborationId collaborationId
    Foreign User userId References users OnDeleteCascade
    Foreign User collaboratorId References users OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Record contributor metrics
recordContributorMetric :: MonadIO m
                       => Text  -- ^ User ID
                       -> Int  -- ^ Commit count
                       -> Int  -- ^ Lines changed
                       -> Int  -- ^ Review count
                       -> Int  -- ^ Comment count
                       -> Double  -- ^ Average review time
                       -> Double  -- ^ Merge success rate
                       -> MetricPeriod  -- ^ Period
                       -> UTCTime  -- ^ Start date
                       -> UTCTime  -- ^ End date
                       -> Maybe Value  -- ^ Additional metadata
                       -> m (Entity ContributorMetric)
recordContributorMetric userId commits lines reviews comments avgReviewTime mergeRate period start end metadata = do
    now <- liftIO getCurrentTime
    let metricId = generateMetricId userId now
    let metric = ContributorMetric
            { contributorMetricMetricId = metricId
            , contributorMetricUserId = userId
            , contributorMetricCommitCount = commits
            , contributorMetricLinesChanged = lines
            , contributorMetricReviewCount = reviews
            , contributorMetricCommentCount = comments
            , contributorMetricAverageReviewTime = avgReviewTime
            , contributorMetricMergeSuccessRate = mergeRate
            , contributorMetricPeriod = period
            , contributorMetricStartDate = start
            , contributorMetricEndDate = end
            , contributorMetricMetadata = metadata
            , contributorMetricCreated = now
            , contributorMetricUpdated = now
            }
    runDB $ insertEntity metric

-- | Get contributor metric by ID
getContributorMetricById :: MonadIO m
                        => Text  -- ^ Metric ID
                        -> m (Maybe (Entity ContributorMetric))
getContributorMetricById metricId =
    runDB $ getBy $ UniqueMetricId metricId

-- | List contributor metrics
listContributorMetrics :: MonadIO m
                      => Text  -- ^ User ID
                      -> MetricPeriod  -- ^ Period
                      -> UTCTime  -- ^ Start date
                      -> UTCTime  -- ^ End date
                      -> Int  -- ^ Offset
                      -> Int  -- ^ Limit
                      -> m [Entity ContributorMetric]
listContributorMetrics userId period start end offset limit =
    runDB $ selectList
        [ ContributorMetricUserId ==. userId
        , ContributorMetricPeriod ==. period
        , ContributorMetricStartDate >=. start
        , ContributorMetricEndDate <=. end
        ]
        [Desc ContributorMetricStartDate, OffsetBy offset, LimitTo limit]

-- | Update contributor performance
updateContributorPerformance :: MonadIO m
                            => Text  -- ^ User ID
                            -> Double  -- ^ Velocity score
                            -> Double  -- ^ Quality score
                            -> Double  -- ^ Collaboration score
                            -> Double  -- ^ Knowledge sharing score
                            -> MetricPeriod  -- ^ Period
                            -> UTCTime  -- ^ Start date
                            -> UTCTime  -- ^ End date
                            -> Maybe Value  -- ^ Additional metadata
                            -> m (Entity ContributorPerformance)
updateContributorPerformance userId velocity quality collab knowledge period start end metadata = do
    now <- liftIO getCurrentTime
    let performanceId = generatePerformanceId userId now
    let performance = ContributorPerformance
            { contributorPerformancePerformanceId = performanceId
            , contributorPerformanceUserId = userId
            , contributorPerformanceVelocityScore = velocity
            , contributorPerformanceQualityScore = quality
            , contributorPerformanceCollaborationScore = collab
            , contributorPerformanceKnowledgeSharingScore = knowledge
            , contributorPerformancePeriod = period
            , contributorPerformanceStartDate = start
            , contributorPerformanceEndDate = end
            , contributorPerformanceMetadata = metadata
            , contributorPerformanceCreated = now
            , contributorPerformanceUpdated = now
            }
    runDB $ insertEntity performance

-- | Get contributor performance by ID
getContributorPerformanceById :: MonadIO m
                             => Text  -- ^ Performance ID
                             -> m (Maybe (Entity ContributorPerformance))
getContributorPerformanceById performanceId =
    runDB $ getBy $ UniquePerformanceId performanceId

-- | List contributor performance
listContributorPerformance :: MonadIO m
                          => Text  -- ^ User ID
                          -> MetricPeriod  -- ^ Period
                          -> UTCTime  -- ^ Start date
                          -> UTCTime  -- ^ End date
                          -> Int  -- ^ Offset
                          -> Int  -- ^ Limit
                          -> m [Entity ContributorPerformance]
listContributorPerformance userId period start end offset limit =
    runDB $ selectList
        [ ContributorPerformanceUserId ==. userId
        , ContributorPerformancePeriod ==. period
        , ContributorPerformanceStartDate >=. start
        , ContributorPerformanceEndDate <=. end
        ]
        [Desc ContributorPerformanceStartDate, OffsetBy offset, LimitTo limit]

-- | Update contributor expertise
updateContributorExpertise :: MonadIO m
                          => Text  -- ^ User ID
                          -> Text  -- ^ Technology
                          -> ExpertiseLevel  -- ^ Level
                          -> Double  -- ^ Confidence score
                          -> Int  -- ^ Endorsements
                          -> Maybe Value  -- ^ Additional metadata
                          -> m (Entity ContributorExpertise)
updateContributorExpertise userId tech level confidence endorsements metadata = do
    now <- liftIO getCurrentTime
    let expertiseId = generateExpertiseId userId tech now
    let expertise = ContributorExpertise
            { contributorExpertiseExpertiseId = expertiseId
            , contributorExpertiseUserId = userId
            , contributorExpertiseTechnology = tech
            , contributorExpertiseLevel = level
            , contributorExpertiseConfidenceScore = confidence
            , contributorExpertiseLastActive = now
            , contributorExpertiseEndorsements = endorsements
            , contributorExpertiseMetadata = metadata
            , contributorExpertiseCreated = now
            , contributorExpertiseUpdated = now
            }
    runDB $ insertBy expertise >>= \case
        Left (Entity key _) -> do
            update key
                [ ContributorExpertiseLevel =. level
                , ContributorExpertiseConfidenceScore =. confidence
                , ContributorExpertiseLastActive =. now
                , ContributorExpertiseEndorsements =. endorsements
                , ContributorExpertiseMetadata =. metadata
                , ContributorExpertiseUpdated =. now
                ]
            getEntity key
        Right entity -> return entity

-- | Get contributor expertise by ID
getContributorExpertiseById :: MonadIO m
                           => Text  -- ^ Expertise ID
                           -> m (Maybe (Entity ContributorExpertise))
getContributorExpertiseById expertiseId =
    runDB $ getBy $ UniqueExpertiseId expertiseId

-- | List contributor expertise
listContributorExpertise :: MonadIO m
                        => Text  -- ^ User ID
                        -> Int  -- ^ Offset
                        -> Int  -- ^ Limit
                        -> m [Entity ContributorExpertise]
listContributorExpertise userId offset limit =
    runDB $ selectList
        [ContributorExpertiseUserId ==. userId]
        [Desc ContributorExpertiseLastActive, OffsetBy offset, LimitTo limit]

-- | Record collaboration
recordCollaboration :: MonadIO m
                   => Text  -- ^ User ID
                   -> Text  -- ^ Collaborator ID
                   -> CollaborationType  -- ^ Collaboration type
                   -> Int  -- ^ Frequency
                   -> Double  -- ^ Effectiveness score
                   -> MetricPeriod  -- ^ Period
                   -> UTCTime  -- ^ Start date
                   -> UTCTime  -- ^ End date
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Entity ContributorCollaboration)
recordCollaboration userId collaboratorId collabType frequency effectiveness period start end metadata = do
    now <- liftIO getCurrentTime
    let collaborationId = generateCollaborationId userId collaboratorId now
    let collaboration = ContributorCollaboration
            { contributorCollaborationCollaborationId = collaborationId
            , contributorCollaborationUserId = userId
            , contributorCollaborationCollaboratorId = collaboratorId
            , contributorCollaborationCollaborationType = collabType
            , contributorCollaborationFrequency = frequency
            , contributorCollaborationEffectivenessScore = effectiveness
            , contributorCollaborationPeriod = period
            , contributorCollaborationStartDate = start
            , contributorCollaborationEndDate = end
            , contributorCollaborationMetadata = metadata
            , contributorCollaborationCreated = now
            , contributorCollaborationUpdated = now
            }
    runDB $ insertEntity collaboration

-- | Get collaboration by ID
getCollaborationById :: MonadIO m
                    => Text  -- ^ Collaboration ID
                    -> m (Maybe (Entity ContributorCollaboration))
getCollaborationById collaborationId =
    runDB $ getBy $ UniqueCollaborationId collaborationId

-- | List collaborations
listCollaborations :: MonadIO m
                   => Text  -- ^ User ID
                   -> MetricPeriod  -- ^ Period
                   -> UTCTime  -- ^ Start date
                   -> UTCTime  -- ^ End date
                   -> Int  -- ^ Offset
                   -> Int  -- ^ Limit
                   -> m [Entity ContributorCollaboration]
listCollaborations userId period start end offset limit =
    runDB $ selectList
        [ ContributorCollaborationUserId ==. userId
        , ContributorCollaborationPeriod ==. period
        , ContributorCollaborationStartDate >=. start
        , ContributorCollaborationEndDate <=. end
        ]
        [Desc ContributorCollaborationStartDate, OffsetBy offset, LimitTo limit]

-- Helper functions for generating IDs
generateMetricId :: Text -> UTCTime -> Text
generateMetricId userId timestamp =
    "cm_" <> Text.filter isAllowed userId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generatePerformanceId :: Text -> UTCTime -> Text
generatePerformanceId userId timestamp =
    "cp_" <> Text.filter isAllowed userId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateExpertiseId :: Text -> Text -> UTCTime -> Text
generateExpertiseId userId tech timestamp =
    "ce_" <> Text.filter isAllowed userId <> "_" <> Text.filter isAllowed tech <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateCollaborationId :: Text -> Text -> UTCTime -> Text
generateCollaborationId userId collaboratorId timestamp =
    "cc_" <> Text.filter isAllowed userId <> "_" <> Text.filter isAllowed collaboratorId <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
