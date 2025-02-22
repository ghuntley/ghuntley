{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.MergeQueue
    ( mergeQueueRoutes
    ) where

import Web.Scotty.Trans

import Gerrit.Api.Handlers.MergeQueue
import Gerrit.Services.MergeQueueService (MergeQueueService)

-- | Routes for merge queue operations
mergeQueueRoutes :: MonadIO m => MergeQueueService -> ScottyT m ()
mergeQueueRoutes service = do
    -- Queue operations
    post "/api/v1/merge-queues" $
        handleCreateQueue service

    get "/api/v1/merge-queues" $
        handleListQueues service

    get "/api/v1/merge-queues/:queue_id" $
        handleGetQueue service

    -- Entry operations
    post "/api/v1/merge-queues/:queue_id/entries" $
        handleEnqueueChange service

    get "/api/v1/merge-queues/:queue_id/entries" $
        handleListQueueEntries service

    get "/api/v1/merge-queues/entries/:entry_id" $
        handleGetQueueEntry service

    delete "/api/v1/merge-queues/entries/:entry_id" $
        handleDequeueChange service

    put "/api/v1/merge-queues/entries/:entry_id/status" $
        handleUpdateEntryStatus service

    -- Queue processing
    post "/api/v1/merge-queues/:queue_id/process" $
        handleProcessQueue service
