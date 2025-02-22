-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.ReviewTemplate
    ( reviewTemplateRoutes
    ) where

import Web.Scotty.Trans

import Gerrit.Api.Error (ApiError)
import Gerrit.Api.Handlers.ReviewTemplate
import Gerrit.Services.ReviewTemplateService (ReviewTemplateService)

-- | Review template routes
reviewTemplateRoutes :: ReviewTemplateService -> ScottyT ApiError IO ()
reviewTemplateRoutes service = do
    -- Templates
    post "/api/templates" $
        handleCreateTemplate service

    get "/api/templates" $
        handleListTemplates service

    get "/api/templates/:template_id" $
        handleGetTemplate service

    put "/api/templates/:template_id" $
        handleUpdateTemplate service

    delete "/api/templates/:template_id" $
        handleDeleteTemplate service

    -- Template Rules
    post "/api/templates/:template_id/rules" $
        handleAddTemplateRule service

    get "/api/templates/:template_id/rules" $
        handleGetTemplateRules service

    put "/api/templates/rules/:rule_id" $
        handleUpdateTemplateRule service

    delete "/api/templates/rules/:rule_id" $
        handleRemoveTemplateRule service

    -- Apply Template
    post "/api/templates/:template_id/apply/:change_id" $
        handleApplyTemplate service
