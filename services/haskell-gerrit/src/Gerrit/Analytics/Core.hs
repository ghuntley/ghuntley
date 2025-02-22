-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Analytics.Core
    ( calculateActivityMetrics
    , calculateQualityMetrics
    , calculateContributorMetrics
    , aggregateMetrics
    , generateMetricsReport
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime, diffUTCTime)
import Database.Esqueleto
import Gerrit.Analytics.Types
import Gerrit.Models.Types
import Gerrit.Database.Schema
import Gerrit.Git.Operations (getDiff)
import qualified NLP.Sentiment as Sentiment

-- | Calculate activity metrics for a given time range
calculateActivityMetrics :: MonadIO m
                       => UTCTime  -- ^ Start time
                       -> UTCTime  -- ^ End time
                       -> SqlPersistT m ActivityMetrics
calculateActivityMetrics start end = do
    -- Calculate changes per day
    changes <- select $ from $ \(change `InnerJoin` project) -> do
        on (change ^. ChangeProject ==. project ^. ProjectId)
        where_ (change ^. ChangeCreatedAt >=. val start &&.
                change ^. ChangeCreatedAt <=. val end)
        return change

    -- Calculate reviews per day
    reviews <- select $ from $ \review -> do
        where_ (review ^. ReviewCreatedAt >=. val start &&.
                review ^. ReviewCreatedAt <=. val end)
        return review

    -- Calculate code churn
    let calculateChurn change = do
            diff <- getDiff (changeId change)
            return $ length $ lines diff

    churn <- mapM calculateChurn changes
    let totalChurn = sum churn
        daysInRange = realToFrac $ diffUTCTime end start / (24 * 3600)
        churnRate = totalChurn / daysInRange

    -- Calculate review depth
    comments <- select $ from $ \comment -> do
        where_ (comment ^. CommentCreatedAt >=. val start &&.
                comment ^. CommentCreatedAt <=. val end)
        return comment

    let totalComments = length comments
        totalLines = sum $ map (length . lines . commentText) comments
        reviewDepth = if totalLines == 0
                     then 0
                     else fromIntegral totalComments / fromIntegral totalLines

    -- Calculate file modification frequency
    fileChanges <- select $ from $ \change -> do
        where_ (change ^. ChangeCreatedAt >=. val start &&.
                change ^. ChangeCreatedAt <=. val end)
        return (change ^. ChangeFile)

    let fileFreq = foldr (\file acc -> Map.insertWith (+) file 1 acc)
                        Map.empty
                        fileChanges

    -- Calculate sentiment scores
    let calcSentiment comments =
            let text = T.concat $ map commentText comments
            in Sentiment.analyze text

    fileSentiments <- mapM (\(file, comments) -> do
        sentiment <- calcSentiment comments
        return (file, sentiment)
        ) $ Map.toList $ groupCommentsByFile comments

    -- Return complete metrics
    return ActivityMetrics
        { amChangesPerDay = groupByDay changes
        , amReviewsPerDay = groupByDay reviews
        , amCodeChurnRate = churnRate
        , amReviewThroughput = fromIntegral (length reviews) / daysInRange
        , amReviewTimeDistribution = calculateReviewTimes reviews
        , amComplexityTrends = calculateComplexityTrends changes
        , amTestCoverage = calculateTestCoverage changes
        , amReviewDepth = reviewDepth
        , amBugRate = calculateBugRate changes
        , amFileModFrequency = fileFreq
        , amCommitSizeDistribution = calculateCommitSizeDistribution changes
        , amBranchActivity = calculateBranchActivity changes
        , amTimeToFirstReview = calculateTimeToFirstReview reviews
        , amReviewCycleTime = calculateReviewCycleTime reviews
        , amMergeSuccessRate = calculateMergeSuccessRate changes
        , amCommentSentiment = Map.fromList fileSentiments
        , amCodeOwnership = calculateCodeOwnership changes
        }

-- | Calculate quality metrics
calculateQualityMetrics :: MonadIO m
                       => UTCTime
                       -> UTCTime
                       -> SqlPersistT m QualityMetrics
