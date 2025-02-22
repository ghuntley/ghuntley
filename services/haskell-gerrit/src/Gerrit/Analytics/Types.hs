-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Analytics.Types where

import Data.Aeson
import Data.Map (Map)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

-- | Activity metrics
data ActivityMetrics = ActivityMetrics
    { amChangesPerDay :: Map UTCTime Int
    , amReviewsPerDay :: Map UTCTime Int
    , amCodeChurnRate :: Double  -- lines/day
    , amReviewThroughput :: Double  -- reviews/day
    , amReviewTimeDistribution :: [Int]  -- minutes
    , amComplexityTrends :: Map UTCTime Double
    , amTestCoverage :: Map UTCTime Double
    , amReviewDepth :: Double  -- comments/line
    , amBugRate :: Double  -- bugs/kLOC
    , amFileModFrequency :: Map Text Int
    , amCommitSizeDistribution :: [(Int, Int)]  -- size buckets and counts
    , amBranchActivity :: Map Text ActivityLevel
    , amTimeToFirstReview :: Int  -- minutes
    , amReviewCycleTime :: Int  -- minutes
    , amMergeSuccessRate :: Map Int Double  -- hour -> success rate
    , amCommentSentiment :: Map Text Double  -- file -> sentiment score
    , amCodeOwnership :: Map Text Text  -- file -> user
    } deriving (Show, Generic)

instance ToJSON ActivityMetrics
instance FromJSON ActivityMetrics

-- | Quality metrics
data QualityMetrics = QualityMetrics
    { qmCodeCoverage :: Double
    , qmReviewCoverage :: Double
    , qmDocScore :: Double
    , qmTestScore :: Double
    , qmStyleScore :: Double
    , qmTechnicalDebt :: DebtScore
    , qmDefectRate :: Double
    , qmCyclomaticComplexity :: Map Text Double  -- file -> complexity
    , qmDuplicationRate :: Double
    , qmTestToCodeRatio :: Double
    , qmDocFreshness :: Map Text UTCTime  -- file -> last doc update
    , qmApiStability :: Double
    , qmBreakingChanges :: Int
    , qmBackwardCompatibility :: Double
    , qmSecurityScore :: Double
    , qmPerformanceScore :: Double
    } deriving (Show, Generic)

instance ToJSON QualityMetrics
instance FromJSON QualityMetrics

-- | Contributor metrics
data ContributorMetrics = ContributorMetrics
    { cmCommitFrequency :: Map Text Double  -- user -> commits/day
    , cmReviewParticipation :: Map Text Double  -- user -> reviews/day
    , cmLinesChanged :: Map Text Int  -- user -> lines
    , cmAverageReviewTime :: Map Text Int  -- user -> minutes
    , cmMergeSuccessRate :: Map Text Double  -- user -> success rate
    , cmCommentActivity :: Map Text Int  -- user -> comments
    , cmTrends :: Map Text [MetricPoint]  -- user -> trend points
    , cmKnowledgeIndex :: Map Text Double  -- user -> knowledge score
    , cmCollaborationScore :: Map Text Double  -- user -> collab score
    , cmReviewLoad :: Map Text Int  -- user -> active reviews
    , cmExpertise :: Map Text ExpertiseLevel  -- user -> expertise
    , cmResponsePatterns :: Map Text [ResponseTime]  -- user -> response times
    , cmReviewThoroughness :: Map Text Double  -- user -> thoroughness score
    , cmMentorshipScore :: Map Text Double  -- user -> mentorship score
    , cmTeamVelocityImpact :: Map Text Double  -- user -> velocity impact
    , cmWorkPatterns :: Map Text WorkPatternAnalysis  -- user -> work patterns
    } deriving (Show, Generic)

instance ToJSON ContributorMetrics
instance FromJSON ContributorMetrics

-- | Activity level enumeration
data ActivityLevel = Low | Medium | High | Critical
    deriving (Show, Eq, Generic)

instance ToJSON ActivityLevel
instance FromJSON ActivityLevel

-- | Technical debt score components
data DebtScore = DebtScore
    { dsComplexity :: Double
    , dsDocumentation :: Double
    , dsTestCoverage :: Double
    , dsCodeStyle :: Double
    , dsDuplication :: Double
    } deriving (Show, Generic)

instance ToJSON DebtScore
instance FromJSON DebtScore

-- | Metric data point
data MetricPoint = MetricPoint
    { mpTimestamp :: UTCTime
    , mpValue :: Double
    } deriving (Show, Generic)

instance ToJSON MetricPoint
instance FromJSON MetricPoint

-- | Expertise level enumeration
data ExpertiseLevel = Novice | Intermediate | Expert | Master
    deriving (Show, Eq, Ord, Generic)

instance ToJSON ExpertiseLevel
instance FromJSON ExpertiseLevel

-- | Response time tracking
data ResponseTime = ResponseTime
    { rtTimestamp :: UTCTime
    , rtDuration :: Int  -- minutes
    } deriving (Show, Generic)

instance ToJSON ResponseTime
instance FromJSON ResponseTime

-- | Work pattern analysis
data WorkPatternAnalysis = WorkPatternAnalysis
    { wpaActiveHours :: [Int]  -- 0-23 hours
    , wpaActiveDays :: [Int]  -- 0-6 days
    , wpaAverageSessionLength :: Int  -- minutes
    , wpaSessionGaps :: [Int]  -- minutes between sessions
    } deriving (Show, Generic)

instance ToJSON WorkPatternAnalysis
instance FromJSON WorkPatternAnalysis
