-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.VCS.JJ
    ( JJ(..)
    , JJConfig(..)
    , Workspace(..)
    , Template(..)
    , ConflictResolutionStyle(..)
    , initJJRepo
    , createWorkspace
    , switchWorkspace
    , rebaseInteractive
    , squashRange
    , resolveConflict
    , listConflicts
    , defineTemplate
    , applyTemplate
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Exception (throwIO)
import Data.Text (Text)
import qualified Data.Text as T
import System.Process (rawSystem, readProcess)
import System.FilePath ((</>))
import System.Directory (createDirectoryIfMissing)
import Data.Time.Clock (getCurrentTime, UTCTime)
import Data.Time.Format (formatTime, defaultTimeLocale)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Aeson
import Data.Aeson.Lens
import Data.Maybe (catMaybes, mapMaybe)
import Data.List (isPrefixOf)
import Data.List.Split (splitOn)
import Control.Lens ((^.), (^..), (^?))
import Data.String (fromString)

import Gerrit.VCS.Types

-- | jj implementation
data JJ = JJ
    { jjConfig :: JJConfig
    , jjWorkspaces :: Map WorkspaceName Workspace
    }

-- | jj-specific configuration
data JJConfig = JJConfig
    { jcCore :: VCSConfig  -- Common config
    , jcTemplates :: Map TemplateName Template
    , jcDefaultWorkspace :: WorkspaceName
    , jcConflictStyle :: ConflictResolutionStyle
    }

-- | Workspace information
data Workspace = Workspace
    { wsName :: WorkspaceName
    , wsPath :: FilePath
    , wsActive :: Bool
    , wsLastSync :: UTCTime
    }

-- | Template for operations
data Template = Template
    { templateName :: TemplateName
    , templateDescription :: Text
    , templateCommands :: [Text]
    }

-- | Conflict resolution styles
data ConflictResolutionStyle
    = ResolveInteractive
    | ResolveAcceptMine
    | ResolveAcceptTheirs
    | ResolveMerge
    deriving (Show, Eq)

type WorkspaceName = Text
type TemplateName = Text

-- | Initialize a new jj repository
initJJRepo :: MonadIO m => FilePath -> JJ -> m Repository
initJJRepo path jj = do
    -- Create directory if it doesn't exist
    liftIO $ createDirectoryIfMissing True path

    -- Initialize jj repository
    exitCode <- liftIO $ rawSystem "jj" ["init", path]
    case exitCode of
        ExitSuccess -> do
            -- Configure repository
            let config = jjConfig jj
            liftIO $ do
                -- Configure user
                writeFile (path </> ".jj" </> "config.toml") $ unlines
                    [ "[user]"
                    , "name = " ++ show (T.unpack $ vcUser $ jcCore config)
                    , "email = " ++ show (T.unpack $ vcEmail $ jcCore config)
                    , "[workspace]"
                    , "default = " ++ show (T.unpack $ jcDefaultWorkspace config)
                    , "[conflict]"
                    , "style = " ++ show (jcConflictStyle config)
                    ]

                -- Initialize metrics
                now <- getCurrentTime
                pure $ Repository
                    { repoPath = path
                    , repoType = JJ
                    , repoConfig = jcCore config
                    , repoMetrics = RepositoryMetrics
                        { rmCommitCount = 0
                        , rmBranchCount = 1  -- default workspace
                        , rmContributorCount = 0
                        , rmLastActivity = now
                        , rmStorageSize = 0
                        }
                    }
        ExitFailure code ->
            throwIO $ VCSException $ "jj init failed with code: " <> T.pack (show code)

instance MonadIO m => VCS JJ m where
    clone jj url path = do
        exitCode <- liftIO $ rawSystem "jj" ["clone", T.unpack url, path]
        case exitCode of
            ExitSuccess -> initJJRepo path jj
            ExitFailure code ->
                throwIO $ VCSException $ "jj clone failed with code: " <> T.pack (show code)

    commit jj repo msg files = do
        -- Stage files
        forM_ files $ \file -> do
            liftIO $ rawSystem "jj" ["-R", repoPath repo, "add", file]

        -- Create commit
        exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "commit", "-m", T.unpack msg]
        case exitCode of
            ExitSuccess -> do
                output <- liftIO $ readProcess "jj" ["-R", repoPath repo, "rev-parse", "HEAD"] ""
                pure $ CommitId $ T.strip $ T.pack output
            ExitFailure code ->
                throwIO $ VCSException $ "jj commit failed with code: " <> T.pack (show code)

    checkout jj repo ref = do
        let refStr = case ref of
                Branch name -> T.unpack name
                Tag name -> T.unpack name
                Commit (CommitId hash) -> T.unpack hash
                WorkingCopy -> "@"

        exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "checkout", refStr]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "jj checkout failed with code: " <> T.pack (show code)

    push jj repo remote branch = do
        exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "push",
                                           T.unpack (remoteName remote),
                                           T.unpack (branchName branch)]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "jj push failed with code: " <> T.pack (show code)

    pull jj repo remote branch = do
        exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "pull",
                                           T.unpack (remoteName remote),
                                           T.unpack (branchName branch)]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "jj pull failed with code: " <> T.pack (show code)

    createBranch jj repo name = do
        exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "branch", "create", T.unpack name]
        case exitCode of
            ExitSuccess -> do
                hash <- liftIO $ readProcess "jj" ["-R", repoPath repo, "rev-parse", T.unpack name] ""
                pure $ Branch name (CommitId $ T.strip $ T.pack hash) Nothing
            ExitFailure code ->
                throwIO $ VCSException $ "jj branch creation failed with code: " <> T.pack (show code)

    deleteBranch jj repo name = do
        exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "branch", "delete", T.unpack name]
        case exitCode of
            ExitSuccess -> pure ()
            ExitFailure code ->
                throwIO $ VCSException $ "jj branch deletion failed with code: " <> T.pack (show code)

    listBranches jj repo = do
        output <- liftIO $ readProcess "jj" ["-R", repoPath repo, "branch", "list", "--format=json"] ""
        let branches = parseBranchesJson output  -- TODO: Implement JSON parsing
        pure branches

    status jj repo = do
        output <- liftIO $ readProcess "jj" ["-R", repoPath repo, "status", "--porcelain"] ""
        let parseStatus [] = RepoStatus [] [] [] [] []
            parseStatus (line:rest) =
                let (status, file) = splitAt 2 line
                    current = parseStatus rest
                in case status of
                    "M " -> current { rsModified = file : rsModified current }
                    "A " -> current { rsAdded = file : rsAdded current }
                    "D " -> current { rsDeleted = file : rsDeleted current }
                    "? " -> current { rsUntracked = file : rsUntracked current }
                    "U " -> current { rsConflicted = file : rsConflicted current }
                    _ -> current
        pure $ parseStatus $ lines output

    isClean jj repo = do
        status <- status jj repo
        pure $ null (rsModified status) &&
               null (rsAdded status) &&
               null (rsDeleted status) &&
               null (rsUntracked status) &&
               null (rsConflicted status)

    log jj repo opts = do
        let formatOpts = ["log", "--format=json"]
            countOpts = maybe [] (\n -> ["--limit", show n]) (loMaxCount opts)
            skipOpts = maybe [] (\n -> ["--skip", show n]) (loSkip opts)
            pathOpts = maybe [] (\p -> ["--", p]) (loPath opts)
            authorOpts = maybe [] (\a -> ["--author", T.unpack a]) (loAuthor opts)
            dateOpts = catMaybes
                [ fmap (\t -> "--since=" ++ formatTime defaultTimeLocale "%Y-%m-%d" t) (loSince opts)
                , fmap (\t -> "--until=" ++ formatTime defaultTimeLocale "%Y-%m-%d" t) (loUntil opts)
                ]
            args = formatOpts ++ countOpts ++ skipOpts ++ authorOpts ++ dateOpts ++ pathOpts

        output <- liftIO $ readProcess "jj" (["-R", repoPath repo] ++ args) ""
        pure $ parseJJLog output

    diff jj repo ref1 ref2 = do
        let ref1Str = formatReference ref1
            ref2Str = formatReference ref2
            args = ["diff", "--git", "-U", "3", ref1Str, ref2Str]

        output <- liftIO $ readProcess "jj" (["-R", repoPath repo] ++ args) ""
        pure $ parseJJDiff output

    blame jj repo file = do
        let args = ["blame", "--porcelain", file]
        output <- liftIO $ readProcess "jj" (["-R", repoPath repo] ++ args) ""
        pure $ parseJJBlame output