calculateQualityMetrics start end = do
    -- Implementation details for quality metrics calculation
    return QualityMetrics
        { qmCodeCoverage = 0.0  -- TODO: Implement
        , qmReviewCoverage = 0.0
        , qmDocScore = 0.0
        , qmTestScore = 0.0
        , qmStyleScore = 0.0
        , qmTechnicalDebt = DebtScore 0.0 0.0 0.0 0.0 0.0
        , qmDefectRate = 0.0
        , qmCyclomaticComplexity = Map.empty
        , qmDuplicationRate = 0.0
        , qmTestToCodeRatio = 0.0
        , qmDocFreshness = Map.empty
        , qmApiStability = 0.0
        , qmBreakingChanges = 0
        , qmBackwardCompatibility = 0.0
        , qmSecurityScore = 0.0
        , qmPerformanceScore = 0.0
        }

-- | Calculate contributor metrics
calculateContributorMetrics :: MonadIO m
                          => UTCTime
                          -> UTCTime
                          -> SqlPersistT m ContributorMetrics
calculateContributorMetrics start end = do
    -- Implementation details for contributor metrics calculation
    return ContributorMetrics
        { cmCommitFrequency = Map.empty
        , cmReviewParticipation = Map.empty
        , cmLinesChanged = Map.empty
        , cmAverageReviewTime = Map.empty
        , cmMergeSuccessRate = Map.empty
        , cmCommentActivity = Map.empty
        , cmTrends = Map.empty
        , cmKnowledgeIndex = Map.empty
        , cmCollaborationScore = Map.empty
        , cmReviewLoad = Map.empty
        , cmExpertise = Map.empty
        , cmResponsePatterns = Map.empty
        , cmReviewThoroughness = Map.empty
        , cmMentorshipScore = Map.empty
        , cmTeamVelocityImpact = Map.empty
        , cmWorkPatterns = Map.empty
        }

-- | Aggregate metrics into a comprehensive report
aggregateMetrics :: MonadIO m
                 => ActivityMetrics
                 -> QualityMetrics
                 -> ContributorMetrics
                 -> m MetricsReport
aggregateMetrics activity quality contributor = do
    -- Implementation details for metrics aggregation
    undefined  -- TODO: Implement

-- | Generate a metrics report
generateMetricsReport :: MonadIO m
                     => MetricsReport
                     -> ReportFormat
                     -> m ReportOutput
generateMetricsReport report format = do
    -- Implementation details for report generation
    undefined  -- TODO: Implement

-- Helper functions

groupByDay :: [Entity record] -> Map UTCTime Int
groupByDay records = Map.fromListWith (+)
    [ (utcMidnight $ entityCreatedAt record, 1)
    | Entity _ record <- records
    ]
  where
    entityCreatedAt record = case record of
        Change{..} -> changeCreatedAt
        Review{..} -> reviewCreatedAt
        Comment{..} -> commentCreatedAt
        _ -> error "Unsupported record type"

    utcMidnight time = UTCTime (utctDay time) 0

calculateReviewTimes :: [Entity Review] -> [Int]
calculateReviewTimes reviews =
    [ diffMinutes (reviewCreatedAt review) (changeCreatedAt change)
    | Entity _ review <- reviews
    , Just change <- [lookupChange (reviewChangeId review)]
    ]
  where
    diffMinutes t1 t2 = round $ diffUTCTime t1 t2 / 60

calculateComplexityTrends :: [Entity Change] -> Map UTCTime Double
calculateComplexityTrends changes = Map.fromListWith (+)
    [ (changeCreatedAt change, calculateChangeComplexity change)
    | Entity _ change <- changes
    ]
  where
    calculateChangeComplexity change =
        let diffLines = length $ lines $ changeDiff change
            fileCount = length $ changeFiles change
        in fromIntegral diffLines * (1 + logBase 2 (fromIntegral fileCount))

calculateTestCoverage :: [Entity Change] -> Map UTCTime Double
calculateTestCoverage changes = Map.fromListWith avg
    [ (changeCreatedAt change, getTestCoverage change)
    | Entity _ change <- changes
    ]
  where
    avg x y = (x + y) / 2
    getTestCoverage change =
        let testFiles = filter isTestFile $ changeFiles change
            totalFiles = changeFiles change
        in if null totalFiles
           then 0.0
           else fromIntegral (length testFiles) / fromIntegral (length totalFiles)
    isTestFile file = "test" `T.isInfixOf` T.toLower file
                   || "spec" `T.isInfixOf` T.toLower file

