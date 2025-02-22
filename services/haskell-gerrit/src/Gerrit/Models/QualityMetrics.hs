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

module Gerrit.Models.QualityMetrics
    ( -- * Types
      CodeQuality(..)
    , CodeQualityId
    , TestCoverage(..)
    , TestCoverageId
    , TechnicalDebt(..)
    , TechnicalDebtId
    , QualityScore(..)
    , QualityType(..)
      -- * Operations
    , recordCodeQuality
    , recordTestCoverage
    , recordTechnicalDebt
    , getCodeQualityMetrics
    , getTestCoverageMetrics
    , getTechnicalDebtMetrics
    , calculateQualityScore
    , trackQualityTrends
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Quality metric types
data QualityType
    = Complexity       -- ^ Code complexity metrics
    | Coverage        -- ^ Test coverage metrics
    | Documentation   -- ^ Documentation coverage
    | Style          -- ^ Code style conformance
    | Security       -- ^ Security metrics
    | Performance    -- ^ Performance metrics
    deriving (Show, Read, Eq, Generic)
derivePersistField "QualityType"

-- | Quality score with metadata
data QualityScore = QualityScore
    { score :: Double
    , weight :: Double
    , details :: Value
    } deriving (Show, Eq, Generic)
derivePersistField "QualityScore"

-- | Define the quality metrics entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
CodeQuality
    metricId Text
    projectId Text
    branch Text
    commitId Text Maybe
    metricType QualityType
    complexity Int
    duplications Double
    violations Int
    qualityScore QualityScore
    metadata Value
    timestamp UTCTime
    UniqueCodeQualityId metricId
    deriving Show Eq Generic

TestCoverage
    metricId Text
    projectId Text
    branch Text
    commitId Text Maybe
    lineCoverage Double
    branchCoverage Double
    mutationScore Double Maybe
    testCount Int
    testDuration Int  -- in milliseconds
    qualityScore QualityScore
    metadata Value
    timestamp UTCTime
    UniqueTestCoverageId metricId
    deriving Show Eq Generic

TechnicalDebt
    metricId Text
    projectId Text
    category Text
    description Text
    severity Text
    effort Int        -- in minutes
    cost Double       -- estimated cost
    created UTCTime
    updated UTCTime
    resolvedAt UTCTime Maybe
    metadata Value
    UniqueTechnicalDebtId metricId
    deriving Show Eq Generic
|]

-- | Record code quality metrics
recordCodeQuality :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Project ID
                 -> Text  -- ^ Branch
                 -> Maybe Text  -- ^ Commit ID
                 -> QualityType  -- ^ Metric type
                 -> Int   -- ^ Complexity
                 -> Double  -- ^ Duplications
                 -> Int   -- ^ Violations
                 -> Value  -- ^ Metadata
                 -> m (Entity CodeQuality)
recordCodeQuality pool projectId branch commitId metricType complexity duplications violations metadata = do
    now <- liftIO getCurrentTime
    let metricId = generateMetricId "quality" projectId branch now
    let qualityScore = calculateQualityScoreFromMetrics complexity duplications violations
    let quality = CodeQuality
            { codeQualityMetricId = metricId
            , codeQualityProjectId = projectId
            , codeQualityBranch = branch
            , codeQualityCommitId = commitId
            , codeQualityMetricType = metricType
            , codeQualityComplexity = complexity
            , codeQualityDuplications = duplications
            , codeQualityViolations = violations
            , codeQualityQualityScore = qualityScore
            , codeQualityMetadata = metadata
            , codeQualityTimestamp = now
            }
    runSqlPool (insertEntity quality) pool

-- | Record test coverage metrics
recordTestCoverage :: MonadIO m
                   => ConnectionPool
                   -> Text  -- ^ Project ID
                   -> Text  -- ^ Branch
                   -> Maybe Text  -- ^ Commit ID
                   -> Double  -- ^ Line coverage
                   -> Double  -- ^ Branch coverage
                   -> Maybe Double  -- ^ Mutation score
                   -> Int    -- ^ Test count
                   -> Int    -- ^ Test duration
                   -> Value  -- ^ Metadata
                   -> m (Entity TestCoverage)
recordTestCoverage pool projectId branch commitId lineCov branchCov mutationScore testCount duration metadata = do
    now <- liftIO getCurrentTime
    let metricId = generateMetricId "coverage" projectId branch now
    let qualityScore = calculateCoverageScore lineCov branchCov mutationScore
    let coverage = TestCoverage
            { testCoverageMetricId = metricId
            , testCoverageProjectId = projectId
            , testCoverageBranch = branch
            , testCoverageCommitId = commitId
            , testCoverageLineCoverage = lineCov
            , testCoverageBranchCoverage = branchCov
            , testCoverageMutationScore = mutationScore
            , testCoverageTestCount = testCount
            , testCoverageTestDuration = duration
            , testCoverageQualityScore = qualityScore
            , testCoverageMetadata = metadata
            , testCoverageTimestamp = now
            }
    runSqlPool (insertEntity coverage) pool

-- | Record technical debt item
recordTechnicalDebt :: MonadIO m
                    => ConnectionPool
                    -> Text  -- ^ Project ID
                    -> Text  -- ^ Category
                    -> Text  -- ^ Description
                    -> Text  -- ^ Severity
                    -> Int   -- ^ Effort (minutes)
                    -> Double  -- ^ Cost
                    -> Value  -- ^ Metadata
                    -> m (Entity TechnicalDebt)
