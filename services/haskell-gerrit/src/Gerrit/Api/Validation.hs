{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Validation
    ( -- * Validation
      ValidationError(..)
    , ValidationRule(..)
    , validate
      -- * Rules
    , contentTypeRule
    , contentLengthRule
    , paginationRule
    , changeRequestRule
    , commentRequestRule
    , voteRequestRule
    ) where

import Control.Monad (unless, when)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Network.HTTP.Types (HeaderName)
import Network.Wai (Request, requestHeaders, requestMethod, requestBody)
import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

import Gerrit.Api.Types
import Gerrit.Api.Config (Config(..))
import Gerrit.Api.Metrics (Metrics(..), incrementValidationErrors)

-- | Validation error
data ValidationError = ValidationError
    { errorCode :: Text
    , errorMessage :: Text
    } deriving (Show, Eq)

-- | Validation rule
data ValidationRule = ValidationRule
    { ruleName :: Text
    , ruleDescription :: Text
    , ruleValidate :: Metrics -> Config -> Request -> IO (Maybe ValidationError)
    }

-- | Validate a request against a list of rules
validate :: Metrics -> Config -> Request -> [ValidationRule] -> IO (Maybe ValidationError)
validate metrics config req rules = do
    results <- mapM (\rule -> ruleValidate rule metrics config req) rules
    let error = head $ filter (/= Nothing) results
    when (error /= Nothing) $
        incrementValidationErrors metrics
    return error

-- | Content type validation rule
contentTypeRule :: ValidationRule
contentTypeRule = ValidationRule
    { ruleName = "content-type"
    , ruleDescription = "Validates the Content-Type header"
    , ruleValidate = \_ _ req -> do
        let method = requestMethod req
        let contentType = lookup "Content-Type" (requestHeaders req)

        if method `elem` ["POST", "PUT", "PATCH"]
            then case contentType of
                Nothing -> return $ Just $ ValidationError
                    "INVALID_CONTENT_TYPE"
                    "Content-Type header is required for POST/PUT/PATCH requests"
                Just ct -> if "application/json" `BS.isInfixOf` ct
                    then return Nothing
                    else return $ Just $ ValidationError
                        "INVALID_CONTENT_TYPE"
                        "Content-Type must be application/json"
            else return Nothing
    }

-- | Content length validation rule
contentLengthRule :: ValidationRule
contentLengthRule = ValidationRule
    { ruleName = "content-length"
    , ruleDescription = "Validates the request body size"
    , ruleValidate = \_ config req -> do
        let contentLength = lookup "Content-Length" (requestHeaders req)
        case contentLength of
            Nothing -> return Nothing
            Just len -> do
                let size = read $ BS.unpack len
                if size > configMaxUploadSize config
                    then return $ Just $ ValidationError
                        "REQUEST_TOO_LARGE"
                        "Request body exceeds maximum allowed size"
                    else return Nothing
    }

-- | Pagination validation rule
paginationRule :: ValidationRule
paginationRule = ValidationRule
    { ruleName = "pagination"
    , ruleDescription = "Validates pagination parameters"
    , ruleValidate = \_ _ req -> do
        let query = queryString req
        let offset = lookup "offset" query >>= readMaybe . BS.unpack
        let limit = lookup "limit" query >>= readMaybe . BS.unpack

        case (offset, limit) of
            (Just o, _) | o < 0 -> return $ Just $ ValidationError
                "INVALID_OFFSET"
                "Offset must be non-negative"
            (_, Just l) | l <= 0 -> return $ Just $ ValidationError
                "INVALID_LIMIT"
                "Limit must be positive"
            (_, Just l) | l > 100 -> return $ Just $ ValidationError
                "INVALID_LIMIT"
                "Limit cannot exceed 100"
            _ -> return Nothing
    }

-- | Change request validation rule
changeRequestRule :: ValidationRule
changeRequestRule = ValidationRule
    { ruleName = "change-request"
    , ruleDescription = "Validates change creation requests"
    , ruleValidate = \_ _ req -> do
        if requestMethod req == "POST" && "/api/v1/changes" `BS.isInfixOf` rawPathInfo req
            then do
                body <- strictRequestBody req
                case eitherDecode body of
                    Left err -> return $ Just $ ValidationError
                        "INVALID_CHANGE_REQUEST"
                        (Text.pack $ "Invalid change request: " ++ err)
                    Right (req :: CreateChangeRequest) -> validateChangeRequest req
            else return Nothing
    }

-- | Comment request validation rule
commentRequestRule :: ValidationRule
commentRequestRule = ValidationRule
    { ruleName = "comment-request"
    , ruleDescription = "Validates comment creation requests"
    , ruleValidate = \_ _ req -> do
        if requestMethod req == "POST" && "/comments" `BS.isInfixOf` rawPathInfo req
            then do
                body <- strictRequestBody req
                case eitherDecode body of
                    Left err -> return $ Just $ ValidationError
                        "INVALID_COMMENT_REQUEST"
                        (Text.pack $ "Invalid comment request: " ++ err)
                    Right (req :: CreateCommentRequest) -> validateCommentRequest req
            else return Nothing
    }

-- | Vote request validation rule
voteRequestRule :: ValidationRule
voteRequestRule = ValidationRule
    { ruleName = "vote-request"
    , ruleDescription = "Validates vote creation requests"
    , ruleValidate = \_ _ req -> do
        if requestMethod req == "POST" && "/votes" `BS.isInfixOf` rawPathInfo req
            then do
                body <- strictRequestBody req
                case eitherDecode body of
                    Left err -> return $ Just $ ValidationError
                        "INVALID_VOTE_REQUEST"
                        (Text.pack $ "Invalid vote request: " ++ err)
                    Right (req :: CreateVoteRequest) -> validateVoteRequest req
            else return Nothing
    }

-- | Helper functions

validateChangeRequest :: CreateChangeRequest -> IO (Maybe ValidationError)
validateChangeRequest CreateChangeRequest{..} = do
    -- Validate project ID
    when (Text.null projectId) $
        return $ Just $ ValidationError
            "INVALID_PROJECT_ID"
            "Project ID cannot be empty"

    -- Validate branch name
    when (Text.null branch) $
        return $ Just $ ValidationError
            "INVALID_BRANCH"
            "Branch name cannot be empty"

    -- Validate subject
    when (Text.null subject) $
        return $ Just $ ValidationError
            "INVALID_SUBJECT"
            "Subject cannot be empty"

    -- Validate description length
    when (maybe False ((> 10000) . Text.length) description) $
        return $ Just $ ValidationError
            "DESCRIPTION_TOO_LONG"
            "Description cannot exceed 10000 characters"

    return Nothing

validateCommentRequest :: CreateCommentRequest -> IO (Maybe ValidationError)
validateCommentRequest CreateCommentRequest{..} = do
    -- Validate message
    when (Text.null message) $
        return $ Just $ ValidationError
            "INVALID_MESSAGE"
            "Comment message cannot be empty"

    when (Text.length message > 10000) $
        return $ Just $ ValidationError
            "MESSAGE_TOO_LONG"
            "Comment message cannot exceed 10000 characters"

    -- Validate file path for inline comments
    when (commentType == Inline && Text.null file) $
        return $ Just $ ValidationError
            "INVALID_FILE_PATH"
            "File path is required for inline comments"

    return Nothing

validateVoteRequest :: CreateVoteRequest -> IO (Maybe ValidationError)
validateVoteRequest CreateVoteRequest{..} = do
    -- Validate vote value range
    unless (value >= -2 && value <= 2) $
        return $ Just $ ValidationError
            "INVALID_VOTE_VALUE"
            "Vote value must be between -2 and 2"

    -- Validate message length if provided
    when (maybe False ((> 1000) . Text.length) message) $
        return $ Just $ ValidationError
            "MESSAGE_TOO_LONG"
            "Vote message cannot exceed 1000 characters"

    return Nothing
