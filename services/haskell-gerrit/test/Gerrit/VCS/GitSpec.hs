-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}

module Gerrit.VCS.GitSpec (spec) where

import Test.Hspec
import Test.QuickCheck
import System.IO.Temp (withSystemTempDirectory)
import Control.Monad.IO.Class (liftIO)
import Control.Monad (void, forM_)
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath ((</>))
import System.Directory (createDirectoryIfMissing, doesFileExist)
import Control.Exception (try)
import Data.List (isPrefixOf)

import Gerrit.VCS.Types
import Gerrit.VCS.Git

spec :: Spec
spec = do
    describe "Git VCS Implementation" $ do
        it "should initialize a new repository" $ do
            withSystemTempDirectory "git-test" $ \dir -> do
                let git = Git $ GitConfig
                        { gcCore = VCSConfig
                            { vcUser = "Test User"
                            , vcEmail = "test@example.com"
                            , vcSigningKey = Nothing
                            , vcRemotes = mempty
                            , vcHooks = []
                            , vcIgnorePatterns = []
                            }
                        , gcDefaultBranch = "main"
                        , gcSignCommits = False
                        , gcPushOptions = []
                        }
                repo <- initGitRepo dir git
                repoPath repo `shouldBe` dir
                repoType repo `shouldBe` Git

        it "should create and list branches" $ do
            withSystemTempDirectory "git-test" $ \dir -> do
                repo <- initTestRepo dir
                -- Create a test branch
                branch <- createBranch testGit repo "feature"
                branchName branch `shouldBe` "feature"
                -- List branches
                branches <- listBranches testGit repo
                length branches `shouldBe` 2  -- main and feature
                map branchName branches `shouldContain` ["main", "feature"]

        it "should commit changes" $ do
            withSystemTempDirectory "git-test" $ \dir -> do
                repo <- initTestRepo dir
                -- Create a test file
                let testFile = dir </> "test.txt"
                liftIO $ writeFile testFile "test content"
                -- Commit the file
                commitId <- commit testGit repo "Test commit" ["test.txt"]
                -- Verify the commit
                commits <- log testGit repo defaultLogOptions
                length commits `shouldBe` 2  -- Initial commit and our test commit
                let lastCommit = head commits
                commitMessage lastCommit `shouldContain` "Test commit"

        it "should handle merge conflicts" $ do
            withSystemTempDirectory "git-test" $ \dir -> do
                repo <- initTestRepo dir
                -- Create conflicting changes
                createConflictingChanges repo
                -- Try to merge
                result <- try $ merge testGit repo (Branch "feature")
                case result of
                    Left (MergeConflict files) -> length files `shouldBe` 1
                    _ -> expectationFailure "Expected merge conflict"

        it "should parse git blame output" $ do
            let blameOutput = unlines
                    [ "abc123 1 1 (Test User 2024-01-01 12:00:00 +0000) Test content"
                    , "Content line"
                    ]
            let blame = parseGitBlame blameOutput
            blameCommit blame `shouldBe` CommitId "abc123"
            blameAuthor blame `shouldBe` "Test User"
            blameLine blame `shouldBe` 1
            blameContent blame `shouldBe` "Content line"

        it "should parse git diff output" $ do
            let diffOutput = unlines
                    [ "diff --git a/test.txt b/test.txt"
                    , "@@ -1,3 +1,4 @@"
                    , " context line"
                    , "-removed line"
                    , "+added line"
                    , " another context"
                    ]
            let hunks = parseHunks $ lines diffOutput
            length hunks `shouldBe` 1
            let hunk = head hunks
            dhOldStart hunk `shouldBe` 1
            dhOldCount hunk `shouldBe` 3
            dhNewStart hunk `shouldBe` 1
            dhNewCount hunk `shouldBe` 4
            length (dhLines hunk) `shouldBe` 4

        it "should handle file operations" $ do
            withSystemTempDirectory "git-test" $ \dir -> do
                repo <- initTestRepo dir
                -- Create multiple files
                let files = ["file1.txt", "file2.txt", "file3.txt"]
                forM_ files $ \file -> do
                    writeFile (dir </> file) "test content"
                    void $ commit testGit repo ("Add " <> file) [file]

                -- Check status
                status <- status testGit repo
                rsModified status `shouldBe` []
                rsUntracked status `shouldBe` []

                -- Modify a file
                writeFile (dir </> "file1.txt") "modified content"
                status' <- status testGit repo
                rsModified status' `shouldBe` ["file1.txt"]

        it "should handle tags" $ do
            withSystemTempDirectory "git-test" $ \dir -> do
                repo <- initTestRepo dir
                -- Create a tag
                tag testGit repo "v1.0" (Just "Release v1.0")
                -- List tags
                tags <- listTags testGit repo
                tags `shouldContain` ["v1.0"]
                -- Checkout tag
                checkout testGit repo (Tag "v1.0")
                isClean <- isClean testGit repo
                isClean `shouldBe` True

        it "should handle remote operations" $ do
            withSystemTempDirectory "git-test" $ \dir -> do
                -- Create source and target repos
                srcRepo <- initTestRepo dir
                let targetDir = dir </> "target"
                createDirectoryIfMissing True targetDir
                targetRepo <- initTestRepo targetDir

                -- Add remote
                let remote = Remote
                        { remoteName = "origin"
                        , remoteUrl = T.pack targetDir
                        , remoteFetch = "+refs/heads/*:refs/remotes/origin/*"
                        , remotePush = "refs/heads/*:refs/heads/*"
                        }

                -- Push changes
                writeFile (dir </> "test.txt") "test content"
                void $ commit testGit srcRepo "Test commit" ["test.txt"]
                push testGit srcRepo remote (Branch "main")

                -- Pull changes in target
                pull testGit targetRepo remote (Branch "main")
                doesFileExist (targetDir </> "test.txt") `shouldReturn` True

        it "should handle cherry-pick operations" $ do
            withSystemTempDirectory "git-test" $ \dir -> do
                repo <- initTestRepo dir
                -- Create feature branch with changes
                void $ createBranch testGit repo "feature"
                void $ checkout testGit repo (Branch "feature")
                writeFile (dir </> "feature.txt") "feature content"
                commitId <- commit testGit repo "Feature commit" ["feature.txt"]

                -- Cherry-pick to main
                void $ checkout testGit repo (Branch "main")
                void $ cherryPick testGit repo commitId
                doesFileExist (dir </> "feature.txt") `shouldReturn` True

