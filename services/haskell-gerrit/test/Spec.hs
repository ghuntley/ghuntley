-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Main (main) where

import Test.Hspec
import Test.QuickCheck
import Database.Persist.Postgresql
import Control.Monad.Logger (runStderrLoggingT)
import Control.Monad.Reader (runReaderT)
import Data.Text (Text)
import Data.Time (getCurrentTime)
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive)
import System.FilePath ((</>))

import Gerrit.Models.Types
import Gerrit.Git.Operations
import Gerrit.Auth.JWT
import qualified Gerrit.Database.Connection as DB

-- | Test configuration
data TestConfig = TestConfig
    { testDbPool :: ConnectionPool
    , testGitPath :: FilePath
    , testJWTConfig :: JWTConfig
    }

-- | Initialize test environment
setupTestEnv :: IO TestConfig
setupTestEnv = do
    -- Create test database connection
    pool <- runStderrLoggingT $ createPostgresqlPool
        "host=localhost dbname=gerrit_test user=gerrit password=gerrit_password port=5432"
        1

    -- Create test Git directory
    let gitPath = "test-repos"
    createDirectoryIfMissing True gitPath

    -- Create JWT config
    let jwtConfig = JWTConfig
            { jwtSecret = "test-secret"
            , jwtExpiry = 3600
            }

    return TestConfig
        { testDbPool = pool
        , testGitPath = gitPath
        , testJWTConfig = jwtConfig
        }

-- | Clean up test environment
teardownTestEnv :: TestConfig -> IO ()
teardownTestEnv TestConfig{..} = do
    -- Close database connections
    destroyAllResources testDbPool
    -- Remove test Git directory
    removeDirectoryRecursive testGitPath

