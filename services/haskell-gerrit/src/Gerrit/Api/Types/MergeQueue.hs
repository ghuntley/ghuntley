-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Types.MergeQueue
    ( -- * Request Types
      EnqueueRequest(..)
    , UpdateQueueItemRequest(..)
    , mkEnqueueRequest
    , mkUpdateRequest
      -- * Status Types
    , QueueItemStatus(..)
    , ValidationStatus(..)
    , MergeStatus(..)
    , isTerminalStatus
    , canTransitionTo
    , statusToText
    , textToStatus
      -- * Response Types
    , QueueItemResponse(..)
    , QueueStatusResponse(..)
    , QueueMetricsResponse(..)
    , SuccessResponse(..)
    , ErrorResponse(..)
      -- * Helper Types
    , QueuePriority(..)
    , RetryPolicy(..)
    , ValidationResult(..)
    , defaultRetryPolicy
    , mkRetryPolicy
    , mkValidationResult
      -- * Utility Functions
    , calculateErrorRate
    , calculateLatency
    , isValidChangeId
    , validateDependencies
    , calculateBackoff
    , shouldRetry
    , isQueueHealthy
    , summarizeQueueMetrics
    ) where

import Control.Monad (when, unless)
import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, NominalDiffTime, diffUTCTime)
import GHC.Generics
import Data.List (nub)
import Data.Maybe (isJust)
import Data.Time.Clock.POSIX (POSIXTime, getPOSIXTime)
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific, fromFloatDigits)

-- | Priority levels for queue items
data QueuePriority
    = PriorityHigh
    | PriorityNormal
    | PriorityLow
    deriving (Show, Eq, Ord, Generic)

instance FromJSON QueuePriority where
    parseJSON = withText "QueuePriority" $ \case
        "high" -> pure PriorityHigh
        "normal" -> pure PriorityNormal
        "low" -> pure PriorityLow
        _ -> fail "Invalid priority level"

instance ToJSON QueuePriority where
    toJSON = String . \case
        PriorityHigh -> "high"
        PriorityNormal -> "normal"
        PriorityLow -> "low"

-- | Retry policy for failed merge attempts
data RetryPolicy = RetryPolicy
    { rpMaxAttempts :: Int       -- ^ Maximum number of retry attempts
    , rpBackoff :: NominalDiffTime  -- ^ Time to wait between retries
    , rpMaxBackoff :: NominalDiffTime -- ^ Maximum backoff time
    , rpJitter :: Double  -- Random jitter factor (0-1)
    } deriving (Show, Eq, Generic)

instance FromJSON RetryPolicy where
    parseJSON = withObject "RetryPolicy" $ \v -> do
        rpMaxAttempts <- v .: "maxAttempts"
        rpBackoff <- fromInteger <$> v .: "backoffSeconds"
        rpMaxBackoff <- fromInteger <$> v .: "maxBackoffSeconds"
        rpJitter <- v .: "jitter"
        when (rpMaxAttempts <= 0) $
            fail "Max attempts must be positive"
        when (rpBackoff <= 0) $
            fail "Backoff duration must be positive"
        when (rpMaxBackoff < rpBackoff) $
            fail "Max backoff must be greater than base backoff"
        when (rpJitter < 0 || rpJitter > 1) $
            fail "Jitter must be between 0 and 1"
        pure RetryPolicy{..}

instance ToJSON RetryPolicy where
    toJSON RetryPolicy{..} = object
        [ "maxAttempts" .= rpMaxAttempts
        , "backoffSeconds" .= round rpBackoff
        , "maxBackoffSeconds" .= round rpMaxBackoff
        , "jitter" .= rpJitter
        ]

-- | Validation status for queue items
data ValidationStatus
    = ValidationPending
    | ValidationInProgress
    | ValidationPassed
    | ValidationFailed Text
    deriving (Show, Eq, Generic)

instance FromJSON ValidationStatus
instance ToJSON ValidationStatus

-- | Merge status for queue items
data MergeStatus
    = MergePending
    | MergeInProgress
    | MergeSucceeded
    | MergeFailed Text
    | MergeConflict Text
    deriving (Show, Eq, Generic)