-- Helper functions

testGit :: Git
testGit = Git $ GitConfig
    { gcCore = VCSConfig
        { vcUser = "Test User"
        , vcEmail = "test@example.com"
        , vcSigningKey = Nothing
        , vcRemotes = mempty
        , vcHooks = []
        , vcIgnorePatterns = []
        }
    , gcDefaultBranch = "main"
    , gcSignCommits = False
    , gcPushOptions = []
    }

initTestRepo :: FilePath -> IO Repository
initTestRepo dir = do
    repo <- initGitRepo dir testGit
    -- Create initial commit
    let readmePath = dir </> "README.md"
    writeFile readmePath "# Test Repository"
    void $ commit testGit repo "Initial commit" ["README.md"]
    pure repo

createConflictingChanges :: Repository -> IO ()
createConflictingChanges repo = do
    let path = repoPath repo
        testFile = path </> "test.txt"

    -- Create feature branch with changes
    void $ createBranch testGit repo "feature"
    void $ checkout testGit repo (Branch "feature")
    writeFile testFile "feature branch content"
    void $ commit testGit repo "Feature branch commit" ["test.txt"]

    -- Create conflicting changes on main
    void $ checkout testGit repo (Branch "main")
    writeFile testFile "main branch content"
    void $ commit testGit repo "Main branch commit" ["test.txt"]

defaultLogOptions :: LogOptions
defaultLogOptions = LogOptions
    { loMaxCount = Nothing
    , loSkip = Nothing
    , loPath = Nothing
    , loAuthor = Nothing
    , loSince = Nothing
    , loUntil = Nothing
    }
