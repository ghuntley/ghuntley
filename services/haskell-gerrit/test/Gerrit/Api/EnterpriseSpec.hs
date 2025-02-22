{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Gerrit.Api.EnterpriseSpec (spec) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Types
import Network.Wai.Test (SResponse)
import Test.Hspec
import Test.Hspec.Wai
import Test.Hspec.Wai.JSON

import Gerrit.Api.TestUtils
import Gerrit.Models.Enterprise
import Gerrit.Services.EnterpriseService
import qualified Gerrit.Database.Connection as DB

spec :: Spec
spec = withApp $ do
    describe "Enterprise API" $ do
        describe "POST /api/v1/enterprises" $ do
            it "creates a new enterprise" $ do
                let payload = object
                        [ "name" .= ("Test Enterprise" :: Text)
                        , "domain" .= ("test.enterprise.com" :: Text)
                        , "plan" .= ("pro" :: Text)
                        , "max_users" .= (100 :: Int)
                        , "max_projects" .= (50 :: Int)
                        , "max_storage" .= (1000 :: Int)
                        , "settings" .= object []
                        ]

                postJSON "/api/v1/enterprises" payload
                    `shouldRespondWith` 201
                    { matchHeaders = ["Content-Type" <:> "application/json"]
                    , matchBody = bodyContains ["enterprise_id", "name", "domain"]
                    }

            it "validates required fields" $ do
                let payload = object
                        [ "name" .= ("Test Enterprise" :: Text)
                        -- Missing required domain
                        ]

                postJSON "/api/v1/enterprises" payload
                    `shouldRespondWith` 400
                    { matchBody = bodyContains ["domain is required"]
                    }

            it "prevents duplicate domains" $ do
                let payload = object
                        [ "name" .= ("Test Enterprise" :: Text)
                        , "domain" .= ("existing.domain.com" :: Text)
                        , "plan" .= ("pro" :: Text)
                        , "settings" .= object []
                        ]

                -- Create first enterprise
                postJSON "/api/v1/enterprises" payload

                -- Try to create another with same domain
                postJSON "/api/v1/enterprises" payload
                    `shouldRespondWith` 409
                    { matchBody = bodyContains ["domain already exists"]
                    }

        describe "GET /api/v1/enterprises/:enterprise_id" $ do
            it "gets enterprise details" $ do
                -- First create an enterprise
                enterpriseId <- createTestEnterprise

                get ("/api/v1/enterprises/" <> enterpriseId)
                    `shouldRespondWith` 200
                    { matchHeaders = ["Content-Type" <:> "application/json"]
                    , matchBody = bodyContains ["enterprise_id", "name", "domain"]
                    }

            it "returns 404 for non-existent enterprise" $ do
                get "/api/v1/enterprises/non-existent"
                    `shouldRespondWith` 404

        describe "PUT /api/v1/enterprises/:enterprise_id" $ do
            it "updates enterprise details" $ do
                enterpriseId <- createTestEnterprise

                let payload = object
                        [ "name" .= ("Updated Enterprise" :: Text)
                        , "domain" .= ("updated.domain.com" :: Text)
                        , "status" .= ("active" :: Text)
                        , "settings" .= object []
                        ]

                putJSON ("/api/v1/enterprises/" <> enterpriseId) payload
                    `shouldRespondWith` 200
                    { matchBody = bodyContains ["Updated Enterprise", "updated.domain.com"]
                    }

        describe "GET /api/v1/enterprises" $ do
            it "lists enterprises with pagination" $ do
                -- Create multiple test enterprises
                mapM_ (const createTestEnterprise) [1..3]

                get "/api/v1/enterprises?offset=0&limit=2"
                    `shouldRespondWith` 200
                    { matchBody = bodyContainsArray 2
                    }

            it "filters enterprises by plan" $ do
                get "/api/v1/enterprises?plan=pro"
                    `shouldRespondWith` 200

            it "filters enterprises by status" $ do
                get "/api/v1/enterprises?status=active"
                    `shouldRespondWith` 200

        describe "PUT /api/v1/enterprises/:enterprise_id/plan" $ do
            it "updates enterprise plan" $ do
                enterpriseId <- createTestEnterprise

                let payload = object
                        [ "plan" .= ("enterprise" :: Text)
                        , "max_users" .= (200 :: Int)
                        , "max_projects" .= (100 :: Int)
                        , "max_storage" .= (2000 :: Int)
                        ]

                putJSON ("/api/v1/enterprises/" <> enterpriseId <> "/plan") payload
                    `shouldRespondWith` 200
                    { matchBody = bodyContains ["enterprise", "200"]
                    }

        describe "GET /api/v1/enterprises/:enterprise_id/limits" $ do
            it "gets enterprise usage limits" $ do
                enterpriseId <- createTestEnterprise

                get ("/api/v1/enterprises/" <> enterpriseId <> "/limits")
                    `shouldRespondWith` 200
                    { matchBody = bodyContains ["users", "projects", "storage"]
                    }

        describe "PUT /api/v1/enterprises/:enterprise_id/branding" $ do
            it "updates enterprise branding" $ do
                enterpriseId <- createTestEnterprise

                let payload = object
                        [ "branding" .= object
                            [ "logo_url" .= ("https://example.com/logo.png" :: Text)
                            , "primary_color" .= ("#FF0000" :: Text)
                            ]
                        ]

                putJSON ("/api/v1/enterprises/" <> enterpriseId <> "/branding") payload
                    `shouldRespondWith` 200

        describe "GET /api/v1/enterprises/:enterprise_id/branding" $ do
            it "gets enterprise branding" $ do
                enterpriseId <- createTestEnterprise

                get ("/api/v1/enterprises/" <> enterpriseId <> "/branding")
                    `shouldRespondWith` 200

        describe "PUT /api/v1/enterprises/:enterprise_id/settings" $ do
            it "updates enterprise settings" $ do
                enterpriseId <- createTestEnterprise

                let payload = object
                        [ "settings" .= object
                            [ "feature_flags" .= object
                                [ "advanced_security" .= True
                                , "custom_workflows" .= True
                                ]
                            ]
                        ]

                putJSON ("/api/v1/enterprises/" <> enterpriseId <> "/settings") payload
                    `shouldRespondWith` 200

        describe "GET /api/v1/enterprises/:enterprise_id/settings" $ do
            it "gets enterprise settings" $ do
                enterpriseId <- createTestEnterprise

                get ("/api/v1/enterprises/" <> enterpriseId <> "/settings")
                    `shouldRespondWith` 200

-- Helper functions

createTestEnterprise :: WaiSession Text
createTestEnterprise = do
    let payload = object
            [ "name" .= ("Test Enterprise" :: Text)
            , "domain" .= ("test-" <> uniqueId <> ".enterprise.com" :: Text)
            , "plan" .= ("pro" :: Text)
            , "settings" .= object []
            ]

    response <- postJSON "/api/v1/enterprises" payload
    let Just enterpriseId = getField "enterprise_id" response
    return enterpriseId
  where
    uniqueId = "test-" <> T.pack (show (hash payload))

bodyContains :: [Text] -> MatchBody
bodyContains fields = MatchBody $ \body ->
    case decode body of
        Nothing -> Just "Response was not valid JSON"
        Just obj -> case all (flip hasField obj) fields of
            True -> Nothing
            False -> Just $ "Response missing required fields: " <> show fields

bodyContainsArray :: Int -> MatchBody
bodyContainsArray expectedLength = MatchBody $ \body ->
    case decode body of
        Nothing -> Just "Response was not valid JSON"
        Just arr -> case length arr == expectedLength of
            True -> Nothing
            False -> Just $ "Array length " <> show (length arr) <>
                          " did not match expected " <> show expectedLength