instance FromJSON MergeStatus
instance ToJSON MergeStatus

-- | Result of validation checks
data ValidationResult = ValidationResult
    { vrName :: Text
    , vrStatus :: ValidationStatus
    , vrStartTime :: UTCTime
    , vrEndTime :: Maybe UTCTime
    , vrOutput :: Maybe Text
    , vrMetrics :: Map Text Scientific
    } deriving (Show, Eq, Generic)

instance FromJSON ValidationResult where
    parseJSON = withObject "ValidationResult" $ \v -> do
        vrName <- v .: "name"
        vrStatus <- v .: "status"
        vrStartTime <- v .: "startTime"
        vrEndTime <- v .:? "endTime"
        vrOutput <- v .:? "output"
        vrMetrics <- v .:? "metrics" .!= Map.empty
        pure ValidationResult{..}

instance ToJSON ValidationResult where
    toJSON ValidationResult{..} = object
        [ "name" .= vrName
        , "status" .= vrStatus
        , "startTime" .= vrStartTime
        , "endTime" .= vrEndTime
        , "output" .= vrOutput
        , "metrics" .= vrMetrics
        , "duration" .= fmap (flip diffUTCTime vrStartTime) vrEndTime
        ]

-- | Request to enqueue a change
data EnqueueRequest = EnqueueRequest
    { eqrChangeId :: Text          -- ^ ID of the change to enqueue
    , eqrStackId :: Maybe Text     -- ^ Optional stack ID if part of a stack
    , eqrDependencies :: [Text]    -- ^ List of change IDs this change depends on
    , eqrPriority :: QueuePriority -- ^ Priority level for processing
    , eqrRetryPolicy :: Maybe RetryPolicy -- ^ Optional custom retry policy
    } deriving (Show, Generic)

instance FromJSON EnqueueRequest where
    parseJSON = withObject "EnqueueRequest" $ \v -> do
        eqrChangeId <- v .: "changeId"
        eqrStackId <- v .:? "stackId"
        eqrDependencies <- v .:? "dependencies" .!= []
        eqrPriority <- v .:? "priority" .!= PriorityNormal
        eqrRetryPolicy <- v .:? "retryPolicy"
        pure EnqueueRequest{..}

instance ToJSON EnqueueRequest

-- | Request to update a queue item
data UpdateQueueItemRequest = UpdateQueueItemRequest
    { uqrPriority :: QueuePriority     -- ^ New priority level
    , uqrStatus :: QueueItemStatus     -- ^ New status
    , uqrRetryPolicy :: Maybe RetryPolicy  -- ^ Updated retry policy
    } deriving (Show, Generic)

instance FromJSON UpdateQueueItemRequest
instance ToJSON UpdateQueueRequest

-- | Queue item status
data QueueItemStatus
    = Queued
    | Processing
    | Validating ValidationStatus
    | Merging MergeStatus
    | Completed
    | Failed Text
    | Cancelled
    deriving (Show, Eq, Generic)

instance FromJSON QueueItemStatus
instance ToJSON QueueItemStatus

-- | Queue item response
data QueueItemResponse = QueueItemResponse
    { qirId :: Text                -- ^ Queue item ID
    , qirChangeId :: Text          -- ^ Change ID
    , qirStackId :: Maybe Text     -- ^ Stack ID if part of a stack
    , qirDependencies :: [Text]    -- ^ Dependencies
    , qirPriority :: QueuePriority -- ^ Current priority
    , qirRetries :: Int            -- ^ Number of retry attempts
    , qirSubmitted :: UTCTime      -- ^ When the item was queued
    , qirStarted :: Maybe UTCTime  -- ^ When processing started
    , qirCompleted :: Maybe UTCTime -- ^ When processing completed
    , qirStatus :: QueueItemStatus -- ^ Current status
    , qirError :: Maybe Text       -- ^ Error message if failed
    , qirValidations :: [ValidationResult] -- ^ Validation results
    } deriving (Show, Generic)

instance FromJSON QueueItemResponse
instance ToJSON QueueItemResponse

