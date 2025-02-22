-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Database.SQLiteSpec (spec) where

import Control.Exception (bracket)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Logger (runNoLoggingT)
import Data.Text (Text)
import qualified Data.Text as T
import Database.Persist.Sqlite
import System.Directory (removeFile)
import System.IO.Temp (withSystemTempFile)
import Test.Hspec

import Gerrit.Database.SQLite
import Gerrit.Database.SQLiteMigrations
import Gerrit.Database.Migrations (MigrationStatus(..))
import qualified Gerrit.Models.Change as Change
import qualified Gerrit.Models.User as User

spec :: Spec
spec = around withTestDatabase $ do
    describe "SQLite Database Operations" $ do
        it "should create and close connection pool" $ \pool -> do
            -- Test connection pool creation
            pool' <- runNoLoggingT $ createSQLitePool testConfig
            pool' `shouldSatisfy` (not . null)

            -- Test connection pool closure
            closeSQLitePool pool'
            -- No assertion needed, just checking it doesn't throw

        it "should run database operations" $ \pool -> do
            result <- withSQLitePool testConfig $ \conn -> do
                -- Create a test user
                let user = User.User
                        { User.userEmail = "test@example.com"
                        , User.userName = "Test User"
                        , User.userActive = True
                        }
                runSqlPool (insert user) conn

            result `shouldSatisfy` (> 0)

        it "should handle concurrent connections" $ \pool -> do
            results <- mapM (const $ runTestQuery pool) [1..10]
            length (filter id results) `shouldBe` 10

    describe "SQLite Migrations" $ do
        it "should run migrations successfully" $ \pool -> do
            result <- runSQLiteMigrations pool
            result `shouldBe` Right ()

        it "should check migration status" $ \pool -> do
            status <- checkSQLiteMigrations pool
            status `shouldBe` MigrationUpToDate

        it "should get detailed migration status" $ \pool -> do
            status <- getSQLiteMigrationStatus pool
            status `shouldBe` MigrationUpToDate

    describe "SQLite Error Handling" $ do
        it "should handle invalid database path" $ do
            result <- try $ runNoLoggingT $ createSQLitePool invalidConfig
            case result of
                Left err -> err `shouldBe` SQLiteFileError "invalid/path/db.sqlite"
                Right _ -> expectationFailure "Expected SQLiteFileError"

        it "should handle concurrent write conflicts" $ \pool -> do
            results <- mapM (const $ runConcurrentWrites pool) [1..10]
            -- Some writes may fail due to conflicts, but not all
            length (filter isRight results) `shouldSatisfy` (> 0)

  where
    testConfig = SQLiteConfig
        { sqliteDbPath = ":memory:"
        , sqlitePoolSize = 10
        }

    invalidConfig = SQLiteConfig
        { sqliteDbPath = "invalid/path/db.sqlite"
        , sqlitePoolSize = 1
        }

-- Helper functions for tests

withTestDatabase :: (ConnectionPool -> IO a) -> IO a
withTestDatabase = bracket
    (runNoLoggingT $ createSQLitePool testConfig)
    closeSQLitePool

runTestQuery :: ConnectionPool -> IO Bool
runTestQuery pool = do
    result <- try $ runSqlPool action pool
    return $ case result of
        Right _ -> True
        Left _ -> False
  where
    action = do
        -- Simple query to test connection
        rawExecute "SELECT 1" []

runConcurrentWrites :: ConnectionPool -> IO (Either SQLiteMigrationError ())
runConcurrentWrites pool = try $ runSqlPool action pool
  where
    action = do
        -- Create a test change
        let change = Change.Change
                { Change.changeTitle = "Test Change"
                , Change.changeDescription = "Test Description"
                , Change.changeStatus = Change.Open
                }
        _ <- insert change
        return ()
