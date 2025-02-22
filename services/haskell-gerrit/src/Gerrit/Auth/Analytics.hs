-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Auth.Analytics
    ( TokenAnalytics(..)
    , TokenUsageStats(..)
    , TokenHealthMetrics(..)
    , TokenUsagePatterns(..)
    , initTokenAnalytics
    , recordTokenUsage
    , getTokenUsageStats
    , getTokenHealthMetrics
    , getTokenUsagePatterns
    , generateTokenReport
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (ToJSON(..), FromJSON(..), object, (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime, addUTCTime)
import Database.PostgreSQL.Simple (Connection, Only(..), query, execute)

import Gerrit.Auth.Types

data TokenAnalytics = TokenAnalytics
    { analyticsConn :: Connection
    }

data TokenUsageStats = TokenUsageStats
    { totalActiveTokens :: Int
    , tokensByType :: Map Text Int
    , tokensByStatus :: Map Text Int
    , totalRequests :: Int
    , uniqueTokens :: Int
    , avgRequestsPerToken :: Double
    , scopeUsage :: Map Text Int
    , endpointUsage :: Map Text Int
    , timeSeriesData :: [(UTCTime, Int, Int, Double)]  -- time, requests, unique tokens, error rate
    }

data TokenHealthMetrics = TokenHealthMetrics
    { overallHealthScore :: Double
    , rotationCompliance :: Double
    , scopeUtilization :: Double
    , errorRate :: Double
    , securityScore :: Double
    , securityEvents :: [(UTCTime, Text, Text, Map Text Text)]  -- time, type, severity, details
    }

data TokenUsagePatterns = TokenUsagePatterns
    { peakUsageHours :: [(Int, Int)]  -- hour, request count
    , locationStats :: Map Text Int  -- IP address, request count
    , userAgentStats :: Map Text Int  -- User agent, request count
    , unusedScopes :: [(Text, UTCTime)]  -- scope, last used
    , overPrivilegedTokens :: [(Text, [Text])]  -- token ID, unused scopes
    }

initTokenAnalytics :: Connection -> TokenAnalytics
initTokenAnalytics conn = TokenAnalytics
    { analyticsConn = conn
    }

-- | Record token usage
recordTokenUsage :: MonadIO m => TokenAnalytics -> AuthToken -> Text -> Text -> Text -> m ()
recordTokenUsage analytics token endpoint ipAddress userAgent = liftIO $ do
    now <- getCurrentTime
    let sql = "INSERT INTO token_usage \
              \(token_value, endpoint, ip_address, user_agent, timestamp) \
              \VALUES (?, ?, ?, ?, ?)"
    void $ execute (analyticsConn analytics) sql
        ( tokenValue token
        , endpoint
        , ipAddress
        , userAgent
        , now
        )

-- | Get token usage statistics
getTokenUsageStats :: MonadIO m => TokenAnalytics -> UTCTime -> UTCTime -> m TokenUsageStats
getTokenUsageStats analytics startTime endTime = liftIO $ do
    -- Get active tokens count
    let activeTokensSql = "SELECT token_type, COUNT(*) \
                         \FROM auth_tokens \
                         \WHERE expires_at > NOW() \
                         \AND revoked_at IS NULL \
                         \GROUP BY token_type"
    activeTokensRows <- query (analyticsConn analytics) activeTokensSql ()
    let tokensByType = Map.fromList activeTokensRows

    -- Get token status distribution
    let statusSql = "SELECT status, COUNT(*) \
                   \FROM auth_tokens \
                   \WHERE created_at BETWEEN ? AND ? \
                   \GROUP BY status"
    statusRows <- query (analyticsConn analytics) statusSql (startTime, endTime)
    let tokensByStatus = Map.fromList statusRows

    -- Get usage metrics
    let usageSql = "SELECT COUNT(*) as total_requests, \
                   \COUNT(DISTINCT token_value) as unique_tokens \
                   \FROM token_usage \
                   \WHERE timestamp BETWEEN ? AND ?"
    [(totalReqs, uniqueTokens)] <- query (analyticsConn analytics) usageSql (startTime, endTime)
    let avgReqs = if uniqueTokens == 0 then 0 else fromIntegral totalReqs / fromIntegral uniqueTokens

    -- Get scope usage
    let scopeSql = "SELECT scope, COUNT(*) \
                   \FROM token_usage_scopes \
                   \WHERE timestamp BETWEEN ? AND ? \
                   \GROUP BY scope"
    scopeRows <- query (analyticsConn analytics) scopeSql (startTime, endTime)
    let scopeUsage = Map.fromList scopeRows

    -- Get endpoint usage
    let endpointSql = "SELECT endpoint, COUNT(*) \
                      \FROM token_usage \
                      \WHERE timestamp BETWEEN ? AND ? \
                      \GROUP BY endpoint"
    endpointRows <- query (analyticsConn analytics) endpointSql (startTime, endTime)
    let endpointUsage = Map.fromList endpointRows

    -- Get time series data
    let timeSeriesSql = "SELECT \
                        \date_trunc('hour', timestamp) as hour, \
                        \COUNT(*) as requests, \
                        \COUNT(DISTINCT token_value) as unique_tokens, \
                        \SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END)::float / COUNT(*)::float as error_rate \
                        \FROM token_usage \
                        \WHERE timestamp BETWEEN ? AND ? \
                        \GROUP BY hour \
                        \ORDER BY hour"
    timeSeriesRows <- query (analyticsConn analytics) timeSeriesSql (startTime, endTime)

    pure TokenUsageStats
        { totalActiveTokens = sum $ Map.elems tokensByType
        , tokensByType = tokensByType
        , tokensByStatus = tokensByStatus
        , totalRequests = totalReqs
        , uniqueTokens = uniqueTokens
        , avgRequestsPerToken = avgReqs
        , scopeUsage = scopeUsage
        , endpointUsage = endpointUsage
        , timeSeriesData = timeSeriesRows
        }

-- | Get token health metrics
getTokenHealthMetrics :: MonadIO m => TokenAnalytics -> AuthToken -> m TokenHealthMetrics
getTokenHealthMetrics analytics token = liftIO $ do
    now <- getCurrentTime

    -- Calculate rotation compliance
    let rotationSql = "SELECT created_at, rotated_at \
                     \FROM auth_tokens \
                     \WHERE token_value = ?"
    [(created, rotated)] <- query (analyticsConn analytics) rotationSql (Only $ tokenValue token)
    let rotationScore = calculateRotationScore created rotated now

    -- Calculate scope utilization
    let scopeSql = "SELECT scope, last_used \
                   \FROM token_scopes \
                   \WHERE token_value = ?"
    scopeRows <- query (analyticsConn analytics) scopeSql (Only $ tokenValue token)
    let scopeScore = calculateScopeScore scopeRows now

    -- Calculate error rate
    let errorSql = "SELECT COUNT(CASE WHEN status = 'error' THEN 1 END)::float / COUNT(*)::float \
                   \FROM token_usage \
                   \WHERE token_value = ? \
                   \AND timestamp > ?"
    let oneHourAgo = addUTCTime (-3600) now
    [Only errorRate] <- query (analyticsConn analytics) errorSql (tokenValue token, oneHourAgo)

    -- Get security events
    let eventsSql = "SELECT timestamp, event_type, severity, details \
                    \FROM security_events \
                    \WHERE token_value = ? \
                    \ORDER BY timestamp DESC \
                    \LIMIT 10"
    events <- query (analyticsConn analytics) eventsSql (Only $ tokenValue token)

    -- Calculate overall health score
    let overallScore = (rotationScore + scopeScore + (1 - errorRate) * 100 + securityScore) / 4
        securityScore = 100 * (1 - min 1 (fromIntegral (length events) / 10))

    pure TokenHealthMetrics
        { overallHealthScore = overallScore
        , rotationCompliance = rotationScore
        , scopeUtilization = scopeScore
        , errorRate = errorRate
        , securityScore = securityScore
        , securityEvents = events
        }

-- | Get token usage patterns
getTokenUsagePatterns :: MonadIO m => TokenAnalytics -> AuthToken -> m TokenUsagePatterns
getTokenUsagePatterns analytics token = liftIO $ do
    -- Get peak usage hours
    let hoursSql = "SELECT EXTRACT(HOUR FROM timestamp) as hour, COUNT(*) \
                   \FROM token_usage \
                   \WHERE token_value = ? \
                   \GROUP BY hour \
                   \ORDER BY count DESC"
    peakHours <- query (analyticsConn analytics) hoursSql (Only $ tokenValue token)

    -- Get location stats
    let locationSql = "SELECT ip_address, COUNT(*) \
                      \FROM token_usage \
                      \WHERE token_value = ? \
                      \GROUP BY ip_address"
    locationRows <- query (analyticsConn analytics) locationSql (Only $ tokenValue token)
    let locationStats = Map.fromList locationRows

    -- Get user agent stats
    let uaSql = "SELECT user_agent, COUNT(*) \
                \FROM token_usage \
                \WHERE token_value = ? \
                \GROUP BY user_agent"
    uaRows <- query (analyticsConn analytics) uaSql (Only $ tokenValue token)
    let userAgentStats = Map.fromList uaRows

    -- Get unused scopes
    let unusedScopesSql = "SELECT scope, MAX(timestamp) \
                          \FROM token_usage_scopes \
                          \WHERE token_value = ? \
                          \GROUP BY scope"
    unusedScopes <- query (analyticsConn analytics) unusedScopesSql (Only $ tokenValue token)

    -- Get over-privileged tokens
    let privilegeSql = "SELECT token_value, ARRAY_AGG(scope) \
                       \FROM token_scopes \
                       \WHERE token_value = ? \
                       \AND last_used < NOW() - INTERVAL '30 days' \
                       \GROUP BY token_value"
    overPrivileged <- query (analyticsConn analytics) privilegeSql (Only $ tokenValue token)

    pure TokenUsagePatterns
        { peakUsageHours = peakHours
        , locationStats = locationStats
        , userAgentStats = userAgentStats
        , unusedScopes = unusedScopes
        , overPrivilegedTokens = overPrivileged
        }

-- | Generate a comprehensive token report
generateTokenReport :: MonadIO m => TokenAnalytics -> AuthToken -> m (Map Text Value)
generateTokenReport analytics token = liftIO $ do
    now <- getCurrentTime
    let startTime = addUTCTime (-86400 * 30) now  -- Last 30 days

    usageStats <- getTokenUsageStats analytics startTime now
    healthMetrics <- getTokenHealthMetrics analytics token
    patterns <- getTokenUsagePatterns analytics token

    pure $ object
        [ "token_info" .= object
            [ "token_value" .= tokenValue token
            , "token_type" .= show (tokenType token)
            , "expires_at" .= tokenExpiry token
            , "scopes" .= tokenScopes token
            ]
        , "usage_stats" .= usageStats
        , "health_metrics" .= healthMetrics
        , "usage_patterns" .= patterns
        , "recommendations" .= generateRecommendations usageStats healthMetrics patterns
        ]

-- Helper functions

calculateRotationScore :: UTCTime -> Maybe UTCTime -> UTCTime -> Double
calculateRotationScore created rotated now =
    case rotated of
        Nothing -> let age = diffUTCTime now created
                  in max 0 (100 - age / 86400 * 2)  -- -2 points per day
        Just r -> let age = diffUTCTime now r
                 in max 0 (100 - age / 86400)  -- -1 point per day

calculateScopeScore :: [(Text, UTCTime)] -> UTCTime -> Double
calculateScopeScore scopes now =
    let totalScopes = length scopes
        unusedScopes = length $ filter (\(_, lastUsed) ->
            diffUTCTime now lastUsed > 30 * 86400) scopes  -- Unused for 30 days
    in if totalScopes == 0
        then 100
        else 100 * (1 - fromIntegral unusedScopes / fromIntegral totalScopes)

generateRecommendations :: TokenUsageStats -> TokenHealthMetrics -> TokenUsagePatterns -> [Value]
generateRecommendations stats health patterns =
    let recommendations = []
        -- Add rotation recommendation if compliance is low
        recommendations' = if rotationCompliance health < 80
            then object
                [ "type" .= ("rotation" :: Text)
                , "priority" .= ("high" :: Text)
                , "message" .= ("Token should be rotated soon" :: Text)
                ] : recommendations
            else recommendations

        -- Add scope recommendation if there are unused scopes
        recommendations'' = if not (null $ unusedScopes patterns)
            then object
                [ "type" .= ("scope" :: Text)
                , "priority" .= ("medium" :: Text)
                , "message" .= ("Consider removing unused scopes" :: Text)
                , "details" .= unusedScopes patterns
                ] : recommendations'
            else recommendations'

        -- Add security recommendation if error rate is high
        recommendations''' = if errorRate health > 0.05
            then object
                [ "type" .= ("security" :: Text)
                , "priority" .= ("high" :: Text)
                , "message" .= ("High error rate detected" :: Text)
                ] : recommendations''
            else recommendations''
    in recommendations'''
