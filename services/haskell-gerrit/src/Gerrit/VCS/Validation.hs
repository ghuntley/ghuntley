-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.VCS.Validation
    ( ValidationSystem(..)
    , ValidationRunner(..)
    , ValidationHook(..)
    , ValidationContext(..)
    , initValidationRunner
    , addHook
    , removeHook
    , runValidations
    ) where

import Control.Concurrent.Async (mapConcurrently)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import System.Process (readProcessWithExitCode)
import System.Exit (ExitCode(..))
import System.Timeout (timeout)

import Gerrit.VCS.Types

-- | Validation hook
data ValidationHook = ValidationHook
    { vhName :: Text
    , vhCommand :: Text
    , vhTimeout :: Int  -- in seconds
    , vhRequired :: Bool
    , vhEnvironment :: [(Text, Text)]  -- environment variables
    }

-- | Validation context
data ValidationContext = ValidationContext
    { vcRepository :: Repository
    , vcSource :: Reference
    , vcTarget :: Reference
    , vcWorkspace :: FilePath
    }

-- | Validation runner
data ValidationRunner = ValidationRunner
    { vrHooks :: [ValidationHook]
    , vrMaxConcurrent :: Int
    }

-- | Initialize validation runner
initValidationRunner :: MonadIO m => Int -> m ValidationRunner
initValidationRunner maxConcurrent =
    pure $ ValidationRunner [] maxConcurrent

-- | Add a validation hook
addHook :: MonadIO m => ValidationRunner -> ValidationHook -> m ValidationRunner
addHook runner hook =
    pure $ runner { vrHooks = hook : vrHooks runner }

-- | Remove a validation hook
removeHook :: MonadIO m => ValidationRunner -> Text -> m ValidationRunner
removeHook runner name =
    pure $ runner { vrHooks = filter ((/= name) . vhName) $ vrHooks runner }

-- | Run all validations
runValidations :: MonadIO m => ValidationRunner -> ValidationContext -> m [ValidationResult]
runValidations runner context = liftIO $ do
    let hooks = vrHooks runner
        maxConcurrent = vrMaxConcurrent runner

    -- Run validations concurrently with max limit
    results <- mapConcurrently (runValidation context) hooks

    -- Update validation status
    now <- getCurrentTime
    pure results

-- | Run a single validation
runValidation :: ValidationContext -> ValidationHook -> IO ValidationResult
runValidation context hook = do
    startTime <- getCurrentTime

    -- Prepare environment variables
    let env = prepareEnvironment context hook

    -- Run validation command with timeout
    result <- timeout (vhTimeout hook * 1000000) $ do
        (exitCode, stdout, stderr) <- readProcessWithExitCode
            "sh"
            ["-c", T.unpack $ vhCommand hook]
            ""

        pure $ case exitCode of
            ExitSuccess ->
                ValidationSuccess
            ExitFailure code ->
                ValidationFailure $ T.pack $
                    "Exit code " ++ show code ++ "\n" ++
                    "stdout: " ++ stdout ++ "\n" ++
                    "stderr: " ++ stderr

    endTime <- getCurrentTime

    -- Create validation check result
    pure $ case result of
        Just r -> ValidationCheck
            { vcName = vhName hook
            , vcStatus = case r of
                ValidationSuccess -> Passed
                ValidationFailure _ -> Failed
            , vcOutput = case r of
                ValidationSuccess -> "Validation passed"
                ValidationFailure msg -> msg
            , vcStarted = startTime
            , vcCompleted = Just endTime
            }
        Nothing -> ValidationCheck
            { vcName = vhName hook
            , vcStatus = Failed
            , vcOutput = "Validation timed out"
            , vcStarted = startTime
            , vcCompleted = Just endTime
            }

-- | Prepare environment variables for validation
prepareEnvironment :: ValidationContext -> ValidationHook -> [(String, String)]
prepareEnvironment ValidationContext{..} ValidationHook{..} =
    -- Convert hook environment variables
    map (\(k, v) -> (T.unpack k, T.unpack v)) vhEnvironment ++
    -- Add context variables
    [ ("GERRIT_REPOSITORY", T.unpack $ T.pack $ repoPath vcRepository)
    , ("GERRIT_SOURCE_REF", T.unpack $ T.pack $ show vcSource)
    , ("GERRIT_TARGET_REF", T.unpack $ T.pack $ show vcTarget)
    , ("GERRIT_WORKSPACE", vcWorkspace)
    ]

-- | Default validation hooks
defaultHooks :: [ValidationHook]
defaultHooks =
    [ ValidationHook
        { vhName = "build"
        , vhCommand = "make build"
        , vhTimeout = 300  -- 5 minutes
        , vhRequired = True
        , vhEnvironment = []
        }
    , ValidationHook
        { vhName = "test"
        , vhCommand = "make test"
        , vhTimeout = 600  -- 10 minutes
        , vhRequired = True
        , vhEnvironment = []
        }
    , ValidationHook
        { vhName = "lint"
        , vhCommand = "make lint"
        , vhTimeout = 60  -- 1 minute
        , vhRequired = False
        , vhEnvironment = []
        }
    ]