-- | Main test suite
main :: IO ()
main = do
    config <- setupTestEnv
    hspec $ after_ (teardownTestEnv config) $ do
        describe "Git Operations" $ do
            it "should initialize a repository" $ do
                result <- runGitTest config $ do
                    initRepository (testGitPath config) "test-project"
                case result of
                    Left err -> fail $ show err
                    Right _ -> return ()

            it "should create a change" $ do
                result <- runGitTest config $ do
                    repo <- initRepository (testGitPath config) "test-project"
                    createChange repo "change-1" "feature-branch"
                case result of
                    Left err -> fail $ show err
                    Right _ -> return ()

            it "should handle rebasing" $ do
                result <- runGitTest config $ do
                    repo <- initRepository (testGitPath config) "test-project"
                    -- Create master branch with some commits
                    liftIO $ writeFile (testGitPath config </> "test-project/file1.txt") "master content"
                    withRepository repo $ do
                        git ["add", "file1.txt"]
                        git ["commit", "-m", "Initial commit"]

                    -- Create feature branch
                    createChange repo "change-1" "feature-branch"
                    liftIO $ writeFile (testGitPath config </> "test-project/file2.txt") "feature content"
                    withRepository repo $ do
                        git ["add", "file2.txt"]
                        git ["commit", "-m", "Feature commit"]

                    -- Update master
                    withRepository repo $ do
                        git ["checkout", "master"]
                        liftIO $ writeFile (testGitPath config </> "test-project/file1.txt") "updated master content"
                        git ["add", "file1.txt"]
                        git ["commit", "-m", "Master update"]

                    -- Rebase feature branch
                    rebaseChange repo "feature-branch" "master"
                case result of
                    Left err -> fail $ show err
                    Right _ -> return ()

            it "should handle cherry-picking" $ do
                result <- runGitTest config $ do
                    repo <- initRepository (testGitPath config) "test-project"
                    -- Create source branch with a commit
                    createChange repo "change-1" "source-branch"
                    liftIO $ writeFile (testGitPath config </> "test-project/file1.txt") "source content"
                    withRepository repo $ do
                        git ["add", "file1.txt"]
                        git ["commit", "-m", "Source commit"]
                        commitHash <- git ["rev-parse", "HEAD"]

                        -- Create target branch and cherry-pick
                        git ["checkout", "-b", "target-branch"]
                        cherryPick repo (T.strip commitHash)
                case result of
                    Left err -> fail $ show err
                    Right _ -> return ()

            it "should handle conflicts" $ do
                result <- runGitTest config $ do
                    repo <- initRepository (testGitPath config) "test-project"
                    -- Create conflicting changes
                    liftIO $ writeFile (testGitPath config </> "test-project/conflict.txt") "original"
                    withRepository repo $ do
                        git ["add", "conflict.txt"]
                        git ["commit", "-m", "Initial commit"]

                        -- Create branch with changes
                        git ["checkout", "-b", "feature"]
                        liftIO $ writeFile (testGitPath config </> "test-project/conflict.txt") "feature change"
                        git ["add", "conflict.txt"]
                        git ["commit", "-m", "Feature change"]

                        -- Create conflicting change in master
                        git ["checkout", "master"]
                        liftIO $ writeFile (testGitPath config </> "test-project/conflict.txt") "master change"
                        git ["add", "conflict.txt"]
                        git ["commit", "-m", "Master change"]

                        -- Try to merge (should fail)
                        mergeResult <- runExceptT $ mergeChange repo "feature" "master"
                        liftIO $ case mergeResult of
                            Left (MergeConflict _) -> return ()
                            _ -> fail "Expected merge conflict"

                        -- Get conflicts
                        conflicts <- getConflicts repo
                        liftIO $ length conflicts `shouldBe` 1

                        -- Resolve conflict
                        resolveConflicts repo "conflict.txt" "resolved content"
                case result of
                    Left err -> fail $ show err
                    Right _ -> return ()

            it "should handle change statistics" $ do
                result <- runGitTest config $ do
                    repo <- initRepository (testGitPath config) "test-project"
                    -- Create some changes
                    liftIO $ do
                        writeFile (testGitPath config </> "test-project/file1.txt") "content 1"
                        writeFile (testGitPath config </> "test-project/file2.txt") "content 2"
                    withRepository repo $ do
                        git ["add", "."]
                        git ["commit", "-m", "Initial commit"]
                        initialCommit <- git ["rev-parse", "HEAD"]

                        -- Modify files
                        liftIO $ do
                            writeFile (testGitPath config </> "test-project/file1.txt") "updated content 1\nmore content"
                            writeFile (testGitPath config </> "test-project/file2.txt") "updated content 2"
                            writeFile (testGitPath config </> "test-project/file3.txt") "new file"
                        git ["add", "."]
                        git ["commit", "-m", "Update files"]

                        -- Get stats
                        stats <- getChangeStats repo (T.strip initialCommit) "HEAD"
                        liftIO $ do
                            gsFilesChanged stats `shouldBe` 3
                            gsInsertions stats `shouldBe` 3
                            gsDeletions stats `shouldBe` 2
                case result of
                    Left err -> fail $ show err
                    Right _ -> return ()

        describe "JWT Authentication" $ do
            it "should generate and verify tokens" $ do
                now <- getCurrentTime
                let user = User
                        { userEmail = "test@example.com"
                        , userName = "Test User"
                        , userPasswordHash = "hash"
                        , userIsAdmin = False
                        , userCreatedAt = now
                        }
                token <- generateToken (testJWTConfig config) user
                result <- runExceptT $ verifyToken (testJWTConfig config) token
                case result of
                    Left err -> fail $ show err
                    Right claims -> do
                        gcEmail claims `shouldBe` userEmail user
                        gcIsAdmin claims `shouldBe` userIsAdmin user

        describe "Database Operations" $ do
            it "should create and retrieve a user" $ do
                now <- getCurrentTime
                let user = User
                        { userEmail = "test@example.com"
                        , userName = "Test User"
                        , userPasswordHash = "hash"
                        , userIsAdmin = False
                        , userCreatedAt = now
                        }
                runDbTest config $ do
                    userId <- insert user
                    muser <- get userId
                    liftIO $ muser `shouldBe` Just user

            it "should create and retrieve a project" $ do
                now <- getCurrentTime
                runDbTest config $ do
                    -- Create test user
                    userId <- insert User
                        { userEmail = "test@example.com"
                        , userName = "Test User"
                        , userPasswordHash = "hash"
                        , userIsAdmin = False
                        , userCreatedAt = now
                        }
                    -- Create project
                    projectId <- insert Project
                        { projectName = "test-project"
                        , projectDescription = Just "Test project"
                        , projectOwnerUserId = userId
                        , projectCreatedAt = now
                        }
                    mproject <- get projectId
                    liftIO $ case mproject of
                        Nothing -> fail "Project not found"
                        Just project -> do
                            projectName project `shouldBe` "test-project"
                            projectDescription project `shouldBe` Just "Test project"

-- Helper functions

-- | Run a Git operation test
runGitTest :: TestConfig -> ExceptT GitError IO a -> IO (Either GitError a)
runGitTest _ = runExceptT

-- | Run a database operation test
runDbTest :: TestConfig -> SqlPersistT IO a -> IO a
runDbTest config = runSqlPool `flip` testDbPool config