-- | Queue status response
data QueueStatusResponse = QueueStatusResponse
    { qsrActive :: Bool            -- ^ Whether queue is processing
    , qsrSize :: Int              -- ^ Total items in queue
    , qsrProcessing :: Int        -- ^ Items currently processing
    , qsrLastProcessed :: Maybe UTCTime -- ^ Last processed timestamp
    , qsrErrors :: Int            -- ^ Number of errors
    , qsrPaused :: Bool           -- ^ Whether queue is paused
    , qsrMaxConcurrent :: Int     -- ^ Maximum concurrent processing
    } deriving (Show, Generic)

instance FromJSON QueueStatusResponse
instance ToJSON QueueStatusResponse

-- | Queue metrics response
data QueueMetricsResponse = QueueMetricsResponse
    { qmrTotalProcessed :: Int     -- ^ Total items processed
    , qmrSuccessful :: Int         -- ^ Successfully processed items
    , qmrFailed :: Int             -- ^ Failed items
    , qmrErrorRate :: Double       -- ^ Error rate percentage
    , qmrAverageWaitTime :: Double -- ^ Average wait time in queue
    , qmrAverageProcessTime :: Double -- ^ Average processing time
    , qmrQueueLatency :: Double    -- ^ Current queue latency
    , qmrThroughput :: Double      -- ^ Items processed per minute
    , qmrConcurrentMerges :: Int   -- ^ Number of concurrent merges
    } deriving (Show, Eq, Generic)

instance FromJSON QueueMetricsResponse
instance ToJSON QueueMetricsResponse where
    toJSON qmr@QueueMetricsResponse{..} = object
        [ "totalProcessed" .= qmrTotalProcessed
        , "successful" .= qmrSuccessful
        , "failed" .= qmrFailed
        , "errorRate" .= qmrErrorRate
        , "averageWaitTime" .= qmrAverageWaitTime
        , "averageProcessTime" .= qmrAverageProcessTime
        , "queueLatency" .= qmrQueueLatency
        , "throughput" .= qmrThroughput
        , "concurrentMerges" .= qmrConcurrentMerges
        , "summary" .= summarizeQueueMetrics qmr
        ]

-- | Generic success response
data SuccessResponse = SuccessResponse
    { srSuccess :: Bool              -- ^ Operation success status
    , srMessage :: Maybe Text        -- ^ Optional success message
    , srDetails :: Maybe Value       -- ^ Additional response details
    } deriving (Show, Eq, Generic)

instance FromJSON SuccessResponse
instance ToJSON SuccessResponse

-- | Generic error response
data ErrorResponse = ErrorResponse
    { erError :: Text                -- ^ Error message
    , erCode :: Text                -- ^ Error code
    , erDetails :: Maybe Value      -- ^ Additional error details
    , erRetryAfter :: Maybe Int      -- ^ Retry after in seconds
    } deriving (Show, Eq, Generic)

instance FromJSON ErrorResponse
instance ToJSON ErrorResponse

-- | Default retry policy
defaultRetryPolicy :: RetryPolicy
defaultRetryPolicy = RetryPolicy
    { rpMaxAttempts = 3
    , rpBackoff = 60  -- 1 minute
    , rpMaxBackoff = 3600  -- 1 hour
    , rpJitter = 0.1  -- 10% jitter
    }

-- | Smart constructor for retry policy
mkRetryPolicy :: Int -> NominalDiffTime -> NominalDiffTime -> Double -> Either Text RetryPolicy
mkRetryPolicy maxAttempts backoff maxBackoff jitter
    | maxAttempts <= 0 = Left "Max attempts must be positive"
    | backoff <= 0 = Left "Backoff duration must be positive"
    | maxBackoff < backoff = Left "Max backoff must be greater than base backoff"
    | jitter < 0 || jitter > 1 = Left "Jitter must be between 0 and 1"
    | otherwise = Right RetryPolicy{..}

-- | Smart constructor for enqueue request
mkEnqueueRequest :: Text -> Maybe Text -> [Text] -> QueuePriority -> Maybe RetryPolicy -> Either Text EnqueueRequest
mkEnqueueRequest changeId stackId deps priority retryPolicy = do
    unless (isValidChangeId changeId) $
        Left "Invalid change ID format"
    case stackId of
        Just sid -> unless (isValidChangeId sid) $
            Left "Invalid stack ID format"
        Nothing -> pure ()
    validateDependencies deps
    pure EnqueueRequest{..}
  where
    eqrChangeId = changeId
    eqrStackId = stackId
    eqrDependencies = deps
    eqrPriority = priority
    eqrRetryPolicy = retryPolicy

