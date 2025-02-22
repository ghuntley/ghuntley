-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.ReviewTemplateService
    ( -- * Types
      ReviewTemplateService(..)
    , ReviewTemplateError(..)
      -- * Service Operations
    , initReviewTemplateService
    , createReviewTemplate
    , updateReviewTemplate
    , deleteReviewTemplate
    , getReviewTemplate
    , listReviewTemplates
    , addTemplateRule
    , updateTemplateRule
    , removeTemplateRule
    , getTemplateRules
    , applyTemplateToReview
    ) where

import Control.Monad (void, when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (getCurrentTime)
import Database.Persist
import Database.Persist.Sql

import Gerrit.Database.Connection (runDB)
import Gerrit.Models.ReviewTemplate
import Gerrit.Models.Change (Change)
import Gerrit.Models.Vote (Vote)
import Gerrit.Services.NotificationService (NotificationService)
import qualified Gerrit.Services.NotificationService as Notification
import Gerrit.Services.MetricsService (MetricsService)
import qualified Gerrit.Services.MetricsService as Metrics

-- | Review template service errors
data ReviewTemplateError
    = TemplateNotFound Text
    | RuleNotFound Text
    | InvalidScope Text
    | InvalidType Text
    | InvalidStatus Text
    | DatabaseError Text
    | ValidationError Text
    deriving (Show, Eq)

-- | Review template service
data ReviewTemplateService = ReviewTemplateService
    { rtsConnectionPool :: ConnectionPool
    , rtsNotificationService :: NotificationService
    , rtsMetricsService :: MetricsService
    }

-- | Initialize the review template service
initReviewTemplateService :: ConnectionPool
                         -> NotificationService
                         -> MetricsService
                         -> ReviewTemplateService
initReviewTemplateService pool notificationSvc metricsSvc =
    ReviewTemplateService
        { rtsConnectionPool = pool
        , rtsNotificationService = notificationSvc
        , rtsMetricsService = metricsSvc
        }

-- | Create a new review template
createReviewTemplate :: MonadIO m
                    => ReviewTemplateService
                    -> Text  -- ^ Name
                    -> Maybe Text  -- ^ Description
                    -> TemplateScope  -- ^ Scope
                    -> TemplateType  -- ^ Template type
                    -> Text  -- ^ Owner ID
                    -> Bool  -- ^ Is default
                    -> Maybe Value  -- ^ Additional metadata
                    -> m (Either ReviewTemplateError (Entity ReviewTemplate))
createReviewTemplate ReviewTemplateService{..} name desc scope templateType ownerId isDefault metadata = do
    -- Validate scope
    case validateScope scope of
        Left err -> return $ Left err
        Right _ -> do
            -- Create template
            result <- runDB rtsConnectionPool $
                createTemplate name desc scope templateType ownerId isDefault metadata

            case result of
                Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
                Right template -> do
                    -- Record metrics
                    void $ Metrics.recordMetric rtsMetricsService "template_created"
                        [ ("scope", show scope)
                        , ("type", show templateType)
                        ]

                    -- Send notification
                    void $ Notification.sendNotification rtsNotificationService
                        "template_created"
                        (object
                            [ "template_id" .= reviewTemplateTemplateId (entityVal template)
                            , "name" .= name
                            , "owner_id" .= ownerId
                            ])

                    return $ Right template

-- | Update an existing review template
updateReviewTemplate :: MonadIO m
                    => ReviewTemplateService
                    -> Text  -- ^ Template ID
                    -> Text  -- ^ Name
                    -> Maybe Text  -- ^ Description
                    -> TemplateType  -- ^ Template type
                    -> Bool  -- ^ Is default
                    -> Bool  -- ^ Is enabled
                    -> Maybe Value  -- ^ Additional metadata
                    -> m (Either ReviewTemplateError (Entity ReviewTemplate))
updateReviewTemplate ReviewTemplateService{..} templateId name desc templateType isDefault isEnabled metadata = do
    -- Get existing template
    result <- runDB rtsConnectionPool $ getTemplateById templateId
    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right Nothing -> return $ Left $ TemplateNotFound templateId
        Right (Just template) -> do
            -- Update template
            result' <- runDB rtsConnectionPool $
                updateTemplate template name desc templateType isDefault isEnabled metadata

            case result' of
                Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
                Right updatedTemplate -> do
                    -- Record metrics
                    void $ Metrics.recordMetric rtsMetricsService "template_updated"
                        [ ("template_id", Text.unpack templateId)
                        ]

                    -- Send notification
                    void $ Notification.sendNotification rtsNotificationService
                        "template_updated"
                        (object
                            [ "template_id" .= templateId
                            , "name" .= name
                            ])

                    return $ Right updatedTemplate

-- | Delete a review template
deleteReviewTemplate :: MonadIO m
                    => ReviewTemplateService
                    -> Text  -- ^ Template ID
                    -> m (Either ReviewTemplateError ())
deleteReviewTemplate ReviewTemplateService{..} templateId = do
    -- Get existing template
    result <- runDB rtsConnectionPool $ getTemplateById templateId
    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right Nothing -> return $ Left $ TemplateNotFound templateId
        Right (Just template) -> do
            -- Delete template
            result' <- runDB rtsConnectionPool $ deleteTemplate template
            case result' of
                Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
                Right _ -> do
                    -- Record metrics
                    void $ Metrics.recordMetric rtsMetricsService "template_deleted"
                        [ ("template_id", Text.unpack templateId)
                        ]

                    -- Send notification
                    void $ Notification.sendNotification rtsNotificationService
                        "template_deleted"
                        (object ["template_id" .= templateId])

                    return $ Right ()

-- | Get a review template by ID
getReviewTemplate :: MonadIO m
                  => ReviewTemplateService
                  -> Text  -- ^ Template ID
                  -> m (Either ReviewTemplateError (Entity ReviewTemplate))
getReviewTemplate ReviewTemplateService{..} templateId = do
    result <- runDB rtsConnectionPool $ getTemplateById templateId
    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right Nothing -> return $ Left $ TemplateNotFound templateId
        Right (Just template) -> return $ Right template

-- | List review templates with filtering
listReviewTemplates :: MonadIO m
                    => ReviewTemplateService
                    -> Maybe TemplateScope  -- ^ Filter by scope
                    -> Maybe TemplateType   -- ^ Filter by type
                    -> Bool                 -- ^ Only enabled templates
                    -> Int                  -- ^ Offset
                    -> Int                  -- ^ Limit
                    -> m (Either ReviewTemplateError [Entity ReviewTemplate])
listReviewTemplates ReviewTemplateService{..} mScope mType onlyEnabled offset limit = do
    result <- runDB rtsConnectionPool $
        listTemplates mScope mType onlyEnabled offset limit
    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right templates -> return $ Right templates

-- | Add a rule to a template
addTemplateRule :: MonadIO m
                => ReviewTemplateService
                -> Text  -- ^ Template ID
                -> Text  -- ^ Rule name
                -> Text  -- ^ Rule description
                -> RuleType  -- ^ Rule type
                -> RuleSeverity  -- ^ Rule severity
                -> Bool  -- ^ Is required
                -> Maybe Value  -- ^ Additional metadata
                -> m (Either ReviewTemplateError (Entity TemplateRule))
addTemplateRule ReviewTemplateService{..} templateId name desc ruleType severity isRequired metadata = do
    -- Verify template exists
    result <- runDB rtsConnectionPool $ getTemplateById templateId
    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right Nothing -> return $ Left $ TemplateNotFound templateId
        Right (Just _) -> do
            -- Add rule
            result' <- runDB rtsConnectionPool $
                Gerrit.Models.ReviewTemplate.addTemplateRule
                    templateId name desc ruleType severity isRequired metadata

            case result' of
                Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
                Right rule -> do
                    -- Record metrics
                    void $ Metrics.recordMetric rtsMetricsService "template_rule_added"
                        [ ("template_id", Text.unpack templateId)
                        , ("rule_type", show ruleType)
                        ]

                    -- Send notification
                    void $ Notification.sendNotification rtsNotificationService
                        "template_rule_added"
                        (object
                            [ "template_id" .= templateId
                            , "rule_id" .= templateRuleRuleId (entityVal rule)
                            ])

                    return $ Right rule

-- | Update a template rule
updateTemplateRule :: MonadIO m
                   => ReviewTemplateService
                   -> Text  -- ^ Rule ID
                   -> Text  -- ^ Rule name
                   -> Text  -- ^ Rule description
                   -> RuleType  -- ^ Rule type
                   -> RuleSeverity  -- ^ Rule severity
                   -> Bool  -- ^ Is required
                   -> Bool  -- ^ Is enabled
                   -> Maybe Value  -- ^ Additional metadata
                   -> m (Either ReviewTemplateError (Entity TemplateRule))
updateTemplateRule ReviewTemplateService{..} ruleId name desc ruleType severity isRequired isEnabled metadata = do
    -- Get existing rule
    result <- runDB rtsConnectionPool $ getBy $ UniqueRuleId ruleId
    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right Nothing -> return $ Left $ RuleNotFound ruleId
        Right (Just rule) -> do
            -- Update rule
            result' <- runDB rtsConnectionPool $
                Gerrit.Models.ReviewTemplate.updateTemplateRule
                    rule name desc ruleType severity isRequired isEnabled metadata

            case result' of
                Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
                Right updatedRule -> do
                    -- Record metrics
                    void $ Metrics.recordMetric rtsMetricsService "template_rule_updated"
                        [ ("rule_id", Text.unpack ruleId)
                        ]

                    -- Send notification
                    void $ Notification.sendNotification rtsNotificationService
                        "template_rule_updated"
                        (object ["rule_id" .= ruleId])

                    return $ Right updatedRule

-- | Remove a rule from a template
removeTemplateRule :: MonadIO m
                   => ReviewTemplateService
                   -> Text  -- ^ Rule ID
                   -> m (Either ReviewTemplateError ())
removeTemplateRule ReviewTemplateService{..} ruleId = do
    -- Get existing rule
    result <- runDB rtsConnectionPool $ getBy $ UniqueRuleId ruleId
    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right Nothing -> return $ Left $ RuleNotFound ruleId
        Right (Just rule) -> do
            -- Remove rule
            result' <- runDB rtsConnectionPool $ removeTemplateRule rule
            case result' of
                Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
                Right _ -> do
                    -- Record metrics
                    void $ Metrics.recordMetric rtsMetricsService "template_rule_removed"
                        [ ("rule_id", Text.unpack ruleId)
                        ]

                    -- Send notification
                    void $ Notification.sendNotification rtsNotificationService
                        "template_rule_removed"
                        (object ["rule_id" .= ruleId])

                    return $ Right ()

-- | Get rules for a template
getTemplateRules :: MonadIO m
                 => ReviewTemplateService
                 -> Text  -- ^ Template ID
                 -> m (Either ReviewTemplateError [Entity TemplateRule])
getTemplateRules ReviewTemplateService{..} templateId = do
    -- Verify template exists
    result <- runDB rtsConnectionPool $ getTemplateById templateId
    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right Nothing -> return $ Left $ TemplateNotFound templateId
        Right (Just _) -> do
            -- Get rules
            result' <- runDB rtsConnectionPool $ getTemplateRules templateId
            case result' of
                Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
                Right rules -> return $ Right rules

-- | Apply a template to a review
applyTemplateToReview :: MonadIO m
                      => ReviewTemplateService
                      -> Text  -- ^ Template ID
                      -> Text  -- ^ Change ID
                      -> m (Either ReviewTemplateError ())
applyTemplateToReview ReviewTemplateService{..} templateId changeId = do
    -- Get template and rules
    result <- runDB rtsConnectionPool $ do
        mTemplate <- getTemplateById templateId
        case mTemplate of
            Nothing -> return $ Left $ TemplateNotFound templateId
            Just template -> do
                rules <- getTemplateRules templateId
                return $ Right (template, rules)

    case result of
        Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
        Right (template, rules) -> do
            -- Apply rules
            result' <- runDB rtsConnectionPool $ applyRulesToChange changeId rules
            case result' of
                Left err -> return $ Left $ DatabaseError $ Text.pack $ show err
                Right _ -> do
                    -- Record metrics
                    void $ Metrics.recordMetric rtsMetricsService "template_applied"
                        [ ("template_id", Text.unpack templateId)
                        , ("change_id", Text.unpack changeId)
                        ]

                    -- Send notification
                    void $ Notification.sendNotification rtsNotificationService
                        "template_applied"
                        (object
                            [ "template_id" .= templateId
                            , "change_id" .= changeId
                            ])

                    return $ Right ()

-- Helper functions

validateScope :: TemplateScope -> Either ReviewTemplateError ()
validateScope scope = case scope of
    GlobalScope -> Right ()
    OrganizationScope orgId
        | Text.null orgId -> Left $ InvalidScope "Organization ID cannot be empty"
        | otherwise -> Right ()
    ProjectScope projId
        | Text.null projId -> Left $ InvalidScope "Project ID cannot be empty"
        | otherwise -> Right ()
    TeamScope teamId
        | Text.null teamId -> Left $ InvalidScope "Team ID cannot be empty"
        | otherwise -> Right ()

applyRulesToChange :: MonadIO m
                   => Text  -- ^ Change ID
                   -> [Entity TemplateRule]  -- ^ Rules to apply
                   -> SqlPersistT m ()
applyRulesToChange changeId rules = do
    -- Implementation would:
    -- 1. Create required votes based on rules
    -- 2. Add automated checks
    -- 3. Update change metadata
    -- For now, just a placeholder
    return ()
