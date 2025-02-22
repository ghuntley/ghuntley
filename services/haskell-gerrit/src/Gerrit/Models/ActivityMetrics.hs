-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Models.ActivityMetrics
    ( -- * Types
      ActivityMetric(..)
    , ActivityMetricId
    , ContributorMetric(..)
    , ContributorMetricId
    , ReviewMetric(..)
    , ReviewMetricId
    , ActivityType(..)
    , MetricPeriod(..)
      -- * Operations
    , recordActivityMetric
    , recordContributorMetric
    , recordReviewMetric
    , getActivityMetrics
    , getContributorMetrics
    , getReviewMetrics
    , calculateActivityTrends
    , calculateVelocity
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime, diffUTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Activity metric types
data ActivityType
    = Commit        -- ^ Code commits
    | Review        -- ^ Code reviews
    | Comment       -- ^ Comments
    | Discussion    -- ^ Discussions
    | Integration   -- ^ Integration activities
    deriving (Show, Read, Eq, Generic)
derivePersistField "ActivityType"

-- | Metric time periods
data MetricPeriod
    = Hourly
    | Daily
    | Weekly
    | Monthly
    | Quarterly
    | Yearly
    deriving (Show, Read, Eq, Generic)
derivePersistField "MetricPeriod"

-- | Define the activity metrics entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
ActivityMetric
    metricId Text
    projectId Text
    activityType ActivityType
    count Int
    period MetricPeriod
    startTime UTCTime
    endTime UTCTime
    metadata Value
    UniqueActivityMetricId metricId
    deriving Show Eq Generic

ContributorMetric
    metricId Text
    projectId Text
    userId Text
    commits Int
    reviews Int
    comments Int
    additions Int
    deletions Int
    period MetricPeriod
    startTime UTCTime
    endTime UTCTime
    metadata Value
    UniqueContributorMetricId metricId
    deriving Show Eq Generic

ReviewMetric
    metricId Text
    projectId Text
    reviewId Text
    timeToFirstComment Int    -- in minutes
    timeToResolution Int      -- in minutes
    commentCount Int
    iterationCount Int
    reviewerCount Int
    status Text
    outcome Text
    created UTCTime
    resolved UTCTime Maybe
    metadata Value
    UniqueReviewMetricId metricId
    deriving Show Eq Generic
|]

-- | Record activity metric
recordActivityMetric :: MonadIO m
                    => ConnectionPool
                    -> Text  -- ^ Project ID
                    -> ActivityType  -- ^ Activity type
                    -> Int   -- ^ Count
                    -> MetricPeriod  -- ^ Period
                    -> UTCTime  -- ^ Start time
                    -> UTCTime  -- ^ End time
                    -> Value  -- ^ Metadata
                    -> m (Entity ActivityMetric)
recordActivityMetric pool projectId activityType count period start end metadata = do
    let metricId = generateMetricId "activity" projectId (Text.pack $ show activityType) start
    let activity = ActivityMetric
            { activityMetricMetricId = metricId
            , activityMetricProjectId = projectId
            , activityMetricActivityType = activityType
            , activityMetricCount = count
            , activityMetricPeriod = period
            , activityMetricStartTime = start
            , activityMetricEndTime = end
            , activityMetricMetadata = metadata
            }
    runSqlPool (insertEntity activity) pool

-- | Record contributor metric
recordContributorMetric :: MonadIO m
                       => ConnectionPool
                       -> Text  -- ^ Project ID
                       -> Text  -- ^ User ID
                       -> Int   -- ^ Commits
                       -> Int   -- ^ Reviews
                       -> Int   -- ^ Comments
                       -> Int   -- ^ Additions
                       -> Int   -- ^ Deletions
                       -> MetricPeriod  -- ^ Period
                       -> UTCTime  -- ^ Start time
                       -> UTCTime  -- ^ End time
                       -> Value  -- ^ Metadata
                       -> m (Entity ContributorMetric)
recordContributorMetric pool projectId userId commits reviews comments additions deletions period start end metadata = do
    let metricId = generateMetricId "contributor" projectId userId start
    let contributor = ContributorMetric
            { contributorMetricMetricId = metricId
            , contributorMetricProjectId = projectId
            , contributorMetricUserId = userId
            , contributorMetricCommits = commits
            , contributorMetricReviews = reviews
            , contributorMetricComments = comments
            , contributorMetricAdditions = additions
            , contributorMetricDeletions = deletions
            , contributorMetricPeriod = period
            , contributorMetricStartTime = start
            , contributorMetricEndTime = end
            , contributorMetricMetadata = metadata
            }
    runSqlPool (insertEntity contributor) pool

-- | Record review metric
recordReviewMetric :: MonadIO m
                   => ConnectionPool
                   -> Text  -- ^ Project ID
                   -> Text  -- ^ Review ID
                   -> Int   -- ^ Time to first comment (minutes)
                   -> Int   -- ^ Time to resolution (minutes)
                   -> Int   -- ^ Comment count
                   -> Int   -- ^ Iteration count
                   -> Int   -- ^ Reviewer count
                   -> Text  -- ^ Status
                   -> Text  -- ^ Outcome
                   -> UTCTime  -- ^ Created time
                   -> Maybe UTCTime  -- ^ Resolved time
                   -> Value  -- ^ Metadata
                   -> m (Entity ReviewMetric)
