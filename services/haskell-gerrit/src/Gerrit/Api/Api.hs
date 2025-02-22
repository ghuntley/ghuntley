{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Api
    ( -- * API
      GerritAPI
    , gerritServer
    , gerritSwagger
      -- * Application
    , app
    , mkApp
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.RequestLogger (logStdout)
import Servant
import Servant.Swagger
import System.Remote.Monitoring.Prometheus (Server, serverMetricStore, exportMetricsAsText)
import qualified System.Remote.Monitoring.Prometheus as Prometheus

import Gerrit.Api.Types
import Gerrit.Api.Handlers
import Gerrit.Api.Middleware
import Gerrit.Api.Config (Config(..), loadConfig)
import Gerrit.Api.RateLimit (RateLimitConfig(..))
import Gerrit.Api.Metrics (Metrics(..), initMetrics, withMetrics)
import Gerrit.Models.Change (ChangeStatus)
import Gerrit.Models.Comment (CommentType)
import Gerrit.Models.Vote (VoteLabel, VoteValue)

-- | Main API type
type GerritAPI =
    -- Metrics endpoint
    "metrics" :> Get '[PlainText] Text
    :<|>
    -- Alerts
    "api" :> "v1" :> "alerts" :> (
        -- List active alerts
        QueryParam "severity" AlertSeverity :>
        QueryParam "source" Text :>
        Get '[JSON] (Response [Alert])

        -- Create a new alert
        :<|> ReqBody '[JSON] CreateAlertRequest :>
        Post '[JSON] (Response Alert)

        -- Get a specific alert
        :<|> Capture "alertId" Text :>
        Get '[JSON] (Response Alert)

        -- Acknowledge an alert
        :<|> Capture "alertId" Text :>
        "acknowledge" :>
        ReqBody '[JSON] AcknowledgeAlertRequest :>
        Post '[JSON] (Response Alert)

        -- Update alert status
        :<|> Capture "alertId" Text :>
        "status" :>
        ReqBody '[JSON] AlertStatus :>
        Put '[JSON] (Response Alert)

        -- Delete an alert
        :<|> Capture "alertId" Text :>
        Delete '[JSON] (Response ())
    )
    :<|>
    -- Alert Rules
    "api" :> "v1" :> "alert-rules" :> (
        -- List alert rules
        QueryParam "name" Text :>
        Get '[JSON] (Response [AlertRule])

        -- Create a new alert rule
        :<|> ReqBody '[JSON] CreateAlertRuleRequest :>
        Post '[JSON] (Response AlertRule)

        -- Get a specific alert rule
        :<|> Capture "ruleId" Text :>
        Get '[JSON] (Response AlertRule)

        -- Update alert rule
        :<|> Capture "ruleId" Text :>
        ReqBody '[JSON] UpdateAlertRuleRequest :>
        Put '[JSON] (Response AlertRule)

        -- Delete alert rule
        :<|> Capture "ruleId" Text :>
        Delete '[JSON] (Response ())

        -- Enable alert rule
        :<|> Capture "ruleId" Text :>
        "enable" :>
        Post '[JSON] (Response AlertRule)

        -- Disable alert rule
        :<|> Capture "ruleId" Text :>
        "disable" :>
        Post '[JSON] (Response AlertRule)
    )
    :<|>
    -- Changes
    "api" :> "v1" :> "changes" :> (
        -- List changes with pagination
        QueryParam "offset" Int :> QueryParam "limit" Int :>
        Get '[JSON] (Response [ChangeResponse])

        -- Create a new change
        :<|> ReqBody '[JSON] CreateChangeRequest :>
        Post '[JSON] (Response ChangeResponse)

        -- Get a specific change
        :<|> Capture "changeId" Text :>
        Get '[JSON] (Response ChangeResponse)

        -- Update change status
        :<|> Capture "changeId" Text :>
        "status" :>
        ReqBody '[JSON] ChangeStatus :>
        Put '[JSON] (Response ChangeResponse)
    )

    -- Revisions
    :<|> "api" :> "v1" :> "changes" :> Capture "changeId" Text :> "revisions" :> (
        -- List revisions for a change
        Get '[JSON] (Response [RevisionResponse])

        -- Create a new revision
        :<|> ReqBody '[JSON] CreateRevisionRequest :>
        Post '[JSON] (Response RevisionResponse)

        -- Get a specific revision
        :<|> Capture "revisionId" Text :>
        Get '[JSON] (Response RevisionResponse)
    )

    -- Comments
    :<|> "api" :> "v1" :> "changes" :> Capture "changeId" Text :> "revisions" :> Capture "revisionId" Text :> "comments" :> (
        -- List comments for a revision
        Get '[JSON] (Response [CommentResponse])

        -- Create a new comment
        :<|> ReqBody '[JSON] CreateCommentRequest :>
        Post '[JSON] (Response CommentResponse)

        -- Get a specific comment
        :<|> Capture "commentId" Text :>
        Get '[JSON] (Response CommentResponse)

        -- Update comment resolved status
        :<|> Capture "commentId" Text :>
        "resolved" :>
        ReqBody '[JSON] Bool :>
        Put '[JSON] (Response CommentResponse)

        -- Get file comments
        :<|> "files" :> Capture "file" Text :>
        Get '[JSON] (Response [CommentResponse])
    )

    -- Votes
    :<|> "api" :> "v1" :> "changes" :> Capture "changeId" Text :> "revisions" :> Capture "revisionId" Text :> "votes" :> (
        -- List votes for a revision
        Get '[JSON] (Response [VoteResponse])

        -- Create/Update a vote
        :<|> ReqBody '[JSON] CreateVoteRequest :>
        Post '[JSON] (Response VoteResponse)

        -- Get votes by reviewer
        :<|> "reviewers" :> Capture "reviewerId" Text :>
        Get '[JSON] (Response [VoteResponse])

        -- Get votes by label
        :<|> "labels" :> Capture "label" VoteLabel :>
        Get '[JSON] (Response [VoteResponse])

        -- Check if revision can be submitted
        :<|> "submit-check" :>
        Get '[JSON] (Response Bool)
    )

-- | API server
gerritServer :: Metrics -> ServerT GerritAPI Handler
gerritServer metrics =
    -- Metrics endpoint
    (liftIO $ exportMetricsAsText $ serverMetricStore metricsServer)
    :<|>
    -- Alerts
    handleListAlerts
    :<|> handleCreateAlert
    :<|> handleGetAlert
    :<|> handleAcknowledgeAlert
    :<|> handleUpdateAlertStatus
    :<|> handleDeleteAlert
    :<|>
    -- Alert Rules
    handleListAlertRules
    :<|> handleCreateAlertRule
    :<|> handleGetAlertRule
    :<|> handleUpdateAlertRule
    :<|> handleDeleteAlertRule
    :<|> handleEnableAlertRule
    :<|> handleDisableAlertRule
    :<|>
    -- Changes
    handleListChanges
    :<|> handleCreateChange
    :<|> handleGetChange
    :<|> handleUpdateChangeStatus

    -- Revisions
    :<|> handleListRevisions
    :<|> handleCreateRevision
    :<|> handleGetRevision

    -- Comments
    :<|> handleListComments
    :<|> handleCreateComment
    :<|> handleGetComment
    :<|> handleUpdateCommentResolved
    :<|> handleGetFileComments

    -- Votes
    :<|> handleListVotes
    :<|> handleCreateVote
    :<|> handleGetReviewerVotes
    :<|> handleGetLabelVotes
    :<|> handleCheckSubmit

-- | API documentation
gerritSwagger :: Swagger
gerritSwagger = toSwagger (Proxy :: Proxy GerritAPI)
    & info.title .~ "Gerrit Code Review API"
    & info.version .~ "1.0"
    & info.description ?~ "API for the Gerrit Code Review System"
    & info.license ?~ ("Proprietary" & url ?~ "https://ghuntley.com")

-- | Default rate limit configuration
defaultRateLimitConfig :: RateLimitConfig
defaultRateLimitConfig = RateLimitConfig
    { maxRequests = 100  -- 100 requests
    , timeWindow = 60    -- per minute
    , useIpLimit = True
    , useTokenLimit = True
    }

-- | Create the WAI application
mkApp :: IO Application
mkApp = do
    -- Load configuration
    config <- loadConfig

    -- Initialize metrics
    (store, metrics) <- initMetrics

    -- Start Prometheus metrics server
    metricsServer <- Prometheus.new defaultPrometheusConfig
    Prometheus.registerMetricStore store metricsServer

    -- Create rate limiter
    rateLimiter <- withRateLimit defaultRateLimitConfig

    -- Create application
    let api = Proxy :: Proxy GerritAPI
        server = hoistServer api (liftIO . runHandler) (gerritServer metrics)
        context = EmptyContext
        app' = serveWithContext api context server

    -- Return application with middleware stack
    return $ logStdout                    -- Development logging
           $ withLogging                  -- Production logging
           $ withMetrics metrics          -- Metrics collection
           $ withErrorHandling            -- Error handling
           $ rateLimiter                  -- Rate limiting
           $ withValidation config        -- Request validation
           $ authMiddleware               -- Authentication
           $ app'

-- | Run the application
app :: Int -> IO ()
app port = do
    putStrLn $ "Starting Gerrit API server on port " ++ show port
    application <- mkApp
    run port application

-- | Default Prometheus configuration
defaultPrometheusConfig :: Prometheus.Config
defaultPrometheusConfig = Prometheus.Config
    { Prometheus.configHost = "127.0.0.1"
    , Prometheus.configPort = 9091  -- Default Prometheus port
    }
