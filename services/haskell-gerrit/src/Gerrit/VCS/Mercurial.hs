-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.VCS.Mercurial
    ( Mercurial(..)
    , MercurialConfig(..)
    , PhaseConfig(..)
    , Phase(..)
    , initMercurialRepo
    , createBundle
    , applyBundle
    , setPhase
    , getPhase
    , log
    , diff
    , blame
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

import Gerrit.VCS.Types

-- | Mercurial implementation
data Mercurial = Mercurial
    { mercurialConfig :: MercurialConfig
    , mercurialExtensions :: [Extension]
    }

-- | Mercurial-specific configuration
data MercurialConfig = MercurialConfig
    { mcCore :: VCSConfig  -- Common config
    , mcPhases :: PhaseConfig
    , mcBookmarks :: BookmarkConfig
    , mcMQ :: Maybe MQConfig
    }

-- | Phase configuration
data PhaseConfig = PhaseConfig
    { pcNewPhase :: Phase
    , pcPublishPhases :: Bool
    }

-- | Commit phases
data Phase = Draft | Public | Secret
    deriving (Show, Eq)

-- | Initialize a new Mercurial repository
initMercurialRepo :: MonadIO m => FilePath -> Mercurial -> m Repository
initMercurialRepo path merc = do
    -- Create directory if it doesn't exist
    liftIO $ createDirectoryIfMissing True path

    -- Initialize Mercurial repository
    exitCode <- liftIO $ rawSystem "hg" ["init", path]
    case exitCode of
        ExitSuccess -> do
            -- Configure repository
            let config = mercurialConfig merc
            liftIO $ do
                -- Configure user
                writeFile (path </> ".hg" </> "hgrc") $ unlines
                    [ "[ui]"
                    , "username = " ++ T.unpack (vcUser $ mcCore config) ++ " <" ++ T.unpack (vcEmail $ mcCore config) ++ ">"
                    , "[phases]"
                    , "new-commit = " ++ show (pcNewPhase $ mcPhases config)
                    , "publish = " ++ show (pcPublishPhases $ mcPhases config)
                    ]

                -- Enable extensions
                forM_ (mercurialExtensions merc) $ \ext ->
                    rawSystem "hg" ["--config", "extensions." ++ T.unpack ext ++ "="]

                -- Initialize metrics
                now <- getCurrentTime
                pure $ Repository
                    { repoPath = path
                    , repoType = Mercurial
                    , repoConfig = mcCore config
                    , repoMetrics = RepositoryMetrics
                        { rmCommitCount = 0
                        , rmBranchCount = 1  -- default branch
                        , rmContributorCount = 0
                        , rmLastActivity = now
                        , rmStorageSize = 0
                        }
                    }
        ExitFailure code ->
            throwIO $ VCSException $ "Mercurial init failed with code: " <> T.pack (show code)

instance MonadIO m => VCS Mercurial m where
    clone merc url path = do
        exitCode <- liftIO $ rawSystem "hg" ["clone", T.unpack url, path]
        case exitCode of
            ExitSuccess -> initMercurialRepo path merc
            ExitFailure code ->
                throwIO $ VCSException $ "Mercurial clone failed with code: " <> T.pack (show code)

    commit merc repo msg files = do
        -- Add files
        forM_ files $ \file -> do
            liftIO $ rawSystem "hg" ["-R", repoPath repo, "add", file]

        -- Create commit
        exitCode <- liftIO $ rawSystem "hg" ["-R", repoPath repo, "commit", "-m", T.unpack msg]
        case exitCode of
            ExitSuccess -> do
                output <- liftIO $ readProcess "hg" ["-R", repoPath repo, "identify", "--id"] ""
                pure $ CommitId $ T.strip $ T.pack output
            ExitFailure code ->
                throwIO $ VCSException $ "Mercurial commit failed with code: " <> T.pack (show code)

    checkout merc repo ref = do
        let refStr = case ref of
                Branch name -> T.unpack name
                Tag name -> T.unpack name
                Commit (CommitId hash) -> T.unpack hash
                WorkingCopy -> "tip"

        exitCode <- liftIO $ rawSystem "hg" ["-R", repoPath repo, "update", refStr]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "Mercurial update failed with code: " <> T.pack (show code)

    push merc repo remote branch = do
        exitCode <- liftIO $ rawSystem "hg" ["-R", repoPath repo, "push",
                                           "-r", T.unpack (branchName branch),
                                           T.unpack (remoteUrl remote)]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure 1 -> pure ()  -- Mercurial returns 1 when no changes to push
            ExitFailure code ->
                throwIO $ VCSException $ "Mercurial push failed with code: " <> T.pack (show code)

    pull merc repo remote branch = do
        exitCode <- liftIO $ rawSystem "hg" ["-R", repoPath repo, "pull",
                                           "-r", T.unpack (branchName branch),
                                           T.unpack (remoteUrl remote)]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "Mercurial pull failed with code: " <> T.pack (show code)

    createBranch merc repo name = do
        exitCode <- liftIO $ rawSystem "hg" ["-R", repoPath repo, "branch", T.unpack name]
        case exitCode of
            ExitSuccess -> do
                hash <- liftIO $ readProcess "hg" ["-R", repoPath repo, "identify", "--id"] ""
                pure $ Branch name (CommitId $ T.strip $ T.pack hash) Nothing
            ExitFailure code ->
                throwIO $ VCSException $ "Mercurial branch creation failed with code: " <> T.pack (show code)

    deleteBranch merc repo name = do
        -- In Mercurial, we close the branch instead of deleting it
        exitCode <- liftIO $ rawSystem "hg" ["-R", repoPath repo, "commit", "--close-branch", "-m", "Close branch " ++ T.unpack name]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "Mercurial branch closure failed with code: " <> T.pack (show code)

    listBranches merc repo = do
        output <- liftIO $ readProcess "hg" ["-R", repoPath repo, "branches", "--template", "{branch}\n{node}\n"] ""
        let pairs = chunksOf 2 $ lines output
        forM pairs $ \[branch, hash] -> do
            pure $ Branch (T.pack branch) (CommitId $ T.pack hash) Nothing

    status merc repo = do
        output <- liftIO $ readProcess "hg" ["-R", repoPath repo, "status"] ""
        let parseStatus [] = RepoStatus [] [] [] [] []
            parseStatus (line:rest) =
                let (status, file) = splitAt 2 line
                    current = parseStatus rest
                in case status of
                    "M" -> current { rsModified = file : rsModified current }
                    "A" -> current { rsAdded = file : rsAdded current }
                    "R" -> current { rsDeleted = file : rsDeleted current }
                    "?" -> current { rsUntracked = file : rsUntracked current }
                    "!" -> current { rsDeleted = file : rsDeleted current }
                    _ -> current
        pure $ parseStatus $ lines output

    isClean merc repo = do
        status <- status merc repo
        pure $ null (rsModified status) &&
               null (rsAdded status) &&
               null (rsDeleted status) &&
               null (rsUntracked status) &&
               null (rsConflicted status)

    log merc repo opts = do
        let formatOpts = ["log", "--template", "{node}\n{author}\n{email}\n{date|hgdate}\n{parents}\n{desc}\n{files}\n---\n"]
            countOpts = maybe [] (\n -> ["-l", show n]) (loMaxCount opts)
            skipOpts = maybe [] (\n -> ["--skip", show n]) (loSkip opts)
            pathOpts = maybe [] (\p -> ["--", p]) (loPath opts)
            authorOpts = maybe [] (\a -> ["--user", T.unpack a]) (loAuthor opts)
            dateOpts = catMaybes
                [ fmap (\t -> "--date", ">" ++ formatTime defaultTimeLocale "%Y-%m-%d" t) (loSince opts)
                , fmap (\t -> "--date", "<" ++ formatTime defaultTimeLocale "%Y-%m-%d" t) (loUntil opts)
                ]
            args = formatOpts ++ countOpts ++ skipOpts ++ authorOpts ++ dateOpts ++ pathOpts

        output <- liftIO $ readProcess "hg" (["-R", repoPath repo] ++ args) ""
        pure $ parseMercurialLog output

    diff merc repo ref1 ref2 = do
        let ref1Str = formatReference ref1
            ref2Str = formatReference ref2
            args = ["diff", "--git", "-U", "3", "-r", ref1Str, "-r", ref2Str]

        output <- liftIO $ readProcess "hg" (["-R", repoPath repo] ++ args) ""
        pure $ parseMercurialDiff output

    blame merc repo file = do
        let args = ["annotate", "-u", "-d", "-n", file]
        output <- liftIO $ readProcess "hg" (["-R", repoPath repo] ++ args) ""
        pure $ parseMercurialBlame output

-- | Mercurial-specific operations

-- | Create a bundle file
createBundle :: MonadIO m => Mercurial -> Repository -> [RevisionSet] -> FilePath -> m ()
createBundle merc repo revs path = do
    let revArgs = map formatRevSet revs
    exitCode <- liftIO $ rawSystem "hg" $
        ["-R", repoPath repo, "bundle", "--type=v2"] ++ revArgs ++ [path]
    unless (exitCode == ExitSuccess) $
        throwIO $ VCSException "Bundle creation failed"

-- | Apply a bundle file
applyBundle :: MonadIO m => Mercurial -> Repository -> FilePath -> m ()
applyBundle merc repo path = do
    exitCode <- liftIO $ rawSystem "hg" ["-R", repoPath repo, "unbundle", path]
    unless (exitCode == ExitSuccess) $
        throwIO $ VCSException "Bundle application failed"

-- | Set phase for revisions
setPhase :: MonadIO m => Mercurial -> Repository -> Phase -> [RevisionSet] -> m ()
setPhase merc repo phase revs = do
    let phaseStr = case phase of
            Draft -> "draft"
            Public -> "public"
            Secret -> "secret"
    let revArgs = map formatRevSet revs
    exitCode <- liftIO $ rawSystem "hg" $
        ["-R", repoPath repo, "phase", "--force", "--" ++ phaseStr] ++ revArgs
    unless (exitCode == ExitSuccess) $
        throwIO $ VCSException "Phase change failed"

-- | Get phase of a revision
getPhase :: MonadIO m => Mercurial -> Repository -> RevisionSet -> m Phase
getPhase merc repo rev = do
    output <- liftIO $ readProcess "hg" ["-R", repoPath repo, "phase", formatRevSet rev] ""
    case T.strip $ T.pack output of
        "draft" -> pure Draft
        "public" -> pure Public
        "secret" -> pure Secret
        _ -> throwIO $ VCSException "Invalid phase"

-- Helper functions
chunksOf :: Int -> [a] -> [[a]]
chunksOf n [] = []
chunksOf n xs = take n xs : chunksOf n (drop n xs)

formatRevSet :: RevisionSet -> String
formatRevSet rev = case rev of
    RevisionSingle (CommitId hash) -> T.unpack hash
    RevisionRange (CommitId from) (CommitId to) -> T.unpack from <> "::" <> T.unpack to
    RevisionBranch name -> "branch(" <> T.unpack name <> ")"
    RevisionBookmark name -> "bookmark(" <> T.unpack name <> ")"
    RevisionTag name -> "tag(" <> T.unpack name <> ")"
    RevisionSpecial name -> T.unpack name

-- | Parse Mercurial log output into Commit objects
parseMercurialLog :: String -> [Commit]
parseMercurialLog output =
    let blocks = splitOn "---\n" output
        parseBlock block =
            case lines block of
                (hash:author:email:dateStr:parents:desc:files) ->
                    let (timestamp, _) = break (== ' ') dateStr
                        parentHashes = words parents
                    in Just $ Commit
                        { commitId = CommitId $ T.pack hash
                        , commitAuthor = T.pack author
                        , commitEmail = T.pack email
                        , commitDate = posixSecondsToUTCTime $ fromIntegral (read timestamp :: Integer)
                        , commitMessage = T.pack desc
                        , commitParents = map (CommitId . T.pack) parentHashes
                        , commitFiles = map T.pack files
                        }
                _ -> Nothing
    in mapMaybe parseBlock blocks

-- | Parse Mercurial diff output into Diff objects
parseMercurialDiff :: String -> [Diff]
parseMercurialDiff output =
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

-- | Parse Mercurial blame output into BlameInfo
parseMercurialBlame :: String -> BlameInfo
parseMercurialBlame output =
    let (line:_) = lines output
        [hash, author, dateStr, lineNum, content] = words line
        timestamp = read $ takeWhile (/= '.') dateStr
    in BlameInfo
        { blameCommit = CommitId $ T.pack hash
        , blameAuthor = T.pack author
        , blameDate = posixSecondsToUTCTime $ fromIntegral timestamp
        , blameLine = read lineNum
        , blameContent = T.pack content
        }

-- | Parse a git-style file path from diff output
parseGitPath :: String -> FilePath
parseGitPath path = case words path of
    ["a/", file] -> file
    ["b/", file] -> file
    [old, "->", new] -> new
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

-- | Parse a diff hunk header
parseHunkHeader :: String -> Maybe (Int, Int, Int, Int)
parseHunkHeader line = case splitOn "@@ " line of
    [_, range, _] -> case splitOn " " range of
        [old, new] -> do
            let oldRange = parseRange (drop 1 old)
                newRange = parseRange (drop 1 new)
            case (oldRange, newRange) of
                (Just (os, oc), Just (ns, nc)) -> Just (os, oc, ns, nc)
                _ -> Nothing
        _ -> Nothing
    _ -> Nothing

-- | Parse a range like "1,3" into (start, count)
parseRange :: String -> Maybe (Int, Int)
parseRange s = case splitOn "," s of
    [start, count] -> Just (read start, read count)
    [single] -> Just (read single, 1)
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

-- | Format a reference for Mercurial commands
formatReference :: Reference -> String
formatReference ref = case ref of
    Branch name -> T.unpack name
    Tag name -> T.unpack name
    Commit (CommitId hash) -> T.unpack hash
    WorkingCopy -> "tip"