calculateBugRate :: [Entity Change] -> Double
calculateBugRate changes =
    let bugFixes = length $ filter isBugFix changes
        totalLines = sum $ map (length . lines . changeDiff) changes
    in if totalLines == 0
       then 0.0
       else 1000 * fromIntegral bugFixes / fromIntegral totalLines
  where
    isBugFix change = "fix" `T.isInfixOf` T.toLower (changeSubject change)
                   || "bug" `T.isInfixOf` T.toLower (changeSubject change)

calculateCommitSizeDistribution :: [Entity Change] -> [(Int, Int)]
calculateCommitSizeDistribution changes =
    let sizes = map (length . lines . changeDiff) changes
        buckets = [0, 10, 50, 100, 500, 1000, maxBound]
        counts = Map.fromListWith (+)
            [ (findBucket size buckets, 1)
            | size <- sizes
            ]
    in Map.toList counts
  where
    findBucket n (x:y:rest)
        | n <= y = x
        | otherwise = findBucket n (y:rest)
    findBucket n [x] = x
    findBucket _ [] = 0

calculateBranchActivity :: [Entity Change] -> Map Text ActivityLevel
calculateBranchActivity changes =
    let branchCounts = Map.fromListWith (+)
            [ (changeBranch change, 1)
            | Entity _ change <- changes
            ]
        maxCount = maximum (0 : Map.elems branchCounts)
    in Map.map (activityLevel maxCount) branchCounts
  where
    activityLevel maxCount count
        | ratio <= 0.25 = Low
        | ratio <= 0.50 = Medium
        | ratio <= 0.75 = High
        | otherwise = Critical
      where ratio = fromIntegral count / fromIntegral maxCount

calculateTimeToFirstReview :: [Entity Review] -> Int
calculateTimeToFirstReview reviews =
    let reviewTimes = Map.fromListWith min
            [ (reviewChangeId review, diffMinutes (reviewCreatedAt review) (changeCreatedAt change))
            | Entity _ review <- reviews
            , Just change <- [lookupChange (reviewChangeId review)]
            ]
    in if Map.null reviewTimes
       then 0
       else round $ sum (Map.elems reviewTimes) / fromIntegral (Map.size reviewTimes)
  where
    diffMinutes t1 t2 = diffUTCTime t1 t2 / 60

calculateReviewCycleTime :: [Entity Review] -> Int
calculateReviewCycleTime reviews =
    let cycleTimes = Map.fromListWith (+)
            [ (reviewChangeId review, diffMinutes (reviewCreatedAt review) (changeCreatedAt change))
            | Entity _ review <- reviews
            , Just change <- [lookupChange (reviewChangeId review)]
            ]
    in if Map.null cycleTimes
       then 0
       else round $ sum (Map.elems cycleTimes) / fromIntegral (Map.size cycleTimes)
  where
    diffMinutes t1 t2 = diffUTCTime t1 t2 / 60

calculateMergeSuccessRate :: [Entity Change] -> Map Int Double
calculateMergeSuccessRate changes =
    let hourlyAttempts = Map.fromListWith (+)
            [ (hour, (if changeStatus change == Merged then 1 else 0, 1))
            | Entity _ change <- changes
            , let hour = getHour $ changeCreatedAt change
            ]
    in Map.map (\(successes, total) ->
        fromIntegral successes / fromIntegral total) hourlyAttempts
  where
    getHour time = todHour $ timeToTimeOfDay $ utctDayTime time

calculateCodeOwnership :: [Entity Change] -> Map Text Text
calculateCodeOwnership changes =
    let ownership = Map.fromListWith mostRecent
            [ (file, (changeCreatedAt change, changeAuthorId change))
            | Entity _ change <- changes
            , file <- changeFiles change
            ]
    in Map.map snd ownership
  where
    mostRecent (t1, a1) (t2, a2) = if t1 > t2 then (t1, a1) else (t2, a2)

groupCommentsByFile :: [Entity Comment] -> Map Text [Comment]
groupCommentsByFile comments = Map.fromListWith (++)
    [ (commentFile comment, [comment])
    | Entity _ comment <- comments
    , Just file <- [commentFilePath comment]
    ]