-- | Smart constructor for update request
mkUpdateRequest :: QueuePriority -> QueueItemStatus -> Maybe RetryPolicy -> Either Text UpdateQueueItemRequest
mkUpdateRequest priority status retryPolicy = do
    validateStatusTransition status
    pure UpdateQueueItemRequest{..}
  where
    uqrPriority = priority
    uqrStatus = status
    uqrRetryPolicy = retryPolicy

-- | Smart constructor for validation result
mkValidationResult :: Text -> ValidationStatus -> UTCTime -> ValidationResult
mkValidationResult name status startTime = ValidationResult
    { vrName = name
    , vrStatus = status
    , vrStartTime = startTime
    , vrEndTime = Nothing
    , vrOutput = Nothing
    , vrMetrics = Map.empty
    }

-- | Check if a status is terminal (no further transitions possible)
isTerminalStatus :: QueueItemStatus -> Bool
isTerminalStatus Completed = True
isTerminalStatus (Failed _) = True
isTerminalStatus Cancelled = True
isTerminalStatus _ = False

-- | Validate if a status transition is allowed
canTransitionTo :: QueueItemStatus -> QueueItemStatus -> Bool
canTransitionTo Queued Processing = True
canTransitionTo Processing (Validating _) = True
canTransitionTo (Validating ValidationPassed) (Merging _) = True
canTransitionTo (Merging MergeSucceeded) Completed = True
canTransitionTo _ Cancelled = True
canTransitionTo _ (Failed _) = True
canTransitionTo _ _ = False

-- | Validate status transition
validateStatusTransition :: QueueItemStatus -> Either Text ()
validateStatusTransition status
    | isTerminalStatus status = Right ()
    | otherwise = Left "Invalid status transition"

-- | Validate change ID format
isValidChangeId :: Text -> Bool
isValidChangeId changeId =
    T.length changeId == 40 &&  -- SHA-1 length
    T.all isHexDigit changeId

-- | Validate dependencies
validateDependencies :: [Text] -> Either Text [Text]
validateDependencies deps = do
    let uniqueDeps = nub deps
    when (length uniqueDeps /= length deps) $
        Left "Duplicate dependencies found"
    forM_ uniqueDeps $ \dep ->
        unless (isValidChangeId dep) $
            Left $ "Invalid change ID format: " <> dep
    Right uniqueDeps

-- | Calculate error rate from metrics
calculateErrorRate :: Int -> Int -> Double
calculateErrorRate total failed
    | total == 0 = 0.0
    | otherwise = fromIntegral failed / fromIntegral total * 100.0

-- | Calculate queue latency
calculateLatency :: UTCTime -> [QueueItemResponse] -> Double
calculateLatency now items =
    let completedItems = filter (isJust . qirCompleted) items
        latencies = map calculateItemLatency completedItems
    in if null latencies then 0.0 else sum latencies / fromIntegral (length latencies)
  where
    calculateItemLatency item =
        let submitted = qirSubmitted item
            completed = maybe now id (qirCompleted item)
        in realToFrac $ diffUTCTime completed submitted

-- | Calculate next backoff duration
calculateBackoff :: RetryPolicy -> Int -> NominalDiffTime
calculateBackoff RetryPolicy{..} attempt =
    min rpMaxBackoff $ rpBackoff * (2 ^ attempt)

-- | Check if should retry based on policy
shouldRetry :: RetryPolicy -> Int -> Bool
shouldRetry RetryPolicy{..} attempts = attempts < rpMaxAttempts

-- | Check if queue is healthy based on metrics
isQueueHealthy :: QueueMetricsResponse -> Bool
isQueueHealthy QueueMetricsResponse{..} =
    qmrErrorRate < 10.0 &&  -- Less than 10% error rate
    qmrQueueLatency < 300.0 &&  -- Less than 5 minutes latency
    qmrThroughput > 0.0  -- Some throughput

