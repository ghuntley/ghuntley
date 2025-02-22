-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.ReviewTemplate
    ( -- * Request Types
      CreateTemplateRequest(..)
    , UpdateTemplateRequest(..)
    , AddRuleRequest(..)
    , UpdateRuleRequest(..)
      -- * Handlers
    , handleCreateTemplate
    , handleUpdateTemplate
    , handleDeleteTemplate
    , handleGetTemplate
    , handleListTemplates
    , handleAddTemplateRule
    , handleUpdateTemplateRule
    , handleRemoveTemplateRule
    , handleGetTemplateRules
    , handleApplyTemplate
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as Text
import Network.HTTP.Types.Status
import Web.Scotty.Trans

import Gerrit.Api.Types
import Gerrit.Models.ReviewTemplate
import Gerrit.Services.ReviewTemplateService (ReviewTemplateService)
import qualified Gerrit.Services.ReviewTemplateService as ReviewTemplate
import Gerrit.Api.Auth (requireAuth, AuthUser(..))
import Gerrit.Api.Error (ApiError(..), throwApiError)

-- | Request to create a new template
data CreateTemplateRequest = CreateTemplateRequest
    { ctrName :: Text
    , ctrDescription :: Maybe Text
    , ctrScope :: TemplateScope
    , ctrType :: TemplateType
    , ctrIsDefault :: Bool
    , ctrMetadata :: Maybe Value
    } deriving (Show, Eq)

instance FromJSON CreateTemplateRequest where
    parseJSON = withObject "CreateTemplateRequest" $ \v -> CreateTemplateRequest
        <$> v .: "name"
        <*> v .:? "description"
        <*> v .: "scope"
        <*> v .: "type"
        <*> v .:? "is_default" .!= False
        <*> v .:? "metadata"

-- | Request to update a template
data UpdateTemplateRequest = UpdateTemplateRequest
    { utrName :: Text
    , utrDescription :: Maybe Text
    , utrType :: TemplateType
    , utrIsDefault :: Bool
    , utrIsEnabled :: Bool
    , utrMetadata :: Maybe Value
    } deriving (Show, Eq)

instance FromJSON UpdateTemplateRequest where
    parseJSON = withObject "UpdateTemplateRequest" $ \v -> UpdateTemplateRequest
        <$> v .: "name"
        <*> v .:? "description"
        <*> v .: "type"
        <*> v .:? "is_default" .!= False
        <*> v .:? "is_enabled" .!= True
        <*> v .:? "metadata"

-- | Request to add a rule to a template
data AddRuleRequest = AddRuleRequest
    { arrName :: Text
    , arrDescription :: Text
    , arrType :: RuleType
    , arrSeverity :: RuleSeverity
    , arrIsRequired :: Bool
    , arrMetadata :: Maybe Value
    } deriving (Show, Eq)

instance FromJSON AddRuleRequest where
    parseJSON = withObject "AddRuleRequest" $ \v -> AddRuleRequest
        <$> v .: "name"
        <*> v .: "description"
        <*> v .: "type"
        <*> v .: "severity"
        <*> v .:? "is_required" .!= False
        <*> v .:? "metadata"

-- | Request to update a rule
data UpdateRuleRequest = UpdateRuleRequest
    { urrName :: Text
    , urrDescription :: Text
    , urrType :: RuleType
    , urrSeverity :: RuleSeverity
    , urrIsRequired :: Bool
    , urrIsEnabled :: Bool
    , urrMetadata :: Maybe Value
    } deriving (Show, Eq)

instance FromJSON UpdateRuleRequest where
    parseJSON = withObject "UpdateRuleRequest" $ \v -> UpdateRuleRequest
        <$> v .: "name"
        <*> v .: "description"
        <*> v .: "type"
        <*> v .: "severity"
        <*> v .:? "is_required" .!= False
        <*> v .:? "is_enabled" .!= True
        <*> v .:? "metadata"

-- | Handle creating a new template
handleCreateTemplate :: ReviewTemplateService -> ActionT ApiError IO ()
handleCreateTemplate service = do
    user <- requireAuth
    req <- jsonData
    result <- liftIO $ ReviewTemplate.createReviewTemplate service
        (ctrName req)
        (ctrDescription req)
        (ctrScope req)
        (ctrType req)
        (authUserId user)
        (ctrIsDefault req)
        (ctrMetadata req)
    case result of
        Left err -> handleTemplateError err
        Right template -> json template

-- | Handle updating a template
handleUpdateTemplate :: ReviewTemplateService -> ActionT ApiError IO ()
handleUpdateTemplate service = do
    _ <- requireAuth
    templateId <- param "template_id"
    req <- jsonData
    result <- liftIO $ ReviewTemplate.updateReviewTemplate service
        templateId
        (utrName req)
        (utrDescription req)
        (utrType req)
        (utrIsDefault req)
        (utrIsEnabled req)
        (utrMetadata req)
    case result of
        Left err -> handleTemplateError err
        Right template -> json template

-- | Handle deleting a template
handleDeleteTemplate :: ReviewTemplateService -> ActionT ApiError IO ()
handleDeleteTemplate service = do
    _ <- requireAuth
    templateId <- param "template_id"
    result <- liftIO $ ReviewTemplate.deleteReviewTemplate service templateId
    case result of
        Left err -> handleTemplateError err
        Right _ -> status noContent204

-- | Handle getting a template by ID
handleGetTemplate :: ReviewTemplateService -> ActionT ApiError IO ()
handleGetTemplate service = do
    _ <- requireAuth
    templateId <- param "template_id"
    result <- liftIO $ ReviewTemplate.getReviewTemplate service templateId
    case result of
        Left err -> handleTemplateError err
        Right template -> json template

-- | Handle listing templates
handleListTemplates :: ReviewTemplateService -> ActionT ApiError IO ()
handleListTemplates service = do
    _ <- requireAuth
    mScope <- paramMaybe "scope"
    mType <- paramMaybe "type"
    onlyEnabled <- param "only_enabled" `rescue` const (return False)
    offset <- param "offset" `rescue` const (return 0)
    limit <- param "limit" `rescue` const (return 50)
    result <- liftIO $ ReviewTemplate.listReviewTemplates service
        mScope mType onlyEnabled offset limit
    case result of
        Left err -> handleTemplateError err
        Right templates -> json templates

-- | Handle adding a rule to a template
handleAddTemplateRule :: ReviewTemplateService -> ActionT ApiError IO ()
handleAddTemplateRule service = do
    _ <- requireAuth
    templateId <- param "template_id"
    req <- jsonData
    result <- liftIO $ ReviewTemplate.addTemplateRule service
        templateId
        (arrName req)
        (arrDescription req)
        (arrType req)
        (arrSeverity req)
        (arrIsRequired req)
        (arrMetadata req)
    case result of
        Left err -> handleTemplateError err
        Right rule -> json rule

-- | Handle updating a template rule
handleUpdateTemplateRule :: ReviewTemplateService -> ActionT ApiError IO ()
handleUpdateTemplateRule service = do
    _ <- requireAuth
    ruleId <- param "rule_id"
    req <- jsonData
    result <- liftIO $ ReviewTemplate.updateTemplateRule service
        ruleId
        (urrName req)
        (urrDescription req)
        (urrType req)
        (urrSeverity req)
        (urrIsRequired req)
        (urrIsEnabled req)
        (urrMetadata req)
    case result of
        Left err -> handleTemplateError err
        Right rule -> json rule

-- | Handle removing a rule from a template
handleRemoveTemplateRule :: ReviewTemplateService -> ActionT ApiError IO ()
handleRemoveTemplateRule service = do
    _ <- requireAuth
    ruleId <- param "rule_id"
    result <- liftIO $ ReviewTemplate.removeTemplateRule service ruleId
    case result of
        Left err -> handleTemplateError err
        Right _ -> status noContent204

-- | Handle getting rules for a template
handleGetTemplateRules :: ReviewTemplateService -> ActionT ApiError IO ()
handleGetTemplateRules service = do
    _ <- requireAuth
    templateId <- param "template_id"
    result <- liftIO $ ReviewTemplate.getTemplateRules service templateId
    case result of
        Left err -> handleTemplateError err
        Right rules -> json rules

-- | Handle applying a template to a review
handleApplyTemplate :: ReviewTemplateService -> ActionT ApiError IO ()
handleApplyTemplate service = do
    _ <- requireAuth
    templateId <- param "template_id"
    changeId <- param "change_id"
    result <- liftIO $ ReviewTemplate.applyTemplateToReview service templateId changeId
    case result of
        Left err -> handleTemplateError err
        Right _ -> status ok200

-- Helper functions

handleTemplateError :: ReviewTemplate.ReviewTemplateError -> ActionT ApiError IO a
handleTemplateError err = case err of
    ReviewTemplate.TemplateNotFound tid ->
        throwApiError $ NotFoundError $ "Template not found: " <> tid
    ReviewTemplate.RuleNotFound rid ->
        throwApiError $ NotFoundError $ "Rule not found: " <> rid
    ReviewTemplate.InvalidScope msg ->
        throwApiError $ ValidationError $ "Invalid scope: " <> msg
    ReviewTemplate.InvalidType msg ->
        throwApiError $ ValidationError $ "Invalid type: " <> msg
    ReviewTemplate.InvalidStatus msg ->
        throwApiError $ ValidationError $ "Invalid status: " <> msg
    ReviewTemplate.DatabaseError msg ->
        throwApiError $ InternalError $ "Database error: " <> msg
    ReviewTemplate.ValidationError msg ->
        throwApiError $ ValidationError msg