recordReviewMetric pool projectId reviewId timeToFirst timeToResolution comments iterations reviewers status outcome created resolved metadata = do
    let metricId = generateMetricId "review" projectId reviewId created
    let review = ReviewMetric
            { reviewMetricMetricId = metricId
            , reviewMetricProjectId = projectId
            , reviewMetricReviewId = reviewId
            , reviewMetricTimeToFirstComment = timeToFirst
            , reviewMetricTimeToResolution = timeToResolution
            , reviewMetricCommentCount = comments
            , reviewMetricIterationCount = iterations
            , reviewMetricReviewerCount = reviewers
            , reviewMetricStatus = status
            , reviewMetricOutcome = outcome
            , reviewMetricCreated = created
            , reviewMetricResolved = resolved
            , reviewMetricMetadata = metadata
            }
    runSqlPool (insertEntity review) pool

-- | Get activity metrics with filtering
getActivityMetrics :: MonadIO m
                   => ConnectionPool
                   -> Text  -- ^ Project ID
                   -> Maybe ActivityType  -- ^ Activity type
                   -> Maybe MetricPeriod  -- ^ Period
                   -> UTCTime  -- ^ Start time
                   -> UTCTime  -- ^ End time
                   -> m [Entity ActivityMetric]
getActivityMetrics pool projectId mType mPeriod start end = do
    let filters = concat
            [ [ActivityMetricProjectId ==. projectId]
            , maybe [] (\t -> [ActivityMetricActivityType ==. t]) mType
            , maybe [] (\p -> [ActivityMetricPeriod ==. p]) mPeriod
            , [ActivityMetricStartTime >=. start]
            , [ActivityMetricEndTime <=. end]
            ]
    runSqlPool (selectList filters [Desc ActivityMetricStartTime]) pool

-- | Get contributor metrics with filtering
getContributorMetrics :: MonadIO m
                      => ConnectionPool
                      -> Text  -- ^ Project ID
                      -> Maybe Text  -- ^ User ID
                      -> Maybe MetricPeriod  -- ^ Period
                      -> UTCTime  -- ^ Start time
                      -> UTCTime  -- ^ End time
                      -> m [Entity ContributorMetric]
getContributorMetrics pool projectId mUserId mPeriod start end = do
    let filters = concat
            [ [ContributorMetricProjectId ==. projectId]
            , maybe [] (\u -> [ContributorMetricUserId ==. u]) mUserId
            , maybe [] (\p -> [ContributorMetricPeriod ==. p]) mPeriod
            , [ContributorMetricStartTime >=. start]
            , [ContributorMetricEndTime <=. end]
            ]
    runSqlPool (selectList filters [Desc ContributorMetricStartTime]) pool

-- | Get review metrics with filtering
getReviewMetrics :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Project ID
                 -> Maybe Text  -- ^ Status
                 -> Maybe Text  -- ^ Outcome
                 -> UTCTime  -- ^ Start time
                 -> UTCTime  -- ^ End time
                 -> m [Entity ReviewMetric]
getReviewMetrics pool projectId mStatus mOutcome start end = do
    let filters = concat
            [ [ReviewMetricProjectId ==. projectId]
            , maybe [] (\s -> [ReviewMetricStatus ==. s]) mStatus
            , maybe [] (\o -> [ReviewMetricOutcome ==. o]) mOutcome
            , [ReviewMetricCreated >=. start]
            , [ReviewMetricCreated <=. end]
            ]
    runSqlPool (selectList filters [Desc ReviewMetricCreated]) pool

-- | Calculate activity trends
calculateActivityTrends :: MonadIO m
                       => ConnectionPool
                       -> Text  -- ^ Project ID
                       -> ActivityType  -- ^ Activity type
                       -> MetricPeriod  -- ^ Period
                       -> UTCTime  -- ^ Start time
                       -> UTCTime  -- ^ End time
                       -> m [(UTCTime, Int, Double)]  -- (time, count, trend)
calculateActivityTrends pool projectId activityType period start end = do
    metrics <- getActivityMetrics pool projectId (Just activityType) (Just period) start end
    -- Calculate trends based on the metrics
    -- Implementation would depend on specific requirements
    return []

-- | Calculate velocity metrics
calculateVelocity :: MonadIO m
                  => ConnectionPool
                  -> Text  -- ^ Project ID
                  -> MetricPeriod  -- ^ Period
                  -> UTCTime  -- ^ Start time
                  -> UTCTime  -- ^ End time
                  -> m Double
calculateVelocity pool projectId period start end = do
    -- Calculate velocity based on activity metrics
    -- Implementation would depend on specific requirements
    return 0.0

-- Helper functions

-- | Generate metric ID
generateMetricId :: Text -> Text -> Text -> UTCTime -> Text
generateMetricId prefix projectId component timestamp =
    prefix <> "_" <> Text.filter isAllowed (projectId <> "_" <> component) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