recordTechnicalDebt pool projectId category description severity effort cost metadata = do
    now <- liftIO getCurrentTime
    let metricId = generateMetricId "debt" projectId category now
    let debt = TechnicalDebt
            { technicalDebtMetricId = metricId
            , technicalDebtProjectId = projectId
            , technicalDebtCategory = category
            , technicalDebtDescription = description
            , technicalDebtSeverity = severity
            , technicalDebtEffort = effort
            , technicalDebtCost = cost
            , technicalDebtCreated = now
            , technicalDebtUpdated = now
            , technicalDebtResolvedAt = Nothing
            , technicalDebtMetadata = metadata
            }
    runSqlPool (insertEntity debt) pool

-- | Get code quality metrics with filtering
getCodeQualityMetrics :: MonadIO m
                      => ConnectionPool
                      -> Text  -- ^ Project ID
                      -> Maybe Text  -- ^ Branch
                      -> Maybe QualityType  -- ^ Metric type
                      -> UTCTime  -- ^ Start time
                      -> UTCTime  -- ^ End time
                      -> m [Entity CodeQuality]
getCodeQualityMetrics pool projectId mBranch mType start end = do
    let filters = concat
            [ [CodeQualityProjectId ==. projectId]
            , maybe [] (\b -> [CodeQualityBranch ==. b]) mBranch
            , maybe [] (\t -> [CodeQualityMetricType ==. t]) mType
            , [CodeQualityTimestamp >=. start]
            , [CodeQualityTimestamp <=. end]
            ]
    runSqlPool (selectList filters [Desc CodeQualityTimestamp]) pool

-- | Get test coverage metrics with filtering
getTestCoverageMetrics :: MonadIO m
                       => ConnectionPool
                       -> Text  -- ^ Project ID
                       -> Maybe Text  -- ^ Branch
                       -> UTCTime  -- ^ Start time
                       -> UTCTime  -- ^ End time
                       -> m [Entity TestCoverage]
getTestCoverageMetrics pool projectId mBranch start end = do
    let filters = concat
            [ [TestCoverageProjectId ==. projectId]
            , maybe [] (\b -> [TestCoverageBranch ==. b]) mBranch
            , [TestCoverageTimestamp >=. start]
            , [TestCoverageTimestamp <=. end]
            ]
    runSqlPool (selectList filters [Desc TestCoverageTimestamp]) pool

-- | Get technical debt metrics with filtering
getTechnicalDebtMetrics :: MonadIO m
                        => ConnectionPool
                        -> Text  -- ^ Project ID
                        -> Maybe Text  -- ^ Category
                        -> Maybe Text  -- ^ Severity
                        -> Bool  -- ^ Include resolved
                        -> m [Entity TechnicalDebt]
getTechnicalDebtMetrics pool projectId mCategory mSeverity includeResolved = do
    let filters = concat
            [ [TechnicalDebtProjectId ==. projectId]
            , maybe [] (\c -> [TechnicalDebtCategory ==. c]) mCategory
            , maybe [] (\s -> [TechnicalDebtSeverity ==. s]) mSeverity
            , if not includeResolved
                then [TechnicalDebtResolvedAt ==. Nothing]
                else []
            ]
    runSqlPool (selectList filters [Desc TechnicalDebtCreated]) pool

-- | Calculate overall quality score
calculateQualityScore :: MonadIO m
                     => ConnectionPool
                     -> Text  -- ^ Project ID
                     -> UTCTime  -- ^ Start time
                     -> UTCTime  -- ^ End time
                     -> m Double
calculateQualityScore pool projectId start end = do
    -- This would combine various metrics into a single score
    -- Implementation would depend on specific requirements
    return 0.0

-- | Track quality trends over time
trackQualityTrends :: MonadIO m
                   => ConnectionPool
                   -> Text  -- ^ Project ID
                   -> UTCTime  -- ^ Start time
                   -> UTCTime  -- ^ End time
                   -> m [(UTCTime, Double, Text)]  -- (time, score, trend)
trackQualityTrends pool projectId start end = do
    -- This would analyze trends in quality metrics
    -- Implementation would depend on specific requirements
    return []

-- Helper functions

-- | Calculate quality score from code metrics
calculateQualityScoreFromMetrics :: Int -> Double -> Int -> QualityScore
calculateQualityScoreFromMetrics complexity duplications violations =
    let complexityScore = 100 * (1 / (1 + fromIntegral complexity / 1000))
        duplicationScore = 100 * (1 - duplications / 100)
        violationScore = 100 * (1 / (1 + fromIntegral violations / 100))
        totalScore = (complexityScore + duplicationScore + violationScore) / 3
    in QualityScore
        { score = totalScore
        , weight = 1.0
        , details = object
            [ "complexity_score" .= complexityScore
            , "duplication_score" .= duplicationScore
            , "violation_score" .= violationScore
            ]
        }

-- | Calculate quality score from coverage metrics
calculateCoverageScore :: Double -> Double -> Maybe Double -> QualityScore
calculateCoverageScore lineCov branchCov mutationScore =
    let lineScore = 100 * (lineCov / 100)
        branchScore = 100 * (branchCov / 100)
        mutationScore' = maybe 0 (\m -> 100 * (m / 100)) mutationScore
        totalScore = (lineScore + branchScore + mutationScore') / 3
    in QualityScore
        { score = totalScore
        , weight = 1.0
        , details = object
            [ "line_coverage_score" .= lineScore
            , "branch_coverage_score" .= branchScore
            , "mutation_score" .= mutationScore'
            ]
        }

-- | Generate metric ID
generateMetricId :: Text -> Text -> Text -> UTCTime -> Text
generateMetricId prefix projectId component timestamp =
    prefix <> "_" <> Text.filter isAllowed (projectId <> "_" <> component) <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

formatTime :: UTCTime -> Text
formatTime = Text.pack . show