-- | Generate a summary of queue metrics
summarizeQueueMetrics :: QueueMetricsResponse -> Map.Map Text Scientific
summarizeQueueMetrics QueueMetricsResponse{..} = Map.fromList
    [ ("success_rate", fromFloatDigits $ 100.0 - qmrErrorRate)
    , ("throughput_per_hour", fromFloatDigits $ qmrThroughput * 60)
    , ("avg_wait_minutes", fromFloatDigits $ qmrAverageWaitTime / 60)
    , ("avg_process_minutes", fromFloatDigits $ qmrAverageProcessTime / 60)
    , ("health_score", calculateHealthScore)
    ]
  where
    calculateHealthScore = fromFloatDigits $
        let successWeight = 0.4
            latencyWeight = 0.3
            throughputWeight = 0.3
            successScore = (100.0 - qmrErrorRate) * successWeight
            latencyScore = (1.0 - min 1.0 (qmrQueueLatency / 300.0)) * 100 * latencyWeight
            throughputScore = min 100.0 (qmrThroughput * 10) * throughputWeight
        in successScore + latencyScore + throughputScore

-- | Convert status to text representation
statusToText :: QueueItemStatus -> Text
statusToText Queued = "queued"
statusToText Processing = "processing"
statusToText (Validating vs) = case vs of
    ValidationPending -> "validating_pending"
    ValidationInProgress -> "validating_in_progress"
    ValidationPassed -> "validating_passed"
    ValidationFailed _ -> "validating_failed"
statusToText (Merging ms) = case ms of
    MergePending -> "merging_pending"
    MergeInProgress -> "merging_in_progress"
    MergeSucceeded -> "merging_succeeded"
    MergeFailed _ -> "merging_failed"
    MergeConflict _ -> "merging_conflict"
statusToText Completed = "completed"
statusToText (Failed _) = "failed"
statusToText Cancelled = "cancelled"

-- | Convert text to status
textToStatus :: Text -> Maybe QueueItemStatus
textToStatus = \case
    "queued" -> Just Queued
    "processing" -> Just Processing
    "validating_pending" -> Just $ Validating ValidationPending
    "validating_in_progress" -> Just $ Validating ValidationInProgress
    "validating_passed" -> Just $ Validating ValidationPassed
    "merging_pending" -> Just $ Merging MergePending
    "merging_in_progress" -> Just $ Merging MergeInProgress
    "merging_succeeded" -> Just $ Merging MergeSucceeded
    "completed" -> Just Completed
    "cancelled" -> Just Cancelled
    _ -> Nothing

instance FromJSON QueueItemResponse where
    parseJSON = withObject "QueueItemResponse" $ \v -> do
        qirId <- v .: "id"
        qirChangeId <- v .: "changeId"
        qirStackId <- v .:? "stackId"
        qirDependencies <- v .:? "dependencies" .!= []
        qirPriority <- v .: "priority"
        qirRetries <- v .: "retries"
        qirSubmitted <- v .: "submitted"
        qirStarted <- v .:? "started"
        qirCompleted <- v .:? "completed"
        qirStatus <- v .: "status"
        qirError <- v .:? "error"
        qirValidations <- v .:? "validations" .!= []
        when (qirRetries < 0) $
            fail "Retries cannot be negative"
        pure QueueItemResponse{..}

instance ToJSON QueueItemResponse where
    toJSON QueueItemResponse{..} = object
        [ "id" .= qirId
        , "changeId" .= qirChangeId
        , "stackId" .= qirStackId
        , "dependencies" .= qirDependencies
        , "priority" .= qirPriority
        , "retries" .= qirRetries
        , "submitted" .= qirSubmitted
        , "started" .= qirStarted
        , "completed" .= qirCompleted
        , "status" .= qirStatus
        , "error" .= qirError
        , "validations" .= qirValidations
        , "duration" .= calculateDuration qirStarted qirCompleted
        ]
      where
        calculateDuration :: Maybe UTCTime -> Maybe UTCTime -> Maybe NominalDiffTime
        calculateDuration (Just start) (Just end) = Just $ diffUTCTime end start
        calculateDuration _ _ = Nothing
