-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.VCS.Git
    ( Git(..)
    , GitConfig(..)
    , initGitRepo
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Exception (throwIO)
import Data.Text (Text)
import qualified Data.Text as T
import System.Process (rawSystem, readProcess)
import System.FilePath ((</>))
import System.Directory (createDirectoryIfMissing)
import Data.Time.Clock (getCurrentTime)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Time.Format (formatTime, defaultTimeLocale)
import Data.Maybe (catMaybes, mapMaybe)
import Data.List (isPrefixOf, splitOn)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import System.Exit (ExitCode(..))

import Gerrit.VCS.Types

-- | Git implementation
data Git = Git
    { gitConfig :: GitConfig
    }

-- | Git-specific configuration
data GitConfig = GitConfig
    { gcCore :: VCSConfig  -- Common config
    , gcDefaultBranch :: Text
    , gcSignCommits :: Bool
    , gcPushOptions :: [Text]
    }

-- | Initialize a new Git repository
initGitRepo :: MonadIO m => FilePath -> Git -> m Repository
initGitRepo path git = do
    -- Create directory if it doesn't exist
    liftIO $ createDirectoryIfMissing True path

    -- Initialize Git repository
    exitCode <- liftIO $ rawSystem "git" ["-C", path, "init"]
    case exitCode of
        ExitSuccess -> do
            -- Configure repository
            let config = gitConfig git
            liftIO $ do
                rawSystem "git" ["-C", path, "config", "user.name", T.unpack $ vcUser $ gcCore config]
                rawSystem "git" ["-C", path, "config", "user.email", T.unpack $ vcEmail $ gcCore config]
                rawSystem "git" ["-C", path, "config", "init.defaultBranch", T.unpack $ gcDefaultBranch config]

                -- Initialize metrics
                now <- getCurrentTime
                pure $ Repository
                    { repoPath = path
                    , repoType = Git
                    , repoConfig = gcCore config
                    , repoMetrics = RepositoryMetrics
                        { rmCommitCount = 0
                        , rmBranchCount = 1  -- main branch
                        , rmContributorCount = 0
                        , rmLastActivity = now
                        , rmStorageSize = 0
                        }
                    }
        ExitFailure code ->
            throwIO $ VCSException $ "Git init failed with code: " <> T.pack (show code)

instance MonadIO m => VCS Git m where
    clone git url path = do
        exitCode <- liftIO $ rawSystem "git" ["clone", T.unpack url, path]
        case exitCode of
            ExitSuccess -> initGitRepo path git
            ExitFailure code ->
                throwIO $ VCSException $ "Git clone failed with code: " <> T.pack (show code)

    commit git repo msg files = do
        -- Stage files
        forM_ files $ \file -> do
            liftIO $ rawSystem "git" ["-C", repoPath repo, "add", file]

        -- Create commit
        let args = ["commit", "-m", T.unpack msg]
                    <> ["--gpg-sign" | gcSignCommits (gitConfig git)]
        exitCode <- liftIO $ rawSystem "git" (["-C", repoPath repo] ++ args)
        case exitCode of
            ExitSuccess -> do
                output <- liftIO $ readProcess "git" ["-C", repoPath repo, "rev-parse", "HEAD"] ""
                pure $ CommitId $ T.strip $ T.pack output
            ExitFailure code ->
                throwIO $ VCSException $ "Git commit failed with code: " <> T.pack (show code)

    checkout git repo ref = do
        let refStr = case ref of
                Branch name -> T.unpack name
                Tag name -> T.unpack name
                Commit (CommitId hash) -> T.unpack hash
                WorkingCopy -> error "Cannot checkout WorkingCopy reference"

        exitCode <- liftIO $ rawSystem "git" ["-C", repoPath repo, "checkout", refStr]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "Git checkout failed with code: " <> T.pack (show code)

    push git repo remote branch = do
        let args = ["push", T.unpack (remoteName remote), T.unpack (branchName branch)]
                    <> map T.unpack (gcPushOptions $ gitConfig git)
        exitCode <- liftIO $ rawSystem "git" (["-C", repoPath repo] ++ args)
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "Git push failed with code: " <> T.pack (show code)

    pull git repo remote branch = do
        exitCode <- liftIO $ rawSystem "git" ["-C", repoPath repo, "pull",
                                            T.unpack (remoteName remote),
                                            T.unpack (branchName branch)]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "Git pull failed with code: " <> T.pack (show code)

    createBranch git repo name = do
        exitCode <- liftIO $ rawSystem "git" ["-C", repoPath repo, "branch", T.unpack name]
        case exitCode of
            ExitSuccess -> do
                hash <- liftIO $ readProcess "git" ["-C", repoPath repo, "rev-parse", T.unpack name] ""
                pure $ Branch name (CommitId $ T.strip $ T.pack hash) Nothing
            ExitFailure code ->
                throwIO $ VCSException $ "Git branch creation failed with code: " <> T.pack (show code)

    deleteBranch git repo name = do
        exitCode <- liftIO $ rawSystem "git" ["-C", repoPath repo, "branch", "-D", T.unpack name]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "Git branch deletion failed with code: " <> T.pack (show code)

    listBranches git repo = do
        output <- liftIO $ readProcess "git" ["-C", repoPath repo, "branch", "--format=%(refname:short)"] ""
        let branches = lines output
        forM branches $ \branch -> do
            hash <- liftIO $ readProcess "git" ["-C", repoPath repo, "rev-parse", branch] ""
            upstream <- liftIO $ do
                result <- readProcess "git" ["-C", repoPath repo, "rev-parse", "--abbrev-ref", branch <> "@{upstream}"] ""
                pure $ if null result then Nothing else Just $ T.strip $ T.pack result
            pure $ Branch (T.pack branch) (CommitId $ T.strip $ T.pack hash) upstream

    status git repo = do
        output <- liftIO $ readProcess "git" ["-C", repoPath repo, "status", "--porcelain"] ""
        let parseStatus [] = RepoStatus [] [] [] [] []
            parseStatus (line:rest) =
                let (status, file) = splitAt 2 line
                    current = parseStatus rest
                in case status of
                    "M " -> current { rsModified = file : rsModified current }
                    "A " -> current { rsAdded = file : rsAdded current }
                    "D " -> current { rsDeleted = file : rsDeleted current }
                    "??" -> current { rsUntracked = file : rsUntracked current }
                    "UU" -> current { rsConflicted = file : rsConflicted current }
                    _ -> current
        pure $ parseStatus $ lines output

    isClean git repo = do
        status <- status git repo
        pure $ null (rsModified status) &&
               null (rsAdded status) &&
               null (rsDeleted status) &&
               null (rsUntracked status) &&
               null (rsConflicted status)

    log git repo opts = do
        let formatOpts = ["log", "--format=%H%n%an%n%ae%n%at%n%P%n%s%n%b%n---%n"]
            countOpts = maybe [] (\n -> ["-n", show n]) (loMaxCount opts)
            skipOpts = maybe [] (\n -> ["--skip", show n]) (loSkip opts)
            pathOpts = maybe [] (\p -> ["--", p]) (loPath opts)
            authorOpts = maybe [] (\a -> ["--author", T.unpack a]) (loAuthor opts)
            dateOpts = catMaybes
                [ fmap (\t -> "--since=" ++ formatTime defaultTimeLocale "%Y-%m-%d" t) (loSince opts)
                , fmap (\t -> "--until=" ++ formatTime defaultTimeLocale "%Y-%m-%d" t) (loUntil opts)
                ]
            args = formatOpts ++ countOpts ++ skipOpts ++ authorOpts ++ dateOpts ++ pathOpts

        output <- liftIO $ readProcess "git" (["-C", repoPath repo] ++ args) ""
        pure $ parseGitLog output

    diff git repo ref1 ref2 = do
        let ref1Str = formatReference ref1
            ref2Str = formatReference ref2
            args = ["diff", "--unified=3", ref1Str, ref2Str]

        output <- liftIO $ readProcess "git" (["-C", repoPath repo] ++ args) ""
        pure $ parseGitDiff output

    blame git repo file = do
        let args = ["blame", "-p", file]
        output <- liftIO $ readProcess "git" (["-C", repoPath repo] ++ args) ""
        pure $ parseGitBlame output

-- Helper functions

-- | Parse git log output into Commit objects
parseGitLog :: String -> [Commit]
parseGitLog output =
    let blocks = splitOn "---\n" output
        parseBlock block =
            case lines block of
                (hash:author:email:timestamp:parents:subject:body) ->
                    Just $ Commit
                        { commitId = CommitId $ T.pack hash
                        , commitAuthor = T.pack author
                        , commitEmail = T.pack email
                        , commitDate = parseUnixTime (read timestamp)
                        , commitMessage = T.pack $ unlines (subject:body)
                        , commitParents = map (CommitId . T.pack) (words parents)
                        , commitFiles = []  -- TODO: Add file list parsing
                        }
                _ -> Nothing
    in mapMaybe parseBlock blocks

-- | Parse git diff output into Diff objects
parseGitDiff :: String -> [Diff]
parseGitDiff output =
    let chunks = splitOn "diff --git " output
        parseChunk chunk =
            case lines chunk of
                (_:oldFile:newFile:hunks) ->
                    Just $ Diff
                        { diffOldFile = parseGitPath oldFile
                        , diffNewFile = parseGitPath newFile
                        , diffHunks = parseHunks hunks
                        }
                _ -> Nothing
    in mapMaybe parseChunk chunks

-- | Parse git blame output into BlameInfo
parseGitBlame :: String -> BlameInfo
parseGitBlame output =
    let lines' = lines output
        -- Parse header line
        (hash:origLine:resultLine:authorInfo) = words $ head lines'
        -- Parse author info
        author = unwords $ takeWhile (/= "(") $ drop 3 authorInfo
        -- Parse timestamp
        timestamp = read $ filter (/= ')') $ last authorInfo
        -- Get content
        content = unwords $ tail lines'
    in BlameInfo
        { blameCommit = CommitId $ T.pack hash
        , blameAuthor = T.pack author
        , blameDate = parseUnixTime timestamp
        , blameLine = read resultLine
        , blameContent = T.pack content
        }

-- | Parse a git file path from diff output
parseGitPath :: String -> FilePath
parseGitPath path = case words path of
    -- Handle "a/" and "b/" prefixes in diff output
    ["a/", file] -> file
    ["b/", file] -> file
    -- Handle renamed files
    [old, "->", new] -> new  -- Use new name for renamed files
    -- Default case
    _ -> dropWhile (`elem` "ab/") path

-- | Parse hunks from diff output
parseHunks :: [String] -> [DiffHunk]
parseHunks [] = []
parseHunks (line:rest) = case parseHunkHeader line of
    Just (oldStart, oldCount, newStart, newCount) ->
        let (hunkLines, remaining) = span (not . isHunkHeader) rest
            hunk = DiffHunk
                { dhOldStart = oldStart
                , dhOldCount = oldCount
                , dhNewStart = newStart
                , dhNewCount = newCount
                , dhLines = parseDiffLines hunkLines
                }
        in hunk : parseHunks remaining
    Nothing -> parseHunks rest

-- | Parse a diff hunk header (e.g., "@@ -1,3 +1,4 @@")
parseHunkHeader :: String -> Maybe (Int, Int, Int, Int)
parseHunkHeader line = case splitOn "@@ " line of
    [_, range, _] -> case splitOn " " range of
        [old, new] -> do
            let oldRange = parseRange (drop 1 old)  -- drop the '-'
                newRange = parseRange (drop 1 new)  -- drop the '+'
            case (oldRange, newRange) of
                (Just (os, oc), Just (ns, nc)) -> Just (os, oc, ns, nc)
                _ -> Nothing
        _ -> Nothing
    _ -> Nothing

-- | Parse a range like "1,3" into (start, count)
parseRange :: String -> Maybe (Int, Int)
parseRange s = case splitOn "," s of
    [start, count] -> Just (read start, read count)
    [single] -> Just (read single, 1)  -- Handle single line changes
    _ -> Nothing

-- | Parse diff lines into DiffLine types
parseDiffLines :: [String] -> [DiffLine]
parseDiffLines = mapMaybe parseDiffLine

-- | Parse a single diff line
parseDiffLine :: String -> Maybe DiffLine
parseDiffLine line = case line of
    [] -> Nothing
    (c:content) -> case c of
        ' ' -> Just $ DiffContext $ T.pack content
        '+' -> Just $ DiffAdded $ T.pack content
        '-' -> Just $ DiffRemoved $ T.pack content
        _ -> Nothing

-- | Check if a line is a hunk header
isHunkHeader :: String -> Bool
isHunkHeader = isPrefixOf "@@ -"

-- | Format a reference for git commands
formatReference :: Reference -> String
formatReference ref = case ref of
    Branch name -> T.unpack name
    Tag name -> T.unpack name
    Commit (CommitId hash) -> T.unpack hash
    WorkingCopy -> "HEAD"

-- | Parse Unix timestamp into UTCTime
parseUnixTime :: Integer -> UTCTime
parseUnixTime = posixSecondsToUTCTime . fromIntegral