-- | jj-specific operations

-- | Create a new workspace
createWorkspace :: MonadIO m => JJ -> Repository -> WorkspaceName -> m Workspace
createWorkspace jj repo name = do
    now <- liftIO getCurrentTime
    let wsPath = repoPath repo </> T.unpack name
    exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "workspace", "new", T.unpack name]
    unless (exitCode == ExitSuccess) $
        throwIO $ VCSException "Workspace creation failed"
    pure $ Workspace name wsPath True now

-- | Switch to a different workspace
switchWorkspace :: MonadIO m => JJ -> Repository -> WorkspaceName -> m ()
switchWorkspace jj repo name = do
    exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "workspace", "switch", T.unpack name]
    unless (exitCode == ExitSuccess) $
        throwIO $ VCSException "Workspace switch failed"

-- | Interactive rebase
rebaseInteractive :: MonadIO m => JJ -> Repository -> CommitRange -> m ()
rebaseInteractive jj repo range = do
    exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "rebase", "-i", formatCommitRange range]
    unless (exitCode == ExitSuccess) $
        throwIO $ VCSException "Interactive rebase failed"

-- | Squash a range of commits
squashRange :: MonadIO m => JJ -> Repository -> CommitRange -> m CommitId
squashRange jj repo range = do
    exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "squash", formatCommitRange range]
    case exitCode of
        ExitSuccess -> do
            output <- liftIO $ readProcess "jj" ["-R", repoPath repo, "rev-parse", "HEAD"] ""
            pure $ CommitId $ T.strip $ T.pack output
        ExitFailure code ->
            throwIO $ VCSException $ "Squash failed with code: " <> T.pack (show code)

