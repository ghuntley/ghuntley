-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Git.Operations
    ( initRepository
    , createChange
    , updateChange
    , fetchChange
    , mergeChange
    , getDiff
    , getPatch
    , getFileContent
    , getFileHistory
    , GitError(..)
    , GitDiff(..)
    , GitPatch(..)
    , GitFileHistory(..)
    , rebaseChange
    , cherryPick
    , resolveConflicts
    , getConflicts
    , abandonChange
    , restoreChange
    , getChangeStats
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Except (ExceptT, throwError, runExceptT)
import Data.Text (Text)
import qualified Data.Text as T
import System.Git.Simple
import System.FilePath ((</>))
import System.Directory (createDirectoryIfMissing)
import Data.Time.Clock (UTCTime, posixSecondsToUTCTime)
import Data.List (splitOn)

-- | Possible Git operation errors
data GitError
    = RepositoryNotFound Text
    | BranchNotFound Text
    | CommitError Text
    | MergeConflict Text
    | InvalidReference Text
    | GitCommandError Text
    deriving (Show, Eq)

-- | Git diff information
data GitDiff = GitDiff
    { gdOldPath :: Text
    , gdNewPath :: Text
    , gdOldMode :: Text
    , gdNewMode :: Text
    , gdHunks :: [DiffHunk]
    } deriving (Show, Eq)

-- | A hunk in a diff
data DiffHunk = DiffHunk
    { dhOldStart :: Int
    , dhOldCount :: Int
    , dhNewStart :: Int
    , dhNewCount :: Int
    , dhLines :: [DiffLine]
    } deriving (Show, Eq)

-- | A line in a diff hunk
data DiffLine = DiffLine
    { dlType :: DiffLineType
    , dlContent :: Text
    } deriving (Show, Eq)

-- | Type of a diff line
data DiffLineType = Context | Addition | Deletion
    deriving (Show, Eq)

-- | Git patch information
data GitPatch = GitPatch
    { gpCommitHash :: Text
    , gpAuthor :: Text
    , gpDate :: UTCTime
    , gpSubject :: Text
    , gpDiffs :: [GitDiff]
    } deriving (Show)

-- | Git file history
data GitFileHistory = GitFileHistory
    { fhPath :: Text
    , fhCommits :: [GitCommit]
    } deriving (Show)

-- | Git commit information
data GitCommit = GitCommit
    { gcHash :: Text
    , gcAuthor :: Text
    , gcDate :: UTCTime
    , gcSubject :: Text
    } deriving (Show)

-- | Git conflict information
data GitConflict = GitConflict
    { gcFile :: Text
    , gcMarkers :: [ConflictMarker]
    } deriving (Show, Eq)

-- | A conflict marker in a file
data ConflictMarker = ConflictMarker
    { cmStart :: Int
    , cmEnd :: Int
    , cmType :: ConflictType
    , cmContent :: Text
    } deriving (Show, Eq)

-- | Type of conflict marker
data ConflictType = Ours | Theirs | Base
    deriving (Show, Eq)

-- | Git change statistics
data GitStats = GitStats
    { gsFilesChanged :: Int
    , gsInsertions :: Int
    , gsDeletions :: Int
    , gsRenames :: Int
    } deriving (Show, Eq)

-- | Initialize a new Git repository for a project
initRepository :: MonadIO m => FilePath -> Text -> ExceptT GitError m Repository
initRepository baseDir projectName = do
    let repoPath = baseDir </> T.unpack projectName
    liftIO $ createDirectoryIfMissing True repoPath
    repo <- liftIO $ initGitRepository repoPath
    -- Initialize with empty commit to establish master branch
    withRepository repo $ do
        void $ git ["commit", "--allow-empty", "-m", "Initial commit"]
        git ["checkout", "-b", "master"]
    return repo

-- | Create a new change (branch) from master
createChange :: MonadIO m
             => Repository
             -> Text  -- ^ Change ID
             -> Text  -- ^ Branch name
             -> ExceptT GitError m ()
createChange repo changeId branchName = do
    withRepository repo $ do
        -- Ensure we're on master and it's up to date
        git ["checkout", "master"]
        git ["pull", "origin", "master"]

        -- Create new branch for the change
        let changeBranch = "changes/" <> branchName
        git ["checkout", "-b", changeBranch]

        -- Add change ID to commit message template
        let changeIdMsg = "Change-Id: " <> changeId
        liftIO $ writeFile (repoPath repo </> ".git" </> "hooks" </> "commit-msg") changeIdMsg

-- | Update an existing change with new commits
updateChange :: MonadIO m
             => Repository
             -> Text  -- ^ Branch name
             -> ExceptT GitError m ()
updateChange repo branchName = do
    withRepository repo $ do
        let changeBranch = "changes/" <> branchName
        exists <- doesBranchExist changeBranch
        unless exists $ throwError $ BranchNotFound branchName
        git ["checkout", changeBranch]

-- | Fetch a change from remote
fetchChange :: MonadIO m
            => Repository
            -> Text  -- ^ Change reference
            -> ExceptT GitError m ()
fetchChange repo changeRef = do
    withRepository repo $ do
        git ["fetch", "origin", changeRef]

-- | Merge a change into the target branch (usually master)
mergeChange :: MonadIO m
            => Repository
            -> Text  -- ^ Source branch
            -> Text  -- ^ Target branch
            -> ExceptT GitError m ()
mergeChange repo sourceBranch targetBranch = do
    withRepository repo $ do
        -- Switch to target branch
        git ["checkout", targetBranch]

        -- Try to merge
        result <- runExceptT $ git ["merge", "--no-ff", sourceBranch]
        case result of
            Left err -> throwError $ MergeConflict $ T.pack $ show err
            Right _ -> return ()

-- | Get the diff between two commits or trees
getDiff :: MonadIO m
        => Repository
        -> Text  -- ^ Old revision
        -> Text  -- ^ New revision
        -> ExceptT GitError m [GitDiff]
getDiff repo oldRev newRev = do
    withRepository repo $ do
        -- Get raw diff output
        output <- git ["diff", "--no-color", oldRev, newRev]
        -- Parse diff output
        case parseDiff output of
            Left err -> throwError $ GitCommandError err
            Right diffs -> return diffs

-- | Get a patch for a commit
getPatch :: MonadIO m
         => Repository
         -> Text  -- ^ Commit hash
         -> ExceptT GitError m GitPatch
getPatch repo commitHash = do
    withRepository repo $ do
        -- Get commit info
        info <- git ["show", "--no-color", "--format=%H%n%an%n%at%n%s", commitHash]
        let [hash, author, timestamp, subject] = lines info

        -- Get diff
        diffs <- getDiff repo (hash <> "^") hash

        -- Parse timestamp
        time <- case reads timestamp of
            [(t, "")] -> return $ posixSecondsToUTCTime (fromIntegral t)
            _ -> throwError $ GitCommandError "Invalid timestamp format"

        return GitPatch
            { gpCommitHash = hash
            , gpAuthor = author
            , gpDate = time
            , gpSubject = subject
            , gpDiffs = diffs
            }

-- | Get the content of a file at a specific revision
getFileContent :: MonadIO m
               => Repository
               -> Text  -- ^ Revision
               -> Text  -- ^ File path
               -> ExceptT GitError m Text
getFileContent repo rev path = do
    withRepository repo $ do
        git ["show", rev <> ":" <> path]

-- | Get the history of a file
getFileHistory :: MonadIO m
               => Repository
               -> Text  -- ^ File path
               -> ExceptT GitError m GitFileHistory
getFileHistory repo path = do
    withRepository repo $ do
        -- Get log output
        output <- git ["log", "--format=%H%n%an%n%at%n%s", "--", path]

        -- Parse commits
        commits <- forM (splitCommits output) $ \commitLines -> do
            case commitLines of
                [hash, author, timestamp, subject] -> do
                    time <- case reads timestamp of
                        [(t, "")] -> return $ posixSecondsToUTCTime (fromIntegral t)
                        _ -> throwError $ GitCommandError "Invalid timestamp format"
                    return GitCommit
                        { gcHash = hash
                        , gcAuthor = author
                        , gcDate = time
                        , gcSubject = subject
                        }
                _ -> throwError $ GitCommandError "Invalid log format"

        return GitFileHistory
            { fhPath = path
            , fhCommits = commits
            }

-- Helper functions

-- | Check if a branch exists
doesBranchExist :: MonadIO m => Text -> m Bool
doesBranchExist branch = do
    result <- runExceptT $ git ["rev-parse", "--verify", branch]
    return $ case result of
        Left _ -> False
        Right _ -> True

-- | Run a Git command and handle errors
git :: MonadIO m => [Text] -> ExceptT GitError m Text
git args = do
    result <- liftIO $ runGit args
    case result of
        Left err -> throwError $ GitCommandError $ T.pack $ show err
        Right output -> return output

-- | Rebase a change onto a target branch
rebaseChange :: MonadIO m
             => Repository
             -> Text  -- ^ Source branch
             -> Text  -- ^ Target branch
             -> ExceptT GitError m ()
rebaseChange repo sourceBranch targetBranch = do
    withRepository repo $ do
        -- Switch to source branch
        git ["checkout", sourceBranch]

        -- Try to rebase
        result <- runExceptT $ git ["rebase", targetBranch]
        case result of
            Left err -> do
                -- Abort rebase on failure
                _ <- runExceptT $ git ["rebase", "--abort"]
                throwError $ GitCommandError $ T.pack $ show err
            Right _ -> return ()

-- | Cherry-pick a commit onto the current branch
cherryPick :: MonadIO m
           => Repository
           -> Text  -- ^ Commit hash to cherry-pick
           -> ExceptT GitError m ()
cherryPick repo commitHash = do
    withRepository repo $ do
        result <- runExceptT $ git ["cherry-pick", commitHash]
        case result of
            Left err -> do
                -- Abort cherry-pick on failure
                _ <- runExceptT $ git ["cherry-pick", "--abort"]
                throwError $ GitCommandError $ T.pack $ show err
            Right _ -> return ()

-- | Parse git diff output into structured diff information
parseDiff :: Text -> Either Text [GitDiff]
parseDiff input = do
    let blocks = T.splitOn "diff --git " input
    traverse parseBlock $ filter (not . T.null) blocks
  where
    parseBlock :: Text -> Either Text GitDiff
    parseBlock block = do
        let ls = T.lines block
        case ls of
            [] -> Left "Empty diff block"
            (header:rest) -> do
                (oldPath, newPath) <- parseHeader header
                (oldMode, newMode, hunks) <- parseContent rest
                return GitDiff
                    { gdOldPath = oldPath
                    , gdNewPath = newPath
                    , gdOldMode = oldMode
                    , gdNewMode = newMode
                    , gdHunks = hunks
                    }

    parseHeader :: Text -> Either Text (Text, Text)
    parseHeader line = case T.words line of
        [_a, oldFile, _b, newFile] -> Right
            ( T.drop 2 oldFile  -- Remove "a/"
            , T.drop 2 newFile  -- Remove "b/"
            )
        _ -> Left $ "Invalid diff header: " <> line

    parseContent :: [Text] -> Either Text (Text, Text, [DiffHunk])
    parseContent ls = do
        let (modeLines, rest) = span (T.isPrefixOf "index ") ls
        (oldMode, newMode) <- case modeLines of
            [modeLine] -> parseModes modeLine
            _ -> Right ("100644", "100644")  -- Default modes
        hunks <- parseHunks rest
        return (oldMode, newMode, hunks)

    parseModes :: Text -> Either Text (Text, Text)
    parseModes line = case T.words line of
        (_:modes:_) -> case T.splitOn ".." modes of
            [old, new] -> Right (old, new)
            _ -> Left $ "Invalid mode line: " <> line
        _ -> Left $ "Invalid mode line: " <> line

    parseHunks :: [Text] -> Either Text [DiffHunk]
    parseHunks [] = Right []
    parseHunks ls = do
        let (hunkHeader:hunkLines, rest) = break (T.isPrefixOf "@@ ") $ dropWhile (not . T.isPrefixOf "@@ ") ls
        hunk <- parseHunk hunkHeader hunkLines
        hunks <- parseHunks rest
        return $ hunk : hunks

    parseHunk :: Text -> [Text] -> Either Text DiffHunk
    parseHunk header lines = do
        (oldStart, oldCount, newStart, newCount) <- parseHunkHeader header
        diffLines <- traverse parseDiffLine lines
        return DiffHunk
            { dhOldStart = oldStart
            , dhOldCount = oldCount
            , dhNewStart = newStart
            , dhNewCount = newCount
            , dhLines = diffLines
            }

    parseHunkHeader :: Text -> Either Text (Int, Int, Int, Int)
    parseHunkHeader header = case T.splitOn " @@ " header of
        [range, _] -> case T.splitOn " " $ T.drop 3 range of
            [old, new] -> do
                (oldStart, oldCount) <- parseRange old
                (newStart, newCount) <- parseRange new
                return (oldStart, oldCount, newStart, newCount)
            _ -> Left $ "Invalid hunk header: " <> header
        _ -> Left $ "Invalid hunk header: " <> header

    parseRange :: Text -> Either Text (Int, Int)
    parseRange range = case T.splitOn "," $ T.drop 1 range of
        [start, count] -> case (reads $ T.unpack start, reads $ T.unpack count) of
            ([(s, "")], [(c, "")]) -> Right (s, c)
            _ -> Left $ "Invalid range: " <> range
        [start] -> case reads $ T.unpack start of
            [(s, "")] -> Right (s, 1)
            _ -> Left $ "Invalid range: " <> range
        _ -> Left $ "Invalid range: " <> range

    parseDiffLine :: Text -> Either Text DiffLine
    parseDiffLine line
        | T.null line = Right $ DiffLine Context ""
        | otherwise = case T.head line of
            '+' -> Right $ DiffLine Addition $ T.tail line
            '-' -> Right $ DiffLine Deletion $ T.tail line
            ' ' -> Right $ DiffLine Context $ T.tail line
            _ -> Left $ "Invalid diff line: " <> line

-- | Split git log output into commits
splitCommits :: Text -> [[Text]]
splitCommits = map lines . splitOn "\n\n" . T.strip

-- | Get conflicts in the current branch
getConflicts :: MonadIO m
             => Repository
             -> ExceptT GitError m [GitConflict]
getConflicts repo = do
    withRepository repo $ do
        -- Get list of conflicted files
        files <- git ["diff", "--name-only", "--diff-filter=U"]
        forM (T.lines files) $ \file -> do
            -- Get conflict markers for each file
            content <- git ["cat-file", "-p", ":" <> file]
            return GitConflict
                { gcFile = file
                , gcMarkers = parseConflictMarkers content
                }

-- | Resolve conflicts in a file
resolveConflicts :: MonadIO m
                 => Repository
                 -> Text  -- ^ File path
                 -> Text  -- ^ Resolved content
                 -> ExceptT GitError m ()
resolveConflicts repo file content = do
    withRepository repo $ do
        -- Write resolved content
        liftIO $ writeFile (repoPath repo </> T.unpack file) (T.unpack content)
        -- Stage the resolved file
        git ["add", file]

-- | Abandon a change
abandonChange :: MonadIO m
              => Repository
              -> Text  -- ^ Branch name
              -> ExceptT GitError m ()
abandonChange repo branch = do
    withRepository repo $ do
        -- Check if branch exists
        exists <- doesBranchExist branch
        unless exists $ throwError $ BranchNotFound branch
        -- Delete the branch
        git ["branch", "-D", branch]

-- | Restore an abandoned change
restoreChange :: MonadIO m
              => Repository
              -> Text  -- ^ Branch name
              -> Text  -- ^ Commit hash
              -> ExceptT GitError m ()
restoreChange repo branch commit = do
    withRepository repo $ do
        -- Create new branch from commit
        git ["branch", branch, commit]

-- | Get change statistics
getChangeStats :: MonadIO m
               => Repository
               -> Text  -- ^ Old revision
               -> Text  -- ^ New revision
               -> ExceptT GitError m GitStats
getChangeStats repo oldRev newRev = do
    withRepository repo $ do
        -- Get diff stats
        output <- git ["diff", "--numstat", oldRev, newRev]
        let stats = parseStats output
        return GitStats
            { gsFilesChanged = length $ T.lines output
            , gsInsertions = sum $ map fst stats
            , gsDeletions = sum $ map snd stats
            , gsRenames = countRenames output
            }

-- Helper functions

-- | Parse conflict markers from file content
parseConflictMarkers :: Text -> [ConflictMarker]
parseConflictMarkers content = go (T.lines content) 1 []
  where
    go [] _ acc = reverse acc
    go (l:ls) n acc
        | "<<<<<<< " `T.isPrefixOf` l = parseOurs ls (n + 1) acc
        | otherwise = go ls (n + 1) acc

    parseOurs ls n acc = case break ("=======" `T.isPrefixOf`) ls of
        (oursLines, sep:rest) -> parseTheirs rest (n + length oursLines + 1)
            (ConflictMarker n (n + length oursLines) Ours (T.unlines oursLines) : acc)
        _ -> reverse acc  -- Malformed conflict marker

    parseTheirs ls n acc = case break (">>>>>>> " `T.isPrefixOf`) ls of
        (theirsLines, end:rest) -> go rest (n + length theirsLines + 1)
            (ConflictMarker n (n + length theirsLines) Theirs (T.unlines theirsLines) : acc)
        _ -> reverse acc  -- Malformed conflict marker

-- | Parse diff stats from git output
parseStats :: Text -> [(Int, Int)]
parseStats = map parseLine . T.lines
  where
    parseLine line = case T.words line of
        [adds, dels, _] -> (read $ T.unpack adds, read $ T.unpack dels)
        _ -> (0, 0)

-- | Count renames in diff output
countRenames :: Text -> Int
countRenames = length . filter isRename . T.lines
  where
    isRename line = case T.words line of
        [_, _, path] -> " => " `T.isInfixOf` path
        _ -> False
