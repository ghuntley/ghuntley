{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.AlertRules
    ( -- * Handlers
      handleListAlertRules
    , handleCreateAlertRule
    , handleGetAlertRule
    , handleUpdateAlertRule
    , handleDeleteAlertRule
    , handleEnableAlertRule
    , handleDisableAlertRule
      -- * Request Types
    , CreateAlertRuleRequest(..)
    , UpdateAlertRuleRequest(..)
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson
import Data.Text (Text)
import Data.Time (getCurrentTime)
import Servant

import Gerrit.Models.Alert
import Gerrit.Api.Types (Response(..), ErrorResponse(..))
import Gerrit.Api.Config (Config(..))
import Gerrit.Api.Metrics (Metrics(..), incrementErrors)

-- | Request to create a new alert rule
data CreateAlertRuleRequest = CreateAlertRuleRequest
    { createRuleName :: Text
    , createRuleDescription :: Text
    , createRuleThresholds :: Value
    , createRuleMetadata :: Maybe Value
    } deriving (Show, Eq)

instance FromJSON CreateAlertRuleRequest where
    parseJSON = withObject "CreateAlertRuleRequest" $ \v -> CreateAlertRuleRequest
        <$> v .: "name"
        <*> v .: "description"
        <*> v .: "thresholds"
        <*> v .:? "metadata"

-- | Request to update an alert rule
data UpdateAlertRuleRequest = UpdateAlertRuleRequest
    { updateRuleName :: Maybe Text
    , updateRuleDescription :: Maybe Text
    , updateRuleThresholds :: Maybe Value
    , updateRuleMetadata :: Maybe Value
    } deriving (Show, Eq)

instance FromJSON UpdateAlertRuleRequest where
    parseJSON = withObject "UpdateAlertRuleRequest" $ \v -> UpdateAlertRuleRequest
        <$> v .:? "name"
        <*> v .:? "description"
        <*> v .:? "thresholds"
        <*> v .:? "metadata"

-- | Handler to list alert rules
handleListAlertRules :: Maybe Text -> Handler (Response [AlertRule])
handleListAlertRules maybeName = do
    config <- asks getConfig
    rules <- liftIO $ case maybeName of
        Just name -> runDB (configDbPath config) $ getAlertRulesByName name
        Nothing -> runDB (configDbPath config) $ getEnabledAlertRules
    return $ Response
        { success = True
        , data_ = Just rules
        , audit = Nothing
        , error = Nothing
        }

-- | Handler to create a new alert rule
handleCreateAlertRule :: CreateAlertRuleRequest -> Handler (Response AlertRule)
handleCreateAlertRule CreateAlertRuleRequest{..} = do
    config <- asks getConfig
    rule <- liftIO $ createAlertRule
        (configDbPath config)
        createRuleName
        createRuleDescription
        createRuleThresholds
        createRuleMetadata
    return $ Response
        { success = True
        , data_ = Just rule
        , audit = Nothing
        , error = Nothing
        }

-- | Handler to get a specific alert rule
handleGetAlertRule :: Text -> Handler (Response AlertRule)
handleGetAlertRule ruleId' = do
    config <- asks getConfig
    maybeRule <- liftIO $ getAlertRuleById (configDbPath config) ruleId'
    case maybeRule of
        Just rule -> return $ Response
            { success = True
            , data_ = Just rule
            , audit = Nothing
            , error = Nothing
            }
        Nothing -> throwError err404
            { errBody = "Alert rule not found"
            }

-- | Handler to update an alert rule
handleUpdateAlertRule :: Text -> UpdateAlertRuleRequest -> Handler (Response AlertRule)
handleUpdateAlertRule ruleId' UpdateAlertRuleRequest{..} = do
    config <- asks getConfig
    maybeRule <- liftIO $ getAlertRuleById (configDbPath config) ruleId'
    case maybeRule of
        Just rule -> do
            now <- liftIO getCurrentTime
            let updatedRule = rule
                    { ruleName = maybe (ruleName rule) id updateRuleName
                    , ruleDescription = maybe (ruleDescription rule) id updateRuleDescription
                    , ruleThresholds = maybe (ruleThresholds rule) id updateRuleThresholds
                    , ruleMetadata = updateRuleMetadata <|> ruleMetadata rule
                    , ruleUpdated = now
                    }
            result <- liftIO $ updateAlertRule (configDbPath config) updatedRule
            return $ Response
                { success = True
                , data_ = Just result
                , audit = Nothing
                , error = Nothing
                }
        Nothing -> throwError err404
            { errBody = "Alert rule not found"
            }

-- | Handler to delete an alert rule
handleDeleteAlertRule :: Text -> Handler (Response ())
handleDeleteAlertRule ruleId' = do
    config <- asks getConfig
    liftIO $ runDB (configDbPath config) $ SQLiteM $ \conn ->
        execute conn "DELETE FROM alert_rules WHERE id = ?" (Only ruleId')
    return $ Response
        { success = True
        , data_ = Just ()
        , audit = Nothing
        , error = Nothing
        }

-- | Handler to enable an alert rule
handleEnableAlertRule :: Text -> Handler (Response AlertRule)
handleEnableAlertRule ruleId' = do
    config <- asks getConfig
    maybeRule <- liftIO $ getAlertRuleById (configDbPath config) ruleId'
    case maybeRule of
        Just rule -> do
            now <- liftIO getCurrentTime
            let updatedRule = rule
                    { ruleEnabled = True
                    , ruleUpdated = now
                    }
            result <- liftIO $ updateAlertRule (configDbPath config) updatedRule
            return $ Response
                { success = True
                , data_ = Just result
                , audit = Nothing
                , error = Nothing
                }
        Nothing -> throwError err404
            { errBody = "Alert rule not found"
            }

-- | Handler to disable an alert rule
handleDisableAlertRule :: Text -> Handler (Response AlertRule)
handleDisableAlertRule ruleId' = do
    config <- asks getConfig
    maybeRule <- liftIO $ getAlertRuleById (configDbPath config) ruleId'
    case maybeRule of
        Just rule -> do
            now <- liftIO getCurrentTime
            let updatedRule = rule
                    { ruleEnabled = False
                    , ruleUpdated = now
                    }
            result <- liftIO $ updateAlertRule (configDbPath config) updatedRule
            return $ Response
                { success = True
                , data_ = Just result
                , audit = Nothing
                , error = Nothing
                }
        Nothing -> throwError err404
            { errBody = "Alert rule not found"
            }