-- | Resolve a conflict
resolveConflict :: MonadIO m => JJ -> Repository -> FilePath -> ConflictResolution -> m ()
resolveConflict jj repo file resolution = do
    let resolutionArg = case resolution of
            ResolveAcceptMine -> "--accept-mine"
            ResolveAcceptTheirs -> "--accept-theirs"
            ResolveMerge -> "--merge"
            ResolveInteractive -> "--interactive"
    exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "resolve", resolutionArg, file]
    unless (exitCode == ExitSuccess) $
        throwIO $ VCSException "Conflict resolution failed"

-- | List conflicts
listConflicts :: MonadIO m => JJ -> Repository -> m [FilePath]
listConflicts jj repo = do
    output <- liftIO $ readProcess "jj" ["-R", repoPath repo, "status", "--conflicts"] ""
    pure $ lines output

-- | Define a new template
defineTemplate :: MonadIO m => JJ -> Repository -> Template -> m ()
defineTemplate jj repo template = do
    let templatePath = repoPath repo </> ".jj" </> "templates" </> T.unpack (templateName template)
    liftIO $ writeFile templatePath $ unlines $
        [ "# " ++ T.unpack (templateDescription template)
        ] ++ map T.unpack (templateCommands template)

-- | Apply a template
applyTemplate :: MonadIO m => JJ -> Repository -> TemplateName -> m ()
applyTemplate jj repo name = do
    exitCode <- liftIO $ rawSystem "jj" ["-R", repoPath repo, "template", "apply", T.unpack name]
    unless (exitCode == ExitSuccess) $
        throwIO $ VCSException "Template application failed"

-- Helper functions
formatCommitRange :: CommitRange -> String
formatCommitRange CommitRange{..} =
    let from = T.unpack $ unCommitId crFrom
        to = T.unpack $ unCommitId crTo
    in if crInclusive
        then from ++ ".." ++ to
        else from ++ "..." ++ to

parseJJLog :: String -> [Commit]
parseJJLog output = case eitherDecode (fromString output) of
    Left err -> error $ "Failed to parse jj log output: " ++ err
    Right commits -> map parseCommit commits
  where
    parseCommit obj = Commit
        { commitId = CommitId $ obj ^. key "id" . _String
        , commitAuthor = obj ^. key "author" . key "name" . _String
        , commitEmail = obj ^. key "author" . key "email" . _String
        , commitDate = parseISO8601 $ T.unpack $ obj ^. key "author" . key "time" . _String
        , commitMessage = obj ^. key "message" . _String
        , commitParents = map (CommitId . (^. _String)) $ obj ^.. key "parents" . values
        , commitFiles = map (^. _String) $ obj ^.. key "files" . values
        }

parseJJDiff :: String -> [Diff]
parseJJDiff output =
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

parseJJBlame :: String -> BlameInfo
parseJJBlame output =
    let (header:_) = lines output
        [hash, author, email, timestamp, lineNum] = words header
    in BlameInfo
        { blameCommit = CommitId $ T.pack hash
        , blameAuthor = T.pack author
        , blameDate = parseISO8601 timestamp
        , blameLine = read lineNum
        , blameContent = T.pack $ unwords $ drop 5 $ words header
        }

parseBranchesJson :: String -> [Branch]
parseBranchesJson output = case eitherDecode (fromString output) of
    Left err -> error $ "Failed to parse jj branches output: " ++ err
    Right branches -> map parseBranch branches
  where
    parseBranch obj = Branch
        { branchName = obj ^. key "name" . _String
        , branchCommit = CommitId $ obj ^. key "commit" . _String
        , branchUpstream = obj ^? key "upstream" . _String
        }

parseGitPath :: String -> FilePath
parseGitPath path = case words path of
    ["a/", file] -> file
    ["b/", file] -> file
    [old, "->", new] -> new
    _ -> dropWhile (`elem` "ab/") path

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

parseRange :: String -> Maybe (Int, Int)
parseRange s = case splitOn "," s of
    [start, count] -> Just (read start, read count)
    [single] -> Just (read single, 1)
    _ -> Nothing

parseDiffLines :: [String] -> [DiffLine]
parseDiffLines = mapMaybe parseDiffLine

parseDiffLine :: String -> Maybe DiffLine
parseDiffLine line = case line of
    [] -> Nothing
    (c:content) -> case c of
        ' ' -> Just $ DiffContext $ T.pack content
        '+' -> Just $ DiffAdded $ T.pack content
        '-' -> Just $ DiffRemoved $ T.pack content
        _ -> Nothing

isHunkHeader :: String -> Bool
isHunkHeader = isPrefixOf "@@ -"

formatReference :: Reference -> String
formatReference ref = case ref of
    Branch name -> T.unpack name
    Tag name -> T.unpack name
    Commit (CommitId hash) -> T.unpack hash
    WorkingCopy -> "@"

-- | Parse ISO8601 timestamp
parseISO8601 :: String -> UTCTime
parseISO8601 str = case iso8601ParseM str of
    Just t -> t
    Nothing -> error $ "Failed to parse ISO8601 timestamp: " ++ str
